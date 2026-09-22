# Hyper-V Cluster VM Group Management
# Version: 1.1
#
# Designed for clustered Hyper-V environments using ConfigStoreRootPath.
#
# VM Group operations are performed against a physical Hyper-V cluster node,
# NOT the cluster virtual/FQDN name.
#
# VM membership changes are performed against the node currently owning the VM.
#
# Update the line below with the FQDN of your Hyper-V Cluster.

$clusterName = "{CLUSTERNAME.domain}"

# ============================================================
# Helper Functions
# ============================================================

function Get-VMGroupManagementNode {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    try {
        $node = Get-ClusterNode -Cluster $clusterName |
            Where-Object { $_.State -eq "Up" } |
            Sort-Object Name |
            Select-Object -First 1

        if ($null -eq $node) {
            throw "No online Hyper-V cluster nodes were found."
        }

        return $node.Name
    }
    catch {
        throw "Unable to determine VM Group management node: $_"
    }
}


function Get-VMOwnerNode {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName,

        [Parameter(Mandatory)]
        [string]$vmName
    )

    $clusterVM = Get-ClusterGroup -Cluster $clusterName |
        Where-Object {
            $_.GroupType -eq "VirtualMachine" -and
            $_.Name -eq $vmName
        }

    if ($null -eq $clusterVM) {
        throw "VM '$vmName' was not found in cluster '$clusterName'."
    }

    return $clusterVM.OwnerNode.Name
}


function Get-ClusterVMGroups {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    $managementNode = Get-VMGroupManagementNode -clusterName $clusterName

    Get-VMGroup -ComputerName $managementNode |
        Where-Object {
            $_.GroupType -eq "VMCollectionType"
        } |
        Sort-Object Name
}


function Show-Menu {

    Clear-Host

    $managementNode = $null

    try {
        $managementNode = Get-VMGroupManagementNode -clusterName $clusterName
    }
    catch {
        $managementNode = "Unavailable"
    }

    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host " Hyper-V Cluster VM Group Management" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Cluster:         " -NoNewline
    Write-Host $clusterName -ForegroundColor DarkCyan

    Write-Host "Management Node: " -NoNewline
    Write-Host $managementNode -ForegroundColor DarkCyan

    Write-Host ""
    Write-Host "1.  Add VM To Existing Group"
    Write-Host "2.  Move VM to New Group"
    Write-Host "3.  Remove VM from Group"
    Write-Host "4.  List Virtual Machines"
    Write-Host "5.  View Existing Group Membership"
    Write-Host "6.  List VM Groups"
    Write-Host "7.  Create VM Group"
    Write-Host "8.  Delete VM Group"
    Write-Host "9.  Rename VM Group"
    Write-Host "10. Exit"
    Write-Host ""
}


# ============================================================
# Add VM To Group
# ============================================================

