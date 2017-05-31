# PowerCLI_C_Drive_Expansion
Automated expansion Windows Guest C: drives (PowerCLI)

This project was created to tackle the issues surrounding C: drive expansions in a Windows/ vSphere environment such as failed patches, BSOD's and login failure. This script proactively expands the VMDK (harddisk1 in the current environment) and guest harddisk (C: drive), reducing time used to fulfil this activity and reduce downtime.

#Disclaimer
Run this script at your own risk, I cannot be held responsible for any issues which may occur from the running of scripts inside this repository.

# Components 

This project comprises of a PowerCLI/ Powershell script which when run against a vCenter server, automates the expansion of C: drives on Windows guests running in a vSphere environment. The script creates a csv file to keep track of past expansions and a log file which dumps the output from the script after each run. A basic html formated email is then sent to the recipient detailing servers which have been expanded along with the log and csv files.

File list:
- vCenterserver.csv
- PowerCLI_C_Drive_Expansion.ps1
- PowerCLI_C_Drive_Expansion.vcenterserver.00-00-0000_00-00.log

Blacklist:

To blacklist servers, use the if statment on line 157 with a guest name check as outline below. If the below is used, the servers listed wont be increased under any circumstances.

This is a wildcard check for a server name containing a string between asterisks:

- $server -Notlike "\*something\*"

This is an exact match of a server name:

- $server -Notlike "servername"

# Overview of tasks

This script performs the following tasks:

- Load the VM inventory of a specified vCenter server.
- Check the VM is not blacklisted (This is an if statement currently which can be expanded as needed on line 130)
- Grab the VMDK information in vCenter.
- Grab the harddisk info from the guest via vmware tools and compare the disk to the vmdk to make sure they match.
- Perform a diskpart to extend any free space before running the free space checks.
- If the disk is the C: drive, check its free space from the guest info.
- If less than 5GB free, check the data csv file to see if the VM has been increased in the last month.
- Check if the VM has any snapshots.
- Check if the VM has been extended in the last month and note of this to email the windows team.
- Check if the datastore has 20% or more free before attempting to do an increase on each VM.
- If all of the above checks are true, the vmdk will be expanded to 10GB more than it currently has and the guest will be expanded to match.
- The increase script will then check the VMDK and Diskpart output, making sure the expansion was successful. 
- This is logged in both a log.txt and an html formatted email sent to the windows team after the script has run.

# Run Script

Create scheduled task

- Create the scheduled task and set the action to:
- Program/Script: Powershell.exe
- Arguments: -Command "&{E:\PowerCLI_C_Drive_Expansion-master\PowerCLI_C_Drive_Expansion.ps1 -vcenter "vcenterserver" -GuestUser "user" -GuestPassword "xxxxx"}"
- Start in: E:\PowerCLI_C_Drive_Expansion-master

Run on demand

.\PowerCLI_C_Drive_Expansion.ps1 -vcenter "vcenterserver" -GuestUser "svc_xxx" -GuestPassword "xxx"

# Requirements

The output of this script must be checked to ensure VM's are not growing out of control. If this is not ideal behaviour, some customisations will be required under the else statement checking for past expansions. The implementation of the script at present only alerts on previous expansions and proceeds to increase the disks.

VMware Tools must be installed, upto date and in working order on all Guest VM's to enable diskpart to perform an increase.

No snapshots or consolidations can exist on VM's which are to be automatically increased. This means if a snapshot backup software e.g. Avamar or Networker is used, the script cannot be run during the same time as the backups will cause the increase to fail. 

The guests must have network connectivity and be joined to the domain for a domain user account to authenticate and perform the tasks.

The following parameters are required to be parsed to the script to establish a connection to vCenter and the string is as follows:

- vCenter server
- User account with permissions to access all windows servers as local admin to perform the increases with diskpart and access to vCenter with permissions to increase VMDK's.
- Password for user account specified above

# Additional Notes

The script has been successfully tested on Windows Server 2008 R2/ 2012 R2 Guests and vSphere 5.5/ 6.0.

The script will fail to increase a VM if there is network connectivity errors or non domain joined VM's as the script requires a domain account with correct access to vCetner and Windows guests. This will be recorded as a failure in the log and will require manual intervention to correct the issue.
