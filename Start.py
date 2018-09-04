#-------------------------------------------------------------------------
#
# Copyright (c) Microsoft Corporation. All rights reserved.
#
# THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, 
# EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES 
# OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
#---------------------------------------------------------------------------

import config, sys, json
import azure.common
from azure.storage import CloudStorageAccount
from Tables import table_json
import subprocess

if config.IS_EMULATED:
    account = CloudStorageAccount(is_emulated=True)
else:
    account_name = config.STORAGE_ACCOUNT_NAME
    account_key = config.STORAGE_ACCOUNT_KEY
    account = CloudStorageAccount(account_name, account_key)


subsJson = subprocess.check_output("az account list", stderr=subprocess.STDOUT, shell=True)
if str(subsJson).__contains__("login"):
    subprocess.call(["az","login"])

for sub in json.loads(subsJson):
    print("subscription id: " + sub["id"])

    subprocess.check_output("az account set -s " + sub["id"], stderr=subprocess.STDOUT, shell=True)

    jsonvm = subprocess.check_output("az vm list", stderr=subprocess.STDOUT, shell=True)
    jsondisk = subprocess.check_output("az disk list", stderr=subprocess.STDOUT, shell=True)
    vmdisk_table = table_json(json.loads(jsonvm),json.loads(jsondisk) )
    vmdisk_table.vmdisks(account)