function Add-VMToGroup {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    $group = Select-VMGroup `
        -clusterName $clusterName `
        -Prompt "Select Group"

    if ($null -eq $group) {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return
    }

    $groupName = $group.Name

    Write-Host ""
    Write-Host "Selected Group: " -NoNewline
    Write-Host $groupName -ForegroundColor DarkCyan
    Write-Host ""

    $vmName = Read-Host "Enter VM Name"

    try {
        $ownerNode = Get-VMOwnerNode `
            -clusterName $clusterName `
            -vmName $vmName

        $vm = Get-VM `
            -ComputerName $ownerNode `
            -Name $vmName `
            -ErrorAction Stop

        $existingGroup = Get-VMGroup `
            -ComputerName $ownerNode `
            -Name $groupName `
            -ErrorAction Stop

        if ($existingGroup.VMMembers.Name -contains $vmName) {

            Write-Host ""
            Write-Host "VM '$vmName' is already a member of '$groupName'." `
                -ForegroundColor Yellow

            return
        }

        Add-VMGroupMember `
            -ComputerName $ownerNode `
            -Name $groupName `
            -VM $vm `
            -ErrorAction Stop

        Write-Host ""
        Write-Host "VM '$vmName' has been added to '$groupName'." `
            -ForegroundColor Green

        Write-Host "VM Owner Node: $ownerNode" `
            -ForegroundColor DarkGray
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

# ============================================================
# Select VM Group From Numbered List
# ============================================================

function Select-VMGroup {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName,

        [string]$Prompt = "Select VM Group"
    )

    try {
        $groups = @(Get-ClusterVMGroups -clusterName $clusterName)
    }
    catch {
        Write-Host "Error retrieving VM Groups: $_" -ForegroundColor Red
        return $null
    }

    if ($groups.Count -eq 0) {
        Write-Host "No VM Groups currently exist." -ForegroundColor Yellow
        return $null
    }

    Write-Host ""
    Write-Host "VM Groups:" -ForegroundColor Yellow
    Write-Host ""

    for ($i = 0; $i -lt $groups.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $groups[$i].Name) `
            -ForegroundColor DarkCyan
    }

    Write-Host ""

    while ($true) {

        $selection = Read-Host "$Prompt [1-$($groups.Count)] or 'cancel'"

        if ($selection -eq "cancel") {
            return $null
        }

        $number = 0

        if ([int]::TryParse($selection, [ref]$number)) {

            if ($number -ge 1 -and $number -le $groups.Count) {
                return $groups[$number - 1]
            }
        }

        Write-Host "Invalid selection." -ForegroundColor Red
    }
}

# ============================================================
# Move VM To New Group
# ============================================================

function Move-VMToNewGroup {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    $vmName = Read-Host "Enter VM Name"

    try {
        $ownerNode = Get-VMOwnerNode `
            -clusterName $clusterName `
            -vmName $vmName

        $vm = Get-VM `
            -ComputerName $ownerNode `
            -Name $vmName `
            -ErrorAction Stop

        $groups = Get-VMGroup `
            -ComputerName $ownerNode `
            -ErrorAction Stop |
            Where-Object {
                $_.GroupType -eq "VMCollectionType"
            } |
            Sort-Object Name

        $oldGroups = $groups |
            Where-Object {
                $_.VMMembers.Name -contains $vmName
            }

        if (-not $oldGroups) {
            Write-Host ""
            Write-Host "VM '$vmName' is not currently found in any VM Group." `
                -ForegroundColor Yellow
            return
        }

        if ($oldGroups.Count -gt 1) {
            Write-Host ""
            Write-Host "VM '$vmName' belongs to multiple groups:" `
                -ForegroundColor Yellow

            $oldGroups | ForEach-Object {
                Write-Host "  $($_.Name)" -ForegroundColor DarkCyan
            }

            Write-Host ""
            Write-Host "Move operation cancelled to avoid removing unexpected memberships." `
                -ForegroundColor Yellow

            Write-Host "Use option 3 to remove memberships individually." `
                -ForegroundColor Yellow

            return
        }

        $oldGroupName = $oldGroups.Name

        Write-Host ""
        Write-Host "Current Group: " -NoNewline
        Write-Host $oldGroupName -ForegroundColor DarkCyan

        Write-Host ""
        Write-Host "Existing Groups:" -ForegroundColor Yellow

        $groups | ForEach-Object {
            Write-Host "  $($_.Name)" -ForegroundColor DarkCyan
        }

        $groupNames = $groups.Name

        do {
            Write-Host ""

            $newGroupName = Read-Host "Enter New Group Name or 'cancel'"

            if ($newGroupName -eq "cancel") {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                return
            }

            if ($groupNames -contains $newGroupName) {
                break
            }

            Write-Host "Invalid Group Name." -ForegroundColor Red

        } while ($true)

        if ($newGroupName -eq $oldGroupName) {
            Write-Host ""
            Write-Host "VM '$vmName' is already in '$newGroupName'." `
                -ForegroundColor Yellow
            return
        }

        Remove-VMGroupMember `
            -ComputerName $ownerNode `
            -Name $oldGroupName `
            -VM $vm `
            -ErrorAction Stop

        try {
            Add-VMGroupMember `
                -ComputerName $ownerNode `
                -Name $newGroupName `
                -VM $vm `
                -ErrorAction Stop
        }
        catch {
            Write-Host ""
            Write-Host "Failed to add VM to new group. Attempting rollback..." `
                -ForegroundColor Yellow

            try {
                Add-VMGroupMember `
                    -ComputerName $ownerNode `
                    -Name $oldGroupName `
                    -VM $vm `
                    -ErrorAction Stop

                Write-Host "Rollback successful." `
                    -ForegroundColor Yellow
            }
            catch {
                Write-Host "WARNING: Rollback also failed." `
                    -ForegroundColor Red
            }

            throw
        }

        Write-Host ""
        Write-Host "VM '$vmName' moved from '$oldGroupName' to '$newGroupName'." `
            -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}


# ============================================================
# Remove VM From Group
# ============================================================

function Remove-VMFromGroup {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    $vmName = Read-Host "Enter VM Name"

    try {
        $ownerNode = Get-VMOwnerNode `
            -clusterName $clusterName `
            -vmName $vmName

        $vm = Get-VM `
            -ComputerName $ownerNode `
            -Name $vmName `
            -ErrorAction Stop

        $groups = Get-VMGroup `
            -ComputerName $ownerNode `
            -ErrorAction Stop |
            Where-Object {
                $_.GroupType -eq "VMCollectionType"
            }

        $memberGroups = $groups |
            Where-Object {
                $_.VMMembers.Name -contains $vmName
            }

        if (-not $memberGroups) {
            Write-Host ""
            Write-Host "VM '$vmName' is not found in any VM Group." `
                -ForegroundColor Yellow
            return
        }

        if ($memberGroups.Count -eq 1) {
            $groupName = $memberGroups.Name
        }
        else {
            Write-Host ""
            Write-Host "VM '$vmName' belongs to multiple groups:" `
                -ForegroundColor Yellow

            $memberGroups | ForEach-Object {
                Write-Host "  $($_.Name)" -ForegroundColor DarkCyan
            }

            Write-Host ""

            $groupName = Read-Host "Enter Group Name to remove VM from"

            if ($memberGroups.Name -notcontains $groupName) {
                Write-Host "VM '$vmName' is not a member of '$groupName'." `
                    -ForegroundColor Red
                return
            }
        }

        Remove-VMGroupMember `
            -ComputerName $ownerNode `
            -Name $groupName `
            -VM $vm `
            -ErrorAction Stop

        Write-Host ""
        Write-Host "VM '$vmName' removed from group '$groupName'." `
            -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}


# ============================================================
# List Virtual Machines
# ============================================================

function List-VMs {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    try {
        $managementNode = Get-VMGroupManagementNode `
            -clusterName $clusterName

        $groups = @(Get-VMGroup `
            -ComputerName $managementNode `
            -ErrorAction Stop |
            Where-Object {
                $_.GroupType -eq "VMCollectionType"
            })

        $vms = @(Get-ClusterGroup -Cluster $clusterName |
            Where-Object {
                $_.GroupType -eq "VirtualMachine"
            } |
            Sort-Object Name)

        Write-Host ""
        Write-Host "Existing Virtual Machines:" -ForegroundColor Yellow
        Write-Host ""

        $rows = foreach ($vm in $vms) {

            $membership = @(
                $groups |
                    Where-Object {
                        $_.VMMembers.Name -contains $vm.Name
                    } |
                    Select-Object -ExpandProperty Name
            )

            if ($membership.Count -eq 0) {
                $membershipText = "-"
            }
            else {
                $membershipText = ($membership | Sort-Object) -join ", "
            }

            [PSCustomObject]@{
                Name      = $vm.Name
                OwnerNode = $vm.OwnerNode.Name
                State     = $vm.State
                VMGroup   = $membershipText
            }
        }

        $rows |
            Format-Table `
                Name,
                OwnerNode,
                State,
                VMGroup `
                -AutoSize |
            Out-Host

        Write-Host "Group information sourced from: $managementNode" `
            -ForegroundColor DarkGray
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}


# ============================================================
# View Existing Group Membership
# ============================================================

function View-ExistingGroupMembership {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    try {
        $managementNode = Get-VMGroupManagementNode `
            -clusterName $clusterName

        $groups = Get-VMGroup `
            -ComputerName $managementNode `
            -ErrorAction Stop |
            Where-Object {
                $_.GroupType -eq "VMCollectionType"
            } |
            Sort-Object Name

        Write-Host ""
        Write-Host "Existing Group Membership:" -ForegroundColor Yellow
        Write-Host ""

        if (-not $groups) {
            Write-Host "No VM Groups exist." -ForegroundColor Yellow
            return
        }

        foreach ($group in $groups) {

            Write-Host "$($group.Name):" -ForegroundColor DarkCyan

            if ($group.VMMembers.Count -eq 0) {
                Write-Host "  (Empty)" -ForegroundColor DarkGray
            }
            else {
                $group.VMMembers |
                    Sort-Object Name |
                    ForEach-Object {
                        Write-Host "  - $($_.Name)"
                    }
            }

            Write-Host ""
        }

        Write-Host "Source Node: $managementNode" `
            -ForegroundColor DarkGray
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}


# ============================================================
# List VM Groups
# ============================================================

function List-VMGroups {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    try {
        $managementNode = Get-VMGroupManagementNode `
            -clusterName $clusterName

        $groups = Get-ClusterVMGroups `
            -clusterName $clusterName

        Write-Host ""
        Write-Host "Existing Groups:" -ForegroundColor Yellow
        Write-Host ""

        if (-not $groups) {
            Write-Host "No VM Groups exist." -ForegroundColor Yellow
            return
        }

        foreach ($group in $groups) {
            $memberCount = @($group.VMMembers).Count

            Write-Host ("  {0,-35} {1} VM(s)" -f `
                $group.Name,
                $memberCount) `
                -ForegroundColor DarkCyan
        }

        Write-Host ""
        Write-Host "Source Node: $managementNode" `
            -ForegroundColor DarkGray
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}


