# AzureDiskAssessment

Usually the usage of Azure Managed Disks can generate extra costs if some aspects are not considerated, like:
1) I'm using the right performance tier?
2) Did I allocated the max space I have available for the desirable tier?
3) The disks that are not attached to a VM can be deleted or moved to a unmanaged disk?

In order to help you answer this question I made this python script that will generate a report to a Azure Table Storage, this table can be used to provide more information to your montoring tool.

## Prerequisites

Python 3.6
Azure Cli 2.0

## Usage

1) Login to your Azure Subscription

```{r, engine='sh', count_lines}
az login
```

2) List the VMs and save it to a json file

```{r, engine='sh', count_lines}
az vm list > vm.json
```

3) List the Managed Disks in your subscription

```{r, engine='sh', count_lines}
az disk list > disk.json
```

4) Change the setting at Config.py

Using your favorite editor set the values to connect to the desire Storage Account.

5) Execute the script

```{r, engine='sh', count_lines}
./Start.py vm.json disk.json
```