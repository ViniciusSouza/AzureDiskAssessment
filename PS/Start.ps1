#-------------------------------------------------------------------------
#
# Copyright (c) Microsoft Corporation. All rights reserved.
#
# THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, 
# EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES 
# OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
#---------------------------------------------------------------------------

param (
    [string]$TargetSubscriptionName,
    [string]$TargetResourceGroup,
    [Parameter(Mandatory=$true)][string]$ReportAzureSubscriptionName,
    [Parameter(Mandatory=$true)][string]$ReportAzureStorageResourceGroup,
    [Parameter(Mandatory=$true)][string]$ReportAzureStorageName
 )

 class DiskAssessment{

    [string]$TenantId
    [string]$tableName = "vmdisks"
     
    [int] tierStorageSize( [string]$storageTier,[int]$size) {
        if ($storageTier.Contains("Premium") -or $storageTier.Contains("Standard_HDD")){
            if ($size -lt 32){
                return 32
            }
            if ($size -lt 64){
                return 64
            }
        }
        if ($size -lt 128){
            return 128
        }
        if ($size -lt 256){
            return 256
        }   
        if ($size -lt 512){
            return 512
        }
        if ($size -lt 1024){
            return 1024
        }   
        if ($size -lt 2048){
            return 2048
        }
        if ($size -lt 4096){
            return 4096
        }   
        
        return -1
    }


    [string] tierStorageOffer([string]$storageTier, [int]$size) {
        $offer = ""
    
        if ($storageTier.Contains("Premium")){
            $offer = "P"
        }
        elseif ($storageTier.Contains("Standard_HDD")){
            $offer = "S"
        }
        elseif ($storageTier.Contains("Standard")){
            $offer = "E"
        }
        if ($size -lt 32){
            return $offer+"4"
        }
        if ($size -lt 64){
            return $offer+"6"
        }
        if ($size -lt 128){
            return $offer+"10"
        }
        if ($size -lt 256){
            return $offer+"15"
        }   
        if ($size -lt 512){
            return $offer+"20"
        }
        if ($size -lt 1024){
            return $offer+"30"
        }   
        if ($size -lt 2048){
            return $offer+"40"
        }
        if ($size -lt 4096){
            return $offer+"50"
        }   
        return ""
    }

    [System.Object] WindowsCmdReturnToJson([string]$str){
        $str = $str.Replace("\n","")
        $str = $str.Replace('0}','"0"},')
        $str = $str.Substring(0, $str.Length-1)
        $str = '[' + $str + ']'
        return ($str | ConvertFrom-Json)
    }
    
    [System.Object] LinuxCmdReturnToJson([string]$str){
        $str = $str.Replace("Enable succeeded:","").$str("[stdout]","").$str("[stderr]","")
        return ($str | ConvertFrom-Json)
    }

    [System.Collections.ArrayList] Correlate ($disk, $windowsVmDisks, $linuxVmDisks, [boolean]$OsDisk){
        $VmDisk = $null
        $disksList =  New-Object System.Collections.ArrayList($null)
       
        if ($windowsVmDisks) {
            foreach ($winDisk in $windowsVmDisks) {
                $correlatedDisk = $null
                if ($OsDisk) {
                    if ($winDisk.DriveLetter -eq "C:") {
                        $correlatedDisk = $winDisk
                    }
                }
                else {
                    if ($winDisk.DriveLetter -ne "C:" -and 
                        $winDisk.DriveLetter -ne "D:" -and $disk.Lun -eq $winDisk.Lun) {
                        $correlatedDisk = $winDisk
                    }
                }
    
                if ($correlatedDisk) {
                    $VmDisk = @{}
                    $VmDisk["DiskID"] = $disk.Id
                    $VmDisk["OSDiskID"] = $correlatedDisk.Disk
                    $VmDisk["OSDiskLun"] = $correlatedDisk.Lun
                    $VmDisk["OSDiskDiskSize"] = $correlatedDisk.DiskSize
                    $VmDisk["OSDiskDiskModel"] = $correlatedDisk.DiskModel
                    $VmDisk["OSDiskPartition"] = $correlatedDisk.Partition
                    $VmDisk["OSDiskRawSize"] = $correlatedDisk.RawSize
                    $VmDisk["OSDiskDriveLetter"] = $correlatedDisk.DriveLetter
                    $VmDisk["OSDiskVolumeName"] = $correlatedDisk.VolumeName
                    $VmDisk["OSDiskSize"] = $correlatedDisk.Size
                    $VmDisk["OSDiskFreeSpace"] = $correlatedDisk.FreeSpace
    
                    #if (-not $disksList) {
                    #    $disksList = New-Object System.Collections.ArrayList($null)
                    #}
    
                    # $disksList.Add($i, $VmDisk)
                    [void]$disksList.Add($VmDisk)
                }
            }
        }
        else {
    
        }
        return $disksList
    }

    [System.Object] CreateReportTable([string] $tableName, [string] $ReportAzureStorageResourceGroup, [string] $ReportAzureStorageName){
        $storageccount = Get-AzureRmStorageAccount -ResourceGroupName $ReportAzureStorageResourceGroup -Name $ReportAzureStorageName 
        if (-not $storageccount){
            Write-Host "Error retrieving the Azure Storage Account [$ReportAzureStorageResourceGroup]$ReportAzureStorageName"
            exit 1
        }

        $saContext = $storageccount.Context

        $ev = $null
        $evt = $null

        $table = Get-AzureStorageTable -Name $tableName -Context $saContext -ErrorVariable ev -ErrorAction SilentlyContinue
        if ($ev) {
            Write-Host "The Azure Storage Table " $tableName " will be created." -ForegroundColor Green
            
            $table = New-AzureStorageTable -Name $tableName -Context $saContext -ErrorVariable evt -ErrorAction SilentlyContinue
            if ($evt){
                Write-Host "Error: Creating Azure Storage Table " $tableName -ForegroundColor Red 
                exit 1
            }
        }

        return $table
    }

    SetTenant([string]$ReportAzureSubscriptionName){
        $azureContext = Get-AzureRmContext
        if ($azureContext){
            $This.TenantId = $azureContext.Tenant.TenantId
            if ($azureContext.Subscription.Name -ne $ReportAzureSubscriptionName){
                Select-AzureRmSubscription -Subscription $ReportAzureSubscriptionName
            }

        }else{
            Write-Host "Error: No Context available, please run the command Connect-AzureRmAccount " -ForegroundColor Red
            exit 1
        }
    }

    [System.Object] GetSubscriptions([string]$TargetSubscriptionName){
        $subs = Get-AzurermSubscription -TenantId $this.TenantId -SubscriptionName $TargetSubscriptionName

        if (-not $subs){
            Write-Host "Error: No subscription available, please check the parameters values" -ForegroundColor Red
            exit 1
        }
        return $subs;
    }
    

    ProcessUnmanagedDisk($disks, $table, $execution_date){
        Write-Host "Managed Disks not attached to a VM" -ForegroundColor Green
            
        foreach($key in $disks.Keys){
    
            $isRunnning = $false
    
            $diskU = ($disks[$key] | ConvertFrom-Json )
    
            if(-not $diskU.ManagedBy){
    
                $property = @{}
                $property.Add("vm_running",$isRunnning)
                    $property.Add("resourcegroup",$diskU.ResourceGroupName)
    
                if ($diskU.OsType){
                    $property.Add("osDisk_id",$diskU.Id)
                    $property.Add("osDisk_name",$diskU.Name)
                    $property.Add("osDisk_disk_type",$diskU.Sku.Tier)
                    $property.Add("osDisk_size_allocated",$diskU.DiskSizeGB)
                    $property.Add("osDisk_size_tier",$this.tierStorageSize($diskU.Sku.Tier,$diskU.DiskSizeGB))
                    $property.Add("osDisk_offer_name",$this.tierStorageOffer( $diskU.Sku.Tier, $diskU.DiskSizeGB))
                }else{
                    $property.Add("datadisk0_id",$diskU.Id)
                    $property.Add("datadisk0_name",$diskU.Name)
                    $property.Add("datadisk0_disk_type",$diskU.Sku.Tier)
                    $property.Add("datadisk0_size_allocated",$diskU.DiskSizeGB)
                    $property.Add("datadisk0_size_tier",$this.tierStorageSize($diskU.Sku.Tier,$diskU.DiskSizeGB))
                    $property.Add("datadisk0_offer_name",$this.tierStorageOffer( $diskU.Sku.Tier, $diskU.DiskSizeGB))
                }
    
                $this.SaveToTable($table, $execution_date, $diskU.Id.Replace("/","__"),"Disk", $diskU.Name, $property)
            }
    
        }
    }

    [bool]SaveToTable([Object]$table, [string] $execution_date, [string] $rowKeyPrefix,[string] $objectType, [string]$objectName, [System.Collections.Hashtable]$property){

        foreach($key in $property.Keys){
            $rowkey = $rowKeyPrefix + "__" + $key
            $tableRecord = @{}
            $tableRecord.Add("object_type", $objectType)
            $tableRecord.Add("object_name", $objectName)
            $tableRecord.Add("key",$key)
            $tableRecord.Add("value",$property[$key])
            Add-StorageTableRow -table $table -partitionKey $execution_date -rowKey $rowkey -property $tableRecord 
        }

        return $true
    }

    Main([string]$TargetSubscriptionName,
        [string]$TargetResourceGroup,
        [string]$ReportAzureSubscriptionName,
        [string]$ReportAzureStorageResourceGroup,
        [string]$ReportAzureStorageName){
        
        $table = $this.CreateReportTable($this.tableName, $ReportAzureStorageResourceGroup, $ReportAzureStorageName)
        $this.SetTenant($ReportAzureSubscriptionName)
        $subs = $this.GetSubscriptions($TargetSubscriptionName)

        Write-Host "Working... this can take a while" -ForegroundColor Green

        foreach($sub in $subs){
            Select-AzureRmSubscription -Subscription $sub.Id
        
            Write-Host "Listing VMs for " $sub.Name -ForegroundColor Green
        
            $disks = @{}
        
            if ($TargetResourceGroup){
                $resourceGroup =  Get-AzureRmResourceGroup -Name $TargetResourceGroup
                if (-not $resourceGroup){
                    Write-Host  $TargetResourceGroup " not available at Subscription " $sub.Name -ForegroundColor Yellow
                    continue
                }
                $vms = Get-AzureRmVM -ResourceGroupName $TargetResourceGroup
                Get-AzureRmDisk -ResourceGroupName  $TargetResourceGroup | foreach { $disks.Add($_.Id, ($_ | ConvertTo-Json))}
            }else{
                $vms = Get-AzureRmVM
                Get-AzureRmDisk | foreach { $disks.Add($_.Id, ($_ | ConvertTo-Json))}
            }
        
            $execution_date = Get-Date -UFormat "%Y-%m-%d-%H-%M"
        
            foreach($vm in $vms){
        
                Write-Host $sub.Name - $vm.ResourceGroupName - $vm.Name  -ForegroundColor Green
                
                $isRunnning = $false
                $VmDisk = $null
                $property = @{}
                $property.Add("vm_name",$vm.Name)
                $property.Add("vm_id",$vm.Id)
                $property.Add("resourcegroup",$vm.ResourceGroupName)
                $property.Add("location",$vm.Location)
                $property.Add("vmtype",$vm.HardwareProfile.VmSize.ToString())
        
                $windowsVmDisks = $null
                $linuxVmDisks = $null
                if ($vm.StorageProfile.OsDisk.DiskSizeGB){
                    $isRunnning = $true
                    
                    Write-Host "Getting information disks information form the VM" -ForegroundColor Green
                    if ($vm.StorageProfile.OsDisk.OsType.ToString() -eq 'Windows'){
                        $result = Invoke-AzureRmVMRunCommand -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -CommandId 'RunPowerShellScript' -ScriptPath "DisksInfo.ps1"
                        if ($result.Status -eq "Succeeded"){
                            $windowsVmDisks = $this.WindowsCmdReturnToJson($result.Value[0].Message)
                        }
                    }
                    # elseif ($vm.StorageProfile.OsDisk.OsType.ToString() -eq 'Linux'){
                    #     $result = Invoke-AzureRmVMRunCommand -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -CommandId 'RunShellScript' -ScriptPath "DisksInfo.sh"
                    #     if ($result.Status -eq "Succeeded"){
                    #         $linuxVmDisks = $this.LinuxCmdReturnToJson($result.Value[0].Message) 
                    #     }
                    # }
                }

                $property.Add("vm_running",$isRunnning)
                $property.Add("host_name",$vm.OSProfile.ComputerName)
                $property.Add("ostype",$vm.StorageProfile.OsDisk.OsType.ToString())
                $property.Add("osDisk_name",$vm.StorageProfile.OsDisk.Name)
        
                if ($vm.StorageProfile.OsDisk.ManagedDisk){
                    $property.Add("osDisk_id",$vm.StorageProfile.OsDisk.ManagedDisk.Id)
                    $disk = ($disks[$vm.StorageProfile.OsDisk.ManagedDisk.Id] | ConvertFrom-Json )
                    $property.Add("osDisk_disk_type",$disk.Sku.Tier)
                    $property.Add("osDisk_size_allocated",$disk.DiskSizeGB)
                    $property.Add("osDisk_size_tier",$this.tierStorageSize($disk.Sku.Tier,$disk.DiskSizeGB))
                    $property.Add("osDisk_offer_name",$this.tierStorageOffer($disk.Sku.Tier,$disk.DiskSizeGB))
                    
                    $disksList = $this.Correlate($disk, $windowsVmDisks, $linuxVmDisks, $true)
        
                    if ($disksList){
                        $property.Add("osDisk_vm_lun",$disksList[0]["OSDiskLun"])
                        $property.Add("osDisk_vm_size",$disksList[0]["OSDiskDiskSize"])
                        $property.Add("osDisk_vm_partition",$disksList[0]["OSDiskPartition"])
                        $property.Add("osDisk_vm_rawsize",$disksList[0]["OSDiskRawSize"])
                        $property.Add("osDisk_vm_driveletter",$disksList[0]["OSDiskDriveLetter"])
                        $property.Add("osDisk_vm_volumename",$disksList[0]["OSDiskVolumeName"])
                        $property.Add("osDisk_vm_disksize",$disksList[0]["OSDiskSize"])
                        $property.Add("osDisk_vm_diskfreeSpace",$disksList[0]["OSDiskFreeSpace"])
                    }
                }else{
                    $property.Add("osDisk_disk_type","Unmanaged")
                    $property.Add("osDisk_size_allocated",$vm.StorageProfile.OsDisk.DiskSizeGB)
                    $property.Add("osDisk_vhd",$vm.StorageProfile.OsDisk.Vhd.Uri.ToString())
                }
        
                $i = 0
                foreach($dataDisk in $vm.StorageProfile.DataDisks){
        
                    Write-Host $sub.Name - $vm.ResourceGroupName - $vm.Name - $i - id $dataDisk.ManagedDisk.Id  -ForegroundColor Green
                    
                    $disksList = $this.Correlate($dataDisk, $windowsVmDisks, $linuxVmDisks, $false)
        
                    $data_disk_type = "Standard_HDD"
        
                    $disk = ($disks[$dataDisk.ManagedDisk.Id] | ConvertFrom-Json )
        
                    if ($disk.Sku){
                        $data_disk_type = $disk.Sku.Tier
                    }
        
                    $property.Add("datadisk"+$i+"_lun",$dataDisk.Lun)
                    $property.Add("datadisk"+$i+"_id",$disk.Id)
                    $property.Add("datadisk"+$i+"_name",$disk.Name)
                    $property.Add("datadisk"+$i+"_type",$data_disk_type)
                    $property.Add("datadisk"+$i+"_size_allocated",$disk.DiskSizeGB)
                    $property.Add("datadisk"+$i+"_size_tier", $this.tierStorageSize($data_disk_type,$disk.DiskSizeGB))
                    $property.Add("datadisk"+$i+"_offer_name",$this.tierStorageOffer($data_disk_type,$disk.DiskSizeGB))
                    
                    $vol = 1
                    foreach($vmdatadisk in $disksList){
                        $prefix = "datadisk"+$i+"_volume_"+$vol
                        $property.Add($prefix+"_driveletter",$vmdatadisk["OSDiskDriveLetter"])
                        $property.Add($prefix+"_size",$vmdatadisk["OSDiskDiskSize"])
                        $property.Add($prefix+"_partition",$vmdatadisk["OSDiskPartition"])
                        $property.Add($prefix+"_lun",$vmdatadisk["OSDiskLun"])
                        $property.Add($prefix+"_rawsize",$vmdatadisk["OSDiskRawSize"])
                        $property.Add($prefix+"_volumeName",$vmdatadisk["OSDiskVolumeName"])
                        $property.Add($prefix+"_diskdize",$vmdatadisk["OSDiskSize"])
                        $property.Add($prefix+"_freeSpace",$vmdatadisk["OSDiskFreeSpace"])
                        $vol = $vol + 1
                    }
        
                    if ($dataDisk.Vhd){
                        $property.Add("datadisk"+$i+"_vhd",$dataDisk.Vhd.Uri.ToString())
                    }
        
                    $i = $i +1
                }
        
                $this.SaveToTable($table, $execution_date, $vm.Id.Replace("/","__"),"Compute",$vm.Name, $property)
            }
        
            $this.ProcessUnmanagedDisk($disks, $table, $execution_date)
        
        }

    }
 }


Write-Host "Warning: This script may change the active subscription for your context" -ForegroundColor Yellow

$diskAssessment = New-Object DiskAssessment

$diskAssessment.Main($TargetSubscriptionName,$TargetResourceGroup,$ReportAzureSubscriptionName,$ReportAzureStorageResourceGroup,$ReportAzureStorageName)