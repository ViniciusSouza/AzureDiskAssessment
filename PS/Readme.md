# PowerShell version

The same funcionality described before but using Powershell.

## Prerequisites

PowerShell 5+

Azure Module '6.8.1'

    Install-Module -Name AzureRM -Force

Azure Table Module

    Install-Module AzureRmStorageTable

## Running

By running the command you can provide.

* TargetSubscriptionName            - Not mandatory, if empty go trhu all the subscriptions
* TargetResourceGroup               - Not Mandatory, if empty go thru all the resourcesgroups  
* ReportAzureSubscriptionName       - Mandatory, Subscription name for the report
* ReportAzureStorageResourceGroup   - Mandatory, ResourceGroup name for the report
* ReportAzureStorageName            - Mandatory, Storage Account name for the report

The subscription that will be scanned will be the ones available in the current tenant. If you are not sure about it run the command **Get-AzureRmContext**

    .\Start.ps1 -TargetSubscriptionName 'Target subscription name' -TargetResourceGroup 'Target resource group name' -ReportAzureSubscriptionName 'My subscription' -ReportAzureStorageResourceGroup 'My Resource Group' -ReportAzureStorageName 'My Storage Account'