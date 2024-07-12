#Hyper-V Cluster VM Group Management
#Version: 1.0

#Update the line below with the FQDN of your Hyper-V Cluster
$clusterName = "{HYPERVCLUSTER.DOMAIN.LOCAL}"

function Show-Menu {
    Clear-Host
    Write-Host "======================"
    Write-Host " Hyper-V VM Group Menu" -ForegroundColor Cyan
    Write-Host "======================"
    Write-Host "1. Add VM To Existing Group"
    Write-Host "2. Move VM to New Group"
    Write-Host "3. Remove VM from Group"
    Write-Host "4. List Virtual Machines"
    Write-Host "5. View Existing Group Membership"
    Write-Host "6. List VM Groups"
    Write-Host "7. Create VM Group"
    Write-Host "8. Delete VM Group"
    Write-Host "9. Rename VM Group"
    Write-Host "10. Exit"
}

function Add-VMToGroup {
    param (
        [string]$clusterName
    )

    # Retrieve and sort the groups alphabetically
    $groups = Get-VMGroup | Where-Object { $_.GroupType -eq "VMCollectionType" } | Sort-Object -Property Name
    Write-Host "Existing Groups:" -ForegroundColor Yellow
    $groups | ForEach-Object { Write-Host $_.Name -ForegroundColor DarkCyan}
    
    $groupName = Read-Host "Enter Group Name"
    $vmName = Read-Host "Enter VM Name"

    try {
        $vm = Get-ClusterGroup -Cluster $clusterName | Where-Object { $_.Name -eq $vmName }
        if ($vm -eq $null) {
            Write-Host "VM '$vmName' not found in the cluster." -ForegroundColor Red
            return
        }

        $ownerNode = $vm.OwnerNode.Name

        $vm = Get-VM -ComputerName $ownerNode -Name $vmName

        Add-VMGroupMember -ComputerName $ownerNode -Name $groupName -VM $vm
        Write-Host "VM '$vmName' has been added to group '$groupName'." -ForegroundColor Green
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

function Move-VMToNewGroup {
    param (
        [string]$clusterName
    )

    $vmName = Read-Host "Enter VM Name"

    # Retrieve the old group name where the VM is currently a member
    $oldGroup = Get-VMGroup -ComputerName $clusterName | Where-Object { $_.VMMembers.Name -contains $vmName }
    $oldGroupName = $oldGroup.Name

    if ($null -eq $oldGroupName) {
        Write-Host "VM '$vmName' is not found in any group." -ForegroundColor Yellow
        return
    }

    Write-Host "Current Group:" -NoNewline
    Write-Host " $oldGroupName" -ForegroundColor DarkCyan

    $groups = Get-VMGroup -ComputerName $clusterName | Where-Object { $_.GroupType -eq "VMCollectionType" } | Sort-Object -Property Name
    $groupNames = $groups.Name

    Write-Host "Existing Groups:" -ForegroundColor Yellow
    $groups | ForEach-Object { Write-Host $_.Name -ForegroundColor DarkCyan }

    do {
        $newGroupName = Read-Host "Enter New Group Name"
        if ($newGroupName -eq 'cancel') {
            Write-Host "Operation cancelled. Returning to menu." -ForegroundColor Yellow
            return
        }
        if ($newGroupName -and $groupNames -contains $newGroupName) {
            break
        }
        Write-Host "Invalid Group Name. Please enter a valid group name or type 'cancel' to return." -ForegroundColor Red
    } while ($true)

    try {
        $ownerNode = (Get-VM -ComputerName $clusterName -Name $vmName).ComputerName
        $vm = Get-VM -ComputerName $ownerNode -Name $vmName

        # Remove the VM from the old group and add it to the new group
        Remove-VMGroupMember -ComputerName $ownerNode -Name $oldGroupName -VM $vm
        Add-VMGroupMember -ComputerName $ownerNode -Name $newGroupName -VM $vm
        Write-Host "VM '$vmName' has been moved from group '$oldGroupName' to '$newGroupName'." -ForegroundColor Green
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

function Remove-VMFromGroup {
    param (
        [string]$clusterName
    )

    $vmName = Read-Host "Enter VM Name"
    $group = Get-VMGroup -ComputerName $clusterName | Where-Object { $_.VMMembers.Name -contains $vmName }

    if ($group -eq $null) {
        Write-Host "VM '$vmName' is not found in any group." -ForegroundColor Yellow
        return
    }

    $groupName = $group.Name
    
    try {
        $ownerNode = (Get-VM -ComputerName $ClusterName -Name $vmName).ComputerName
        $vm = Get-VM -ComputerName $ownerNode -Name $vmName
        
        Remove-VMGroupMember -ComputerName $ownerNode -Name $groupName -VM $vm
        Write-Host "VM '$vmName' has been removed from group '$groupName'." -ForegroundColor Green
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

function List-VMs {
    param (
        [string]$clusterName
    )

    $vms = Get-ClusterGroup -Cluster $clusterName | Where-Object { $_.GroupType -eq "VirtualMachine" }
    Write-Host "Existing Virtual Machines:" -ForegroundColor Yellow
    $vms | ForEach-Object { Write-Host $_.Name }
}

function View-ExistingGroupMembership {
    param (
        [string]$clusterName
    )
    Clear-Variable -Name groups -ErrorAction SilentlyContinue
    Clear-Variable -Name groupName -ErrorAction SilentlyContinue
    Clear-Variable -Name vmMembers -ErrorAction SilentlyContinue
    $groups = Get-VMGroup -ComputerName $clusterName | Select-Object Name, VMMembers
    Write-Host "Existing Group Membership:" -ForegroundColor Yellow
    $groups | ForEach-Object {
        Write-Host "$($_.Name):" -ForegroundColor DarkCyan
        $_.VMMembers | ForEach-Object { Write-Host "  - $($_.Name)"}
    }
}

function List-VMGroups {
    param (
        [string]$clusterName
    )

    $groups = Get-VMGroup | Where-Object { $_.GroupType -eq "VMCollectionType" } | Sort-Object -Property Name
    Write-Host "Existing Groups:" -ForegroundColor Yellow
    $groups | ForEach-Object { Write-Host $_.Name -ForegroundColor DarkCyan}
}

function Create-VMGroup {
    $groupName = Read-Host "Enter New Group Name"
    try {
        New-VMGroup -Name $groupName -GroupType VMCollectionType
        Write-Host "Group '$groupName' has been created." -ForegroundColor Green
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

function Delete-VMGroup {
    param (
        [string]$clusterName
    )

    $groups = Get-VMGroup | Where-Object { $_.GroupType -eq "VMCollectionType" }
    Write-Host "Existing Groups:" -ForegroundColor Yellow
    $groups | ForEach-Object { Write-Host $_.Name -ForegroundColor DarkCyan}
    
    $groupName = Read-Host "Enter Group Name to Delete"
    $group = $groups | Where-Object { $_.Name -eq $groupName }
    
    if ($group -eq $null) {
        Write-Host "Group '$groupName' does not exist." -ForegroundColor Yellow
        return
    }

    $vmsInGroup = $group.VMMembers
    
    if ($vmsInGroup.Count -gt 0) {
        Write-Host "Group '$groupName' contains the following VMs:" -ForegroundColor Yellow
        $vmsInGroup | ForEach-Object { Write-Host $_.Name }
        Write-Host "Cannot delete a group with existing VMs." -ForegroundColor Yellow
    } else {
        try {
            Remove-VMGroup -Name $groupName
            Write-Host "Group '$groupName' has been deleted." -ForegroundColor Green
        } catch {
            Write-Host "Error: $_" -ForegroundColor Red
        }
    }
}

function Rename-VMGroupMenu {
    param (
        [string]$clusterName
    )

    $groups = Get-VMGroup | Where-Object { $_.GroupType -eq "VMCollectionType" }
    Write-Host "Existing Groups:" -ForegroundColor Yellow
    $groups | ForEach-Object { Write-Host $_.Name -ForegroundColor DarkCyan}
    
    $oldGroupName = Read-Host "Enter Old Group Name"
    $group = $groups | Where-Object { $_.Name -eq $oldGroupName }
    
    if ($group -eq $null) {
        Write-Host "Group '$oldGroupName' does not exist." -ForegroundColor Yellow
        return
    }

    $newGroupName = Read-Host "Enter New Group Name"
    
    try {
        Rename-VMGroup -Name $oldGroupName -NewName $newGroupName
        Write-Host "Group '$oldGroupName' has been renamed to '$newGroupName'." -ForegroundColor Green
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

do {
    Show-Menu
    $choice = Read-Host "Enter your choice"

    switch ($choice) {
        1 { Add-VMToGroup -clusterName $clusterName }
        2 { Move-VMToNewGroup -clusterName $clusterName }
        3 { Remove-VMFromGroup -clusterName $clusterName }
        4 { List-VMs -clusterName $clusterName }
        5 { View-ExistingGroupMembership -clusterName $clusterName }
        6 { List-VMGroups -clusterName $clusterName }
        7 { Create-VMGroup }
        8 { Delete-VMGroup -clusterName $clusterName }
        9 { Rename-VMGroupMenu -clusterName $clusterName }
        10 { Write-Host "Exiting..."; exit }
        default { Write-Host "Invalid choice, please try again." -ForegroundColor Yellow }
    }

    Write-Host "Press any key to return to the menu..."
    [void][System.Console]::ReadKey($true)
} while ($true)
