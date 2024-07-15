## Objectives
This is a work in progress to provide powershell tools to fulfill administrations needs in Hyper-V that aren't provided by Microsoft in their free tools. SCVMM can fulfill some of these needs, but is a licensed product, and much of what SCVMM does can be done in Powershell. 

## Hyper-V VM Groups
At first look, groups don't exist in Hyper-V, but they were implemented quietly in Server 2016. There is no management GUI for them, and outside of PowerShell and SCVMM, you'd never know if a VM was in a group. Windows Admin Center also lacks the ability to administer groups.
Certain applications can utilize groups. For example, Veeam Backup and Restore. This was the purpose of writing this script. When creating a backup job, we want to define if a VM is Production, Development, etc, and create backup jobs based on the VM Group. 
VM Groups also allow you to perform administrative tasks on groups of VMs instead of one at a time. Groups can be nested as well. 

### hypervvmgroups.ps1
This script provides the administrator with a simple management interface to manage VM Groups in a HV Cluster. It has not been tested with standalone Hyper-V servers, though I hope to get to this soon. It allows the following functions:

- Add VM To Existing Group
(Add-VMGroupMember -ComputerName $ownerNode -Name $groupName -VM $vm)
-  Move VM to New Group
-  Remove VM from Group
 - List Virtual Machines
 - View Existing Group Membership
 - List VM Groups
 - Create VM Group
 - Delete VM Group
 - Rename VM Group
   
Testing could also be done with multiple clusters in a failover group, but I also haven't had the opportunity to test this. 
