# AzureDiskAssessment

Usually the usage of Azure Managed Disks can generate extra costs if some aspects are not considerated, like:
1) I'm using the right performance tier?
2) Did I allocated the max space I have available for the desirable tier?
3) The disks that are not attached to a VM can be deleted or moved to a unmanaged disk?

In order to help you answer this question I made this python script that will generate a report to a Azure Table Storage, this table can be used to provide more information to your montoring tool.

## Solution

There are two implementation using [Python](./python/Readme.md) and [Powershell](./PS/Readme.md), choose the one that fits your need.