# AzureDiskAssessment

Usually the usage of Azure Managed Disks can generate extra costs if some aspects are not considerated, like:
1) I'm using the right performance tier?
2) Did I allocated the max space I have available for the desirable tier?
3) The disks that are not attached to a VM can be deleted or moved to a unmanaged disk?

In order to help you answer this question I made this python script that will generate a report to a Azure Table Storage, this table can be used to provide more information to your montoring tool.

## Solution

There are two implementation using [Python]("./python/Readme.md") and [Powershell]("./PS/Readme.md"), choose the one that fits your need.


## Prerequisites

[Python 3.6](https://www.python.org/downloads/)

[Azure Cli 2.0](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)

## Python Packages

[azure.common](https://pypi.org/project/azure-common/)

[azure.storage](https://pypi.org/project/azure-storage/)

[objectpath](https://pypi.org/project/objectpath/)

## Usage

1) Execute the script

```{r, engine='sh', count_lines}
./Start.py
```