# ============================================================
# Create VM Group
# ============================================================

function Create-VMGroup {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    $groupName = Read-Host "Enter New Group Name"

    if ([string]::IsNullOrWhiteSpace($groupName)) {
        Write-Host "Group name cannot be blank." -ForegroundColor Red
        return
    }

    try {
        $managementNode = Get-VMGroupManagementNode `
            -clusterName $clusterName

        $existingGroup = Get-VMGroup `
            -ComputerName $managementNode `
            -ErrorAction Stop |
            Where-Object {
                $_.GroupType -eq "VMCollectionType" -and
                $_.Name -eq $groupName
            }

        if ($existingGroup) {
            Write-Host ""
            Write-Host "Group '$groupName' already exists." `
                -ForegroundColor Yellow
            return
        }

        New-VMGroup `
            -ComputerName $managementNode `
            -Name $groupName `
            -GroupType VMCollectionType `
            -ErrorAction Stop |
            Out-Null

        Write-Host ""
        Write-Host "Group '$groupName' has been created." `
            -ForegroundColor Green

        Write-Host "Created using node: $managementNode" `
            -ForegroundColor DarkGray
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}


# ============================================================
# Delete VM Group
# ============================================================

function Delete-VMGroup {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    try {
        $managementNode = Get-VMGroupManagementNode `
            -clusterName $clusterName

        $groups = Get-ClusterVMGroups `
            -clusterName $clusterName

        Write-Host ""
        Write-Host "Existing Groups:" -ForegroundColor Yellow

        $groups | ForEach-Object {
            Write-Host "  $($_.Name)" -ForegroundColor DarkCyan
        }

        Write-Host ""

        $groupName = Read-Host "Enter Group Name to Delete"

        $group = $groups |
            Where-Object {
                $_.Name -eq $groupName
            }

        if ($null -eq $group) {
            Write-Host "Group '$groupName' does not exist." `
                -ForegroundColor Yellow
            return
        }

        $vmsInGroup = @($group.VMMembers)

        if ($vmsInGroup.Count -gt 0) {

            Write-Host ""
            Write-Host "Group '$groupName' contains:" `
                -ForegroundColor Yellow

            $vmsInGroup |
                Sort-Object Name |
                ForEach-Object {
                    Write-Host "  $($_.Name)"
                }

            Write-Host ""
            Write-Host "Cannot delete a group containing VMs." `
                -ForegroundColor Yellow

            return
        }

        Remove-VMGroup `
            -ComputerName $managementNode `
            -Name $groupName `
            -Force `
            -ErrorAction Stop

        Write-Host ""
        Write-Host "Group '$groupName' has been deleted." `
            -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}


# ============================================================
# Rename VM Group
# ============================================================

function Rename-VMGroupMenu {
    param (
        [Parameter(Mandatory)]
        [string]$clusterName
    )

    try {
        $managementNode = Get-VMGroupManagementNode `
            -clusterName $clusterName

        $groups = Get-ClusterVMGroups `
            -clusterName $clusterName

        Write-Host ""
        Write-Host "Existing Groups:" -ForegroundColor Yellow

        $groups | ForEach-Object {
            Write-Host "  $($_.Name)" -ForegroundColor DarkCyan
        }

        Write-Host ""

        $oldGroupName = Read-Host "Enter Old Group Name"

        $group = $groups |
            Where-Object {
                $_.Name -eq $oldGroupName
            }

        if ($null -eq $group) {
            Write-Host "Group '$oldGroupName' does not exist." `
                -ForegroundColor Yellow
            return
        }

        $newGroupName = Read-Host "Enter New Group Name"

        if ([string]::IsNullOrWhiteSpace($newGroupName)) {
            Write-Host "New group name cannot be blank." `
                -ForegroundColor Red
            return
        }

        if ($groups.Name -contains $newGroupName) {
            Write-Host "Group '$newGroupName' already exists." `
                -ForegroundColor Yellow
            return
        }

        Rename-VMGroup `
            -ComputerName $managementNode `
            -Name $oldGroupName `
            -NewName $newGroupName `
            -ErrorAction Stop

        Write-Host ""
        Write-Host "Group '$oldGroupName' renamed to '$newGroupName'." `
            -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}


# ============================================================
# Main Menu
# ============================================================

do {

    Show-Menu

    $choice = Read-Host "Enter your choice"

    switch ($choice) {

        "1" {
            Add-VMToGroup -clusterName $clusterName
        }

        "2" {
            Move-VMToNewGroup -clusterName $clusterName
        }

        "3" {
            Remove-VMFromGroup -clusterName $clusterName
        }

        "4" {
            List-VMs -clusterName $clusterName
        }

        "5" {
            View-ExistingGroupMembership -clusterName $clusterName
        }

        "6" {
            List-VMGroups -clusterName $clusterName
        }

        "7" {
            Create-VMGroup -clusterName $clusterName
        }

        "8" {
            Delete-VMGroup -clusterName $clusterName
        }

        "9" {
            Rename-VMGroupMenu -clusterName $clusterName
        }

		"10" {

			if (-not $script:ChangesMade) {
				Write-Host "No VM Group changes were made. Exiting..."
				exit
			}

			Write-Host ""
			Write-Host "VM Group changes were made during this session." `
				-ForegroundColor Yellow

			Write-Host ""
			Write-Host "1. Restart VMMS and Exit"
			Write-Host "2. Exit Without Restarting VMMS"
			Write-Host "3. Cancel"
			Write-Host ""

			$exitChoice = Read-Host "Select"

			switch ($exitChoice) {

				"1" {
					try {
						$managementNode = Get-VMGroupManagementNode `
							-clusterName $clusterName

						Write-Host ""
						Write-Host "Restarting VMMS on $managementNode..." `
							-ForegroundColor Yellow

						Invoke-Command `
							-ComputerName $managementNode `
							-ScriptBlock {
								Restart-Service vmms -ErrorAction Stop
							}

						Write-Host "VMMS restarted successfully." `
							-ForegroundColor Green

						exit
					}
					catch {
						Write-Host "VMMS restart failed: $_" `
							-ForegroundColor Red
					}
				}

				"2" {
					Write-Host "Exiting without restarting VMMS."
					exit
				}

				"3" {
					return
				}
			}
		}

        default {
            Write-Host ""
            Write-Host "Invalid choice, please try again." `
                -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "Press any key to return to the menu..."
    [void][System.Console]::ReadKey($true)

} while ($true)
