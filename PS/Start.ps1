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

function tierStorageSize {
    param (
        [string]$storageTier, 
        [int]$size
    )

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
    
    
}

function tierStorageOffer {
    param (
        [string]$storageTier, 
        [int]$size
    )

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
}

Write-Host "Warning: This script may change the active subscription for your context" -ForegroundColor Yellow

$azureContext = Get-AzureRmContext
if ($azureContext){
    $TenantId = $azureContext.Tenant.TenantId
    if ($azureContext.Subscription.Name -ne $ReportAzureSubscriptionName){
        Select-AzureRmSubscription -Subscription $ReportAzureSubscriptionName
    }

}else{
    Write-Host "Error: No Context available, please run the command Connect-AzureRmAccount " -ForegroundColor Red
    exit 1
}

$tableName = "vmdisks"

$storageccount = Get-AzureRmStorageAccount -ResourceGroupName $ReportAzureStorageResourceGroup -Name $ReportAzureStorageName 
if (-not $storageccount){
    Write-Host "Error retrieving the Azure Storage Account [$ReportAzureStorageResourceGroup]$ReportAzureStorageName"
    exit 1
}

$saContext = $storageccount.Context

$table = Get-AzureStorageTable -Name $tableName -Context $saContext -ErrorVariable ev -ErrorAction SilentlyContinue
if ($ev) {
    Write-Host "The Azure Storage Table " $tableName " will be created." -ForegroundColor Green
    
    $table = New-AzureStorageTable  -Name $tableName -Context $saContext
}

Write-Host "Report table:" $table.Uri -ForegroundColor Green
 
$subs = Get-AzurermSubscription -TenantId $TenantId -SubscriptionName $TargetSubscriptionName

if (-not $subs){
    Write-Host "Error: No subscription available, please check the parameters values" -ForegroundColor Red
    exit 1
}

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

    #$disksHas = ToHastable $disks

    foreach($vm in $vms){

        Write-Host $sub.Name - $vm.ResourceGroupName - $vm.Name  -ForegroundColor Green
        
        $isRunnning = $false
        
        $property = @{}
        $property.Add("vm_name",$vm.Name)
        $property.Add("vm_id",$vm.Id)
        $property.Add("resourcegroup",$vm.ResourceGroupName)
        $property.Add("location",$vm.Location)
        $property.Add("vmtype",$vm.HardwareProfile.VmSize.ToString())

        $windowsVmDisks = @{}
        $linuxVmDisks = @{}
        if ($vm.StorageProfile.OsDisk.DiskSizeGB){
            $isRunnning = $true
            
            Write-Host "Getting information disks information form the VM" -ForegroundColor Green
            if ($vm.StorageProfile.OsDisk.OsType.ToString() -eq 'Windows'){
                $result = Invoke-AzureRmVMRunCommand -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -CommandId 'RunPowerShellScript' -ScriptPath "DisksInfo.ps1"
                if ($result.Status -eq "Succeeded"){
                    #$resultstr = $result.Value[0].Message.Replace("\n","")
                    #$resultstr = $resultstr.Replace("0}",'"0"}')
                    #$windowsVmDisks = $resultstr | ConvertFrom-Json
                    $windowsVmDisks = $result.Value[0].Message | ConvertFrom-String
                }
            }
            # elseif ($vm.StorageProfile.OsDisk.OsType.ToString() -eq 'Linux'){
            #     $result = Invoke-AzureRmVMRunCommand -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -CommandId 'RunShellScript' -ScriptPath "DisksInfo.sh"
            #     if ($result.Status -eq "Succeeded"){
            #         $resultstr = $result.Value[0].Message.Replace("Enable succeeded:","").Replace("[stdout]","").Replace("[stderr]","")
            #         $linuxVmDisks = $resultstr | ConvertFrom-Json 
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
            $property.Add("osDisk_size_tier",(tierStorageSize -storageTier $disk.Sku.Tier -size $disk.DiskSizeGB))
            $property.Add("osDisk_offer_name",(tierStorageOffer -storageTier $disk.Sku.Tier -size $disk.DiskSizeGB))
            
        }else{
            $property.Add("osDisk_disk_type","Unmanaged")
            $property.Add("osDisk_size_allocated",$vm.StorageProfile.OsDisk.DiskSizeGB)
            $property.Add("osDisk_vhd",$vm.StorageProfile.OsDisk.Vhd.Uri.ToString())
        }

        $i = 0
        foreach($dataDisk in $vm.StorageProfile.DataDisks){

            Write-Host $sub.Name - $vm.ResourceGroupName - $vm.Name - $i - id $dataDisk.ManagedDisk.Id  -ForegroundColor Green
            

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
            $property.Add("datadisk"+$i+"_size_tier", (tierStorageSize -storageTier $data_disk_type -size $disk.DiskSizeGB))
            $property.Add("datadisk"+$i+"_offer_name",(tierStorageOffer -storageTier $data_disk_type -size $disk.DiskSizeGB))
            
            if ($dataDisk.Vhd){
                $property.Add("datadisk"+$i+"_vhd",$dataDisk.Vhd.Uri.ToString())
            }

            $i = $i +1
        }


        Add-StorageTableRow -table $table -partitionKey $execution_date -rowKey $vm.Id.Replace("/","__") -property $property 
    }


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
                $property.Add("osDisk_size_tier",(tierStorageSize -storageTier $diskU.Sku.Tier -size $diskU.DiskSizeGB))
                $property.Add("osDisk_offer_name",(tierStorageOffer -storageTier $diskU.Sku.Tier -size $diskU.DiskSizeGB))
            }else{
                $property.Add("datadisk0_id",$diskU.Id)
                $property.Add("datadisk0_name",$diskU.Name)
                $property.Add("datadisk0_disk_type",$diskU.Sku.Tier)
                $property.Add("datadisk0_size_allocated",$diskU.DiskSizeGB)
                $property.Add("datadisk0_size_tier",(tierStorageSize -storageTier $diskU.Sku.Tier -size $diskU.DiskSizeGB))
                $property.Add("datadisk0_offer_name",(tierStorageOffer -storageTier $diskU.Sku.Tier -size $diskU.DiskSizeGB))
            }

            Add-StorageTableRow -table $table -partitionKey $execution_date -rowKey $diskU.Id.Replace("/","__") -property $property 
        }

    }

}