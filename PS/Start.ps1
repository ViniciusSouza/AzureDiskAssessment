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
            if ($size -le 32){
                return 32
            }
            if ($size -le 64){
                return 64
            }
        }
        if ($size -le 128){
            return 128
        }
        if ($size -le 256){
            return 256
        }   
        if ($size -le 512){
            return 512
        }
        if ($size -le 1024){
            return 1024
        }   
        if ($size -le 2048){
            return 2048
        }
        if ($size -le 4096){
            return 4096
        }
        if ($size -le 8192){
            return 8192
        }
        if ($size -le 16384){
            return 16384
        }  
        if ($size -le 32768){
            return 32768
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
        if ($size -le 32){
            return $offer+"4"
        }
        if ($size -le 64){
            return $offer+"6"
        }
        if ($size -le 128){
            return $offer+"10"
        }
        if ($size -le 256){
            return $offer+"15"
        }   
        if ($size -le 512){
            return $offer+"20"
        }
        if ($size -le 1024){
            return $offer+"30"
        }   
        if ($size -le 2048){
            return $offer+"40"
        }
        if ($size -le 4096){
            return $offer+"50"
        } 
        if ($size -le 8192){
            return $offer+"60"
        }
        if ($size -le 16384){
            return $offer+"70"
        }  
        if ($size -le 32768){
            return $offer+"80"
        } 
        return ""
    }

    [System.Object] WindowsCmdReturnToJson([string]$str){
        try{
            if ($str -ne "" -and $str.Length -gt 6){
                $str = $str.Remove(0, $str.IndexOf("[")-1)
                $str = $str.Trim()
                return ($str | ConvertFrom-Json)
            }
        }Catch{
            Write-Host "Error found to parse the windows disk information " $str -ForegroundColor Red
            throw "Error found to parse the linux disk information " + $str 
        }
        return ("{}" | ConvertFrom-Json)
    }
    
    [System.Object] LinuxCmdReturnToJson([string]$str){

        $str = $str.Replace("Enable succeeded:","").Replace("[stdout]","").Replace("[stderr]","").Trim()
        $parts = $str.Split("---")
        $disksJson = $null

        Try
        {
            $usageJson = ($parts[3] | ConvertFrom-Json)
            $disksJson = ($parts[0] | ConvertFrom-Json)

            foreach($disk in $disksJson.blockdevices){

                $hctlParts = $disk.hctl.Split(":")

                $disk | Add-Member -Type NoteProperty -Name 'size' -Value 0
                $disk | Add-Member -Type NoteProperty -Name 'used' -Value 0
                $disk | Add-Member -Type NoteProperty -Name 'free' -Value 0
                $disk | Add-Member -Type NoteProperty -Name 'lun' -Value $hctlParts[$hctlParts.Length-1]
                $disk | Add-Member -Type NoteProperty -Name 'volume' -Value (New-Object System.Collections.ArrayList($null))

                foreach($usagedisk in $usageJson.diskarray){
                    if ($usagedisk.source.IndexOf($disk.name) -ne -1){
                        $disk.size += $usagedisk.spacetotal
                        $disk.free +=  $usagedisk.spaceavail
                        $disk.used += ($usagedisk.spaceused)
                        $disk.volume.Add($usagedisk)
                    }
                }

            }
        }
        Catch
        {
            Write-Host "Error found to parse the linux disk information " $str -ForegroundColor Red 
            throw "Error found to parse the linux disk information " + $str
        }

        return $disksJson
    }

    [System.Collections.ArrayList] Correlate ($disk, $windowsVmDisks, $linuxVmDisks, [boolean]$OsDisk){
        $VmDisk = $null
        $disksList =  New-Object System.Collections.ArrayList($null)
       
        if (-not $windowsVmDisks -and -not $linuxVmDisks){
            return $disksList
        }
        
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
                    $VmDisk = $this.GetVMDiskRecord($disk,$correlatedDisk,$null,$OsDisk,$false)
                    [void]$disksList.Add($VmDisk)
                }
            }
        }
        else {
            foreach ($linuxDisk in $linuxVmDisks.blockdevices) {
                $correlatedDisk = $null
                if ($OsDisk) {
                    if ($linuxDisk.name -eq "sda") {
                        $correlatedDisk = $linuxDisk
                    }
                }
                else {
                    $parts = $linuxDisk.hctl.Split(":")
                    $linuxLun = $parts[$parts.Length-1]
                    if ($linuxDisk.name -ne "sda" -and 
                        $linuxDisk.name -ne "sdb" -and
                        $linuxDisk.name.IndexOf("sr") -eq -1 -and 
                        $disk.Lun -eq $linuxLun) {
                        $correlatedDisk = $linuxDisk
                    }
                }
    
                if ($correlatedDisk){
                    if ($correlatedDisk.volume.Count -gt 0){
                        foreach($volume in $correlatedDisk.volume){
                            $VmDisk = $this.GetVMDiskRecord($disk,$correlatedDisk,$volume,$OsDisk,$true)
                            [void]$disksList.Add($VmDisk)
                        }
                    }else{
                        $VmDisk = $this.GetVMDiskRecord($disk,$correlatedDisk,$null,$OsDisk,$true)
                        [void]$disksList.Add($VmDisk)
                    }
                }
            }
        }
        return $disksList
    }

    [System.Object]GetVMDiskRecord($AzureDisk, $OSCorrelateDisk, $OSVolume, [bool] $OSDisk, [bool]$isLinux){
        $VmDisk = @{}

        if (-not $OsDisk){
            $VmDisk["DiskID"] = $AzureDisk.ManagedDisk.Id
        }else{
            $VmDisk["DiskID"] = $AzureDisk.Id
        }

        if ($isLinux){
            $VmDisk["OSDiskID"] = $OSCorrelateDisk.name
            $VmDisk["OSDiskLun"] = $OSCorrelateDisk.lun
            $VmDisk["OSDiskDiskSize"] = ($OSCorrelateDisk.size/1MB)
            $VmDisk["OSDiskDiskFree"] = ($OSCorrelateDisk.free/1MB)
            $VmDisk["OSDiskDiskUsed"] = ($OSCorrelateDisk.used/1MB)
            $VmDisk["OSDiskDiskModel"] = $OSCorrelateDisk.model
            if ($OSVolume){
                $VmDisk["OSDiskPartition"] = $OSVolume.source
                $VmDisk["OSDiskRawSize"] = ($OSVolume.spacetotal/1MB)
                $VmDisk["OSDiskDriveLetter"] = $OSVolume.source
                $VmDisk["OSDiskVolumeName"] = $OSVolume.source
                $VmDisk["OSDiskVolumeSize"] = ($OSVolume.spacetotal)/1MB
                $VmDisk["OSDiskVolumeFreeSpace"] = ($OSVolume.spaceavail/1MB)
                $VmDisk["OSDiskVolumeUsed"] = ($OSVolume.spaceused/1MB)
            }
        }else{
            $VmDisk["OSDiskID"] = $OSCorrelateDisk.Disk
            $VmDisk["OSDiskLun"] = $OSCorrelateDisk.Lun
            $VmDisk["OSDiskDiskSize"] = $OSCorrelateDisk.DiskSize
            $VmDisk["OSDiskDiskModel"] = $OSCorrelateDisk.DiskModel
            $VmDisk["OSDiskPartition"] = $OSCorrelateDisk.Partition
            $VmDisk["OSDiskRawSize"] = $OSCorrelateDisk.RawSize
            $VmDisk["OSDiskDriveLetter"] = $OSCorrelateDisk.DriveLetter
            $VmDisk["OSDiskVolumeName"] = $OSCorrelateDisk.VolumeName
            $VmDisk["OSDiskVolumeSize"] = $OSCorrelateDisk.Size
            $VmDisk["OSDiskVolumeFreeSpace"] = $OSCorrelateDisk.FreeSpace
            $VmDisk["OSDiskVolumeUsed"] = $OSCorrelateDisk.VolumeUsed
        }

        return $VmDisk
    }


    [System.Object] CreateReportTable([string] $tableName, [string] $ReportAzureStorageResourceGroup, [string] $ReportAzureStorageName){
        $storageccount = Get-AzureRmStorageAccount -ResourceGroupName $ReportAzureStorageResourceGroup -Name $ReportAzureStorageName 
        if (-not $storageccount){
            Write-Host "Error retrieving the Azure Storage Account [$ReportAzureStorageResourceGroup]$ReportAzureStorageName" -ForegroundColor Red
            exit 1
        }

        $saContext = $storageccount.Context

        $ev = $null
        $evt = $null

        $table = Get-AzureStorageTable -Name $tableName -Context $saContext -ErrorVariable ev -ErrorAction SilentlyContinue
        if ($ev) {
            Write-Host "The Azure Storage Table " $tableName " will be created." -ForegroundColor Green
            
            $retry=1
            while(-not $table){
                $table = New-AzureStorageTable -Name $tableName -Context $saContext -ErrorVariable evt -ErrorAction SilentlyContinue
                if ($evt){
                    Write-Host "Error: Try " $retry " Creating Azure Storage Table " $tableName -ForegroundColor Red 
                    Start-Sleep -s 5
                    if($retry -gt 2){
                        Write-Host "Error: After some tries was not possible to create the table, please try again! " $tableName -ForegroundColor Red 
                        exit 1
                    }
                }
                $retry = $retry + 1
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
            if ($property[$key]){
                $tableRecord.Add("value",$property[$key])
            }else{
                $tableRecord.Add("value",0)
            }
            Add-StorageTableRow -table $table -partitionKey $execution_date -rowKey $rowkey -property $tableRecord 
        }

        return $true
    }


    HandleError([Object]$table,[string] $table_key, [Object]$vm, [String]$errorMessage){
        try{
            $propertyError = @{}
            $propertyError.Add("Error",$errorMessage)
            Write-Host $errorMessage -ForegroundColor Yellow 
            $this.SaveToTable($table, $table_key, $vm.Id.Replace("/","__"),"Compute",$vm.Name, $propertyError)
        }Catch{
            Write-Host "Error handling error: "  $_.Exception.Message -ForegroundColor Red
        }
    }

    Main([string]$TargetSubscriptionName,
        [string]$TargetResourceGroup,
        [string]$ReportAzureSubscriptionName,
        [string]$ReportAzureStorageResourceGroup,
        [string]$ReportAzureStorageName){
        
        $this.SetTenant($ReportAzureSubscriptionName)
        $table = $this.CreateReportTable($this.tableName, $ReportAzureStorageResourceGroup, $ReportAzureStorageName)
        $tableError = $this.CreateReportTable($this.tableName+"error", $ReportAzureStorageResourceGroup, $ReportAzureStorageName)
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
                try{
                    Write-Host "Processing - Subscription: " $sub.Name " Resource Group: " $vm.ResourceGroupName " VM: " $vm.Name  -ForegroundColor Yellow
                    
                    $isRunnning = $false
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
                        
                        $result = $null
                        $evt = $null
                        $retry=1
                        while(-not $result -or -not $result.Status -eq "Succeeded"){
                            
                            try{
                                Write-Host "Try " $retry ": Getting information disks information for the VM" -ForegroundColor Yellow
                                if ($vm.StorageProfile.OsDisk.OsType.ToString() -eq 'Windows'){
                                    $result = Invoke-AzureRmVMRunCommand -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -CommandId 'RunPowerShellScript' -ScriptPath "DisksInfo.ps1" -ErrorVariable evt -ErrorAction SilentlyContinue
                                    if ($result.Status -eq "Succeeded"){
                                        $windowsVmDisks = $this.WindowsCmdReturnToJson($result.Value[0].Message)
                                    }
                                }
                                elseif ($vm.StorageProfile.OsDisk.OsType.ToString() -eq 'Linux'){
                                    $result = Invoke-AzureRmVMRunCommand -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -CommandId 'RunShellScript' -ScriptPath "DisksInfo.sh" -ErrorVariable evt -ErrorAction SilentlyContinue
                                    if ($result.Status -eq "Succeeded"){
                                        $linuxVmDisks = $this.LinuxCmdReturnToJson($result.Value[0].Message) 
                                    }
                                }
                            
                                if (-not $result){
                                    $this.HandleError($tableError, $execution_date+"_"+$retry, $vm, "Not able to run the remote script for the " + $vm.Name )
                                }else{
                                    if (-not $result.Status -eq "Succeeded"){
                                        #Log Error on vm disk error table
                                        $this.HandleError($tableError, $execution_date+"_"+$retry, $vm,  $result.Error.Message)
                                    }else{
                                        if ($result.Value[1] -and $result.Value[1].Message.Trim().Length -gt 0){
                                            $this.HandleError($tableError, $execution_date+"_"+$retry, $vm,  "A error was returned from the remote script " + $vm.Name + " this registry was saved to the vmdiskserror table")
                                        }
                                    }
                                }
                            }Catch{
                                $this.HandleError($tableError, $execution_date+"_"+$retry, $vm, $_.Exception.Message)
                            }

                            if($retry -gt 2){
                                $this.HandleError($tableError, $execution_date+"_"+$retry, $vm, "Error Trying go get disk information for VM " + $vm.Name +  ", please check if there is something wrong with this particular VM. error: " )
                                Write-Host $evt -ForegroundColor Red 
                                break
                            }
                            
                            $retry = $retry + 1
                        }
                    }else{
                        Write-Host "VM " $vm.name "is not running skipping the remote script execution " -ForegroundColor Yellow
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

                            $vol = 1
                            foreach($vmdatadisk in $disksList){
                                if ($disksList.Count -gt 1){
                                    $prefix = "osDisk_vm_volume_"+$vol
                                }else{
                                    $prefix = "osDisk_vm"
                                }
                                $property.Add($prefix+"_driveletter",$vmdatadisk["OSDiskDriveLetter"])
                                $property.Add($prefix+"_size",$vmdatadisk["OSDiskDiskSize"])
                                $property.Add($prefix+"_partition",$vmdatadisk["OSDiskPartition"])
                                $property.Add($prefix+"_lun",$vmdatadisk["OSDiskLun"])
                                $property.Add($prefix+"_partition_size",$vmdatadisk["OSDiskRawSize"])
                                $property.Add($prefix+"_volume_name",$vmdatadisk["OSDiskVolumeName"])
                                $property.Add($prefix+"_volume_size",$vmdatadisk["OSDiskVolumeSize"])
                                $property.Add($prefix+"_volume_freespace",$vmdatadisk["OSDiskVolumeFreeSpace"])
                                $vol = $vol + 1
                            }
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

                        if ($disks.count -gt 0 -and $disks.ContainsKey($dataDisk.ManagedDisk.Id)){
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
                            
                            if ($disksList -and $disksList.Count -gt 0){
                                if ($linuxVmDisks) { 
                                    #If Linux
                                    $property.Add("datadisk"+$i+"_OSDiskSize",$disksList[0]["OSDiskDiskSize"])
                                    $property.Add("datadisk"+$i+"_OsDiskFree",$disksList[0]["OSDiskDiskFree"])
                                    $property.Add("datadisk"+$i+"_OsDiskUsed",$disksList[0]["OSDiskDiskUsed"])
                                }else{
                                    #if Windows
                                    $property.Add("datadisk"+$i+"_OSDiskSize",$disksList[0]["OSDiskDiskSize"])
                                }
                            }
                        }

                        $vol = 1
                        foreach($vmdatadisk in $disksList){
                            $prefix = "datadisk"+$i+"_volume_"+$vol
                            $property.Add($prefix+"_driveletter",$vmdatadisk["OSDiskDriveLetter"])
                            $property.Add($prefix+"_partition",$vmdatadisk["OSDiskPartition"])
                            $property.Add($prefix+"_lun",$vmdatadisk["OSDiskLun"])
                            $property.Add($prefix+"_partition_size",$vmdatadisk["OSDiskRawSize"])
                            $property.Add($prefix+"_volume_name",$vmdatadisk["OSDiskVolumeName"])
                            $property.Add($prefix+"_volume_freeSpace",$vmdatadisk["OSDiskVolumeFreeSpace"])
                            $property.Add($prefix+"_volume_usedSpace",$vmdatadisk["OSDiskVolumeUsed"])
                            $property.Add($prefix+"_volume_size",$vmdatadisk["OSDiskVolumeSize"])

                            $vol = $vol + 1
                        }
            
                        if ($dataDisk.Vhd){
                            $property.Add("datadisk"+$i+"_vhd",$dataDisk.Vhd.Uri.ToString())
                        }
            
                        $i = $i +1
                    }
            
                    $this.SaveToTable($table, $execution_date, $vm.Id.Replace("/","__"),"Compute",$vm.Name, $property)
                }Catch{
                    $this.HandleError($tableError, $execution_date, $vm, $_.Exception.Message)
                }
            }
        
            $this.ProcessUnmanagedDisk($disks, $table, $execution_date)
        
        }

    }
 }


Write-Host "Warning: This script may change the active subscription for your context" -ForegroundColor Yellow

$diskAssessment = New-Object DiskAssessment

$diskAssessment.Main($TargetSubscriptionName,$TargetResourceGroup,$ReportAzureSubscriptionName,$ReportAzureStorageResourceGroup,$ReportAzureStorageName)

Write-Host "Script has finished with success!" -ForegroundColor Green