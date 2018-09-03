#-------------------------------------------------------------------------
#
# Copyright (c) Microsoft Corporation. All rights reserved.
#
# THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, 
# EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES 
# OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
#---------------------------------------------------------------------------

import random, config, string, json, io, objectpath
from datetime import datetime
from azure.storage import CloudStorageAccount
from azure.storage.table import TableService, Entity

class table_json():

    def __init__(self, strJsonVM, strJsonDisk):
        self.strJsonVM = strJsonVM
        self.strJsonDisk = strJsonDisk

    def vmdisks(self, account):
        print('Processing VM List Json ')
        table_service = None
        try:
            table_service = account.create_table_service()
            table_name = 'vmdisks'

            # Create a new table
            if not table_service.exists(table_name):
                print('Create a table with name - ' + table_name)
                table_service.create_table(table_name)
            else:
                print('Create a table with name - ' + table_name + ' - already exists')
            

            vms = json.load(io.open(self.strJsonVM))
            disks = json.load(io.open(self.strJsonDisk))

            execution_date = datetime.now().strftime("%Y-%m-%d-%H-%M")

            for vm in vms:

                vm_running = False

                registry = {'PartitionKey': execution_date,
                 'RowKey': str(vm["id"]).replace('/','__')
                }

                registry['vm_name'] = vm["name"]
                registry['vm_id'] = vm["id"]
                registry['resourcegroup'] = vm["resourceGroup"]
                registry['location'] = vm["location"]
                registry['vmtype'] = vm["hardwareProfile"]["vmSize"]

                if not vm["storageProfile"]["osDisk"]["diskSizeGb"] is None:
                    vm_running = True

                disktree_obj = objectpath.Tree(disks)                
                osDisks = disktree_obj.execute('$.*[lower(@.id) is lower("'+vm["storageProfile"]["osDisk"]["managedDisk"]["id"]+'")]')
                
                for osDisk in osDisks:
                    self.osDisk = osDisk

                registry["vm_running"] = str(vm_running)
                registry['host_name'] = vm["osProfile"]["computerName"]
                registry['ostype'] = vm["storageProfile"]["osDisk"]["osType"]
                registry['osDisk_id'] = vm["storageProfile"]["osDisk"]["managedDisk"]["id"]
                registry['osDisk_name'] = vm["storageProfile"]["osDisk"]["name"]
                registry['osDisk_disk_type'] = self.osDisk["sku"]["name"]
                registry['osDisk_size_allocated'] = self.osDisk["diskSizeGb"]
                registry["osDisk_size_tier"] = self.tierStorageSize(self.osDisk["sku"]["name"], self.osDisk["diskSizeGb"])
                registry["osDisk_offer_name"] = self.tierStorageOffer(self.osDisk["sku"]["name"], self.osDisk["diskSizeGb"])

                i = 0
                for datadisk in vm["storageProfile"]["dataDisks"]:

                    data_disk_type = None
                    vmDataDisks = disktree_obj.execute('$.*[lower(@.id) is lower("'+datadisk["managedDisk"]["id"]+'")]')
                    for vmDataDisk in vmDataDisks:
                        self.vmDataDisk = vmDataDisk
                        if not self.vmDataDisk["sku"] is None:
                            data_disk_type = self.vmDataDisk["sku"]["name"]

                    if data_disk_type is None:
                        data_disk_type = "Standard_HDD"

                    registry["datadisk"+str(i)+"_lun"] = datadisk["lun"]
                    registry["datadisk"+str(i)+"_id"] = datadisk["managedDisk"]["id"]
                    registry["datadisk"+str(i)+"_name"] = datadisk["name"]
                    registry["datadisk"+str(i)+"_type"] = data_disk_type
                    registry["datadisk"+str(i)+"_size_allocated"] = self.vmDataDisk["diskSizeGb"]
                    registry["datadisk"+str(i)+"size_tier"] = self.tierStorageSize(data_disk_type,self.vmDataDisk["diskSizeGb"])
                    registry["datadisk"+str(i)+"_offer_name"] = self.tierStorageOffer(data_disk_type,self.vmDataDisk["diskSizeGb"])
                    registry["datadisk"+str(i)+"_vhd"] = datadisk["vhd"]
                    i = i + 1

                table_service.insert_entity(table_name, registry)

            ManageDisksUnused = disktree_obj.execute('$.*[@.managedBy is None]')
            
            for unusedDisk in ManageDisksUnused:
                vm_running = False

                registry = {'PartitionKey': execution_date,
                 'RowKey': str(unusedDisk["id"]).replace('/','__')
                }

                registry['location'] = unusedDisk["location"]
                registry['osType'] = unusedDisk["osType"]

                if not unusedDisk["osType"] is None:
                    registry['osDisk_id'] = unusedDisk["id"]
                    registry['osDisk_name'] = unusedDisk["name"]
                    registry['osDisk_disk_type'] = unusedDisk["sku"]["name"]
                    registry['osDisk_size_allocated'] = unusedDisk["diskSizeGb"]
                    registry["osDisk_size_tier"] = self.tierStorageSize(unusedDisk["sku"]["name"], unusedDisk["diskSizeGb"])
                    registry["osDisk_offer_name"] = self.tierStorageOffer(unusedDisk["sku"]["name"], unusedDisk["diskSizeGb"])
                else:
                    registry["datadisk0_id"] = unusedDisk["id"]
                    registry["datadisk0_name"] = unusedDisk["name"]
                    registry["datadisk0_type"] = unusedDisk["sku"]["name"]
                    registry["datadisk0_size_allocated"] = unusedDisk["diskSizeGb"]
                    registry["datadisk0size_tier"] = self.tierStorageSize(unusedDisk["sku"]["name"], unusedDisk["diskSizeGb"])
                    registry["datadisk0_offer_name"] = self.tierStorageOffer(unusedDisk["sku"]["name"], unusedDisk["diskSizeGb"])
                table_service.insert_entity(table_name, registry)

        except Exception as e:
            print('Error occurred.', e)

    def tierStorageSize(self, storageTier, size):
        if "Premium" in str(storageTier):
            if size <= 32:
                return 32
            if size <= 64:
                return 64
            if size <= 128:
                return 128
            if size <= 256:
                return 256
            if size <= 512:
                return 512
            if size <= 1024:
                return 1024
            if size <= 2048:
                return 2048
            if size <= 4096:
                return 4096
        elif "Standard_HDD" in str(storageTier):
            if size <= 32:
                return 32
            if size <= 64:
                return 63
            if size <= 128:
                return 128
            if size <= 256:
                return 256
            if size <= 512:
                return 512
            if size <= 1024:
                return 1024
            if size <= 2048:
                return 2048
            if size <= 4096:
                return 4096
        elif "Standard" in str(storageTier):
            if size <= 128:
                return 128
            if size <= 256:
                return 256
            if size <= 512:
                return 512
            if size <= 1024:
                return 1024
            if size <= 2048:
                return 2048
            if size <= 4096:
                return 4096

    def tierStorageOffer(self, storageTier, size):
        if "Premium" in str(storageTier):
            if size <= 32:
                return "P4"
            if size <= 64:
                return "P6"
            if size <= 128:
                return "P10"
            if size <= 256:
                return "P15"
            if size <= 512:
                return "P20"
            if size <= 1024:
                return "P30"
            if size <= 2048:
                return "P40"
            if size <= 4096:
                return "P50"
        elif "Standard_HDD" in str(storageTier):
            if size <= 32:
                return "S4"
            if size <= 64:
                return "S6"
            if size <= 128:
                return "S10"
            if size <= 256:
                return "S15"
            if size <= 512:
                return "S20"
            if size <= 1024:
                return "S30"
            if size <= 2048:
                return "S40"
            if size <= 4096:
                return "S50"
        elif "Standard" in str(storageTier):
            if size <= 128:
                return "E10"
            if size <= 256:
                return "E15"
            if size <= 512:
                return "E20"
            if size <= 1024:
                return "E30"
            if size <= 2048:
                return "E40"
            if size <= 4096:
                return "E50"
