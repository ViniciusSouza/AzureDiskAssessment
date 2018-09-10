# PowerShell version

The same funcionality described before but using Powershell.

## Prerequisites

PowerShell 5+

Azure Module '6.8.1'

    Install-Module -Name AzureRM -Force

Azure Table Module

    Install-Module AzureRmStorageTable

## Running

By running the command you must provide the location to store the report.

* ReportAzureSubscriptionName
* ReportAzureStorageResourceGroup
* ReportAzureStorageName

The subscription that will be scanned will be the ones available in the current tenant. If you are not sure about it run the command **Get-AzureRmContext**

    .\Start.ps1 -ReportAzureSubscriptionName "My subscription" -ReportAzureStorageResourceGroup "My Resource Group" -ReportAzureStorageName "My Storage Account"