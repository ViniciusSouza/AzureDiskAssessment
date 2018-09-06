param (
    [string]$TenantId = ""
    # ,[Parameter(Mandatory=$true)][string]$username,
    # ,[string]$password = $( Read-Host "Input password, please" )
 )

if ($TenantId -eq ""){
    if (Get-AzureRmContext){
        $TenantId = (Get-AzureRmContext).Tenant.TenantId
    }else{
        Write-Host "Error: No Context available, please run the command Connect-AzureRmAccount " -ForegroundColor Red
    }
}

$subs = Get-AzurermSubscription -TenantId $TenantId

foreach($sub in $subs){
    Select-AzureRmSubscription -Subscription $sub.Id

    Write-Host "Listing VMs for " $sub.Name -ForegroundColor Green
    $vms = Get-AzureRmVM 
    foreach($vm in $vms){
        
        
        
    }

    
}

# foreach($vm in $vms){
#     $VmDiks = Get-AzureRmDisk | Where ManagedBy -like $vm.Id
# }

# if ($tenants.Length -gt 1 -and $TenantId.Equals("")) {
#     Write-Host "Error: The current user has more than one tenant available" -ForegroundColor Red

#     foreach ($tenant in $tenants){
#         Write-Host "Tenant ID" $tenant.Id " Name " $tenant.Name
#     }

#     exit 1
# }

# if $tenant.GetItems() >= 1{
#     Write-Host "The current user has more than 1 tennant available" 
# }