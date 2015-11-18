function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)] [System.String] $Name,
        [parameter(Mandatory = $false)] [System.String[]] $Members,
        [parameter(Mandatory = $false)] [System.String[]] $MembersToInclude,
        [parameter(Mandatory = $false)] [System.String[]] $MembersToExclude,
        [parameter(Mandatory = $false)] [System.Management.Automation.PSCredential] $InstallAccount
    )

    Write-Verbose -Message "Getting all Farm Administrators"

    $result = Invoke-xSharePointCommand -Credential $InstallAccount -Arguments $PSBoundParameters -ScriptBlock {
        $caWebapp = Get-SPwebapplication -includecentraladministration | where {$_.IsAdministrationWebApplication}
        $caWeb = Get-SPweb($caWebapp.Url)
        $farmAdminGroup = $caWeb.AssociatedOwnerGroup
        $farmAdministratorsGroup = $caWeb.SiteGroups[$farmAdminGroup]
        return $farmAdministratorsGroup.users.UserLogin
    }
    return $result
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)] [System.String] $Name,
        [parameter(Mandatory = $false)] [System.String[]] $Members,
        [parameter(Mandatory = $false)] [System.String[]] $MembersToInclude,
        [parameter(Mandatory = $false)] [System.String[]] $MembersToExclude,
        [parameter(Mandatory = $false)] [System.Management.Automation.PSCredential] $InstallAccount
    )

    Write-Verbose -Message "Setting Farm Administrator config"
    
    if ($Members -and (($MembersToInclude) -or ($MembersToExclude))) {
        Throw "Cannot use the Members parameter together with the MembersToInclude or MembersToExclude parameters"
    }

    $CurrentValues = Get-TargetResource @PSBoundParameters
    $changeUsers = @{}
    $runChange = $false
    
    if ($Members) {
        Write-Verbose "Processing Members parameter"
        $differences = Compare-Object -ReferenceObject $CurrentValues -DifferenceObject $Members
        if ($differences -eq $null) {
            Write-Verbose "Farm Administrators group matches. No further processing required"
        } else {
            Write-Verbose "Farm Administrators group does not match. Perform corrective action"
            $addUsers = @()
            $removeUsers = @()
            ForEach ($difference in $differences) {
                if ($difference.SideIndicator -eq "=>") {
                    # Add account
                    $user = $difference.InputObject
                    Write-Verbose "Add $user to Add list"
                    $addUsers += $user
                } elseif ($difference.SideIndicator -eq "<=") {
                    # Remove account
                    $user = $difference.InputObject
                    Write-Verbose "Add $user to Remove list"
                    $removeUsers += $user
                }
            }

            if($addUsers.count -gt 0) { 
                Write-Verbose "Adding $($addUsers.Count) users to the Farm Administrators group"
                $changeUsers.Add = $addUsers
                $runChange = $true
            }

            if($removeUsers.count -gt 0) { 
                Write-Verbose "Removing $($removeUsers.Count) users from the Farm Administrators group"
                $changeUsers.Remove = $removeUsers
                $runChange = $true
            }
        }
    }

    if ($MembersToInclude) {
        Write-Verbose "Processing MembersToInclude parameter"
        
        $addUsers = @()
        ForEach ($member in $MembersToInclude) {
            if (-not($CurrentValues.Contains($member))) {
                Write-Verbose "$member is not a Farm Administrator. Add user to Add list"
                $addUsers += $member
            } else {
                Write-Verbose "$member is already a Farm Administrator. Skipping"
            }
        }

        if($addUsers.count -gt 0) { 
            Write-Verbose "Adding $($addUsers.Count) users to the Farm Administrators group"
            $changeUsers.Add = $addUsers
            $runChange = $true
        }
    }

    if ($MembersToExclude) {
        Write-Verbose "Processing MembersToExclude parameter"
        
        $removeUsers = @()
        ForEach ($member in $MembersToExclude) {
            if ($CurrentValues.Contains($member)) {
                Write-Verbose "$member is a Farm Administrator. Add user to Remove list"
                $removeUsers += $member
            } else {
                Write-Verbose "$member is not a Farm Administrator. Skipping"
            }
        }

        if($removeUsers.count -gt 0) { 
            Write-Verbose "Removing $($removeUsers.Count) users from the Farm Administrators group"
            $changeUsers.Remove = $removeUsers
            $runChange = $true
        }
    }

    if ($runChange) {
        Write-Verbose "Apply changes"
        Change-SPFarmAdministrators $changeUsers
    }
}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)] [System.String] $Name,
        [parameter(Mandatory = $false)] [System.String[]] $Members,
        [parameter(Mandatory = $false)] [System.String[]] $MembersToInclude,
        [parameter(Mandatory = $false)] [System.String[]] $MembersToExclude,
        [parameter(Mandatory = $false)] [System.Management.Automation.PSCredential] $InstallAccount
    )

    Write-Verbose -Message "Testing Farm Administrator settings"
    
    if ($Members -and (($MembersToInclude) -or ($MembersToExclude))) {
        Throw "Cannot use the Members parameter together with the MembersToInclude or MembersToExclude parameters"
    }

    $CurrentValues = Get-TargetResource @PSBoundParameters
    
    if ($Members) {
        Write-Verbose "Processing Members parameter"
        $differences = Compare-Object -ReferenceObject $CurrentValues -DifferenceObject $Members
        if ($differences -eq $null) {
            Write-Verbose "Farm Administrators group matches"
            return $true
        } else {
            Write-Verbose "Farm Administrators group does not match"
            return $false
        }
    }

    $result = $true
    if ($MembersToInclude) {
        Write-Verbose "Processing MembersToInclude parameter"
        ForEach ($member in $MembersToInclude) {
            if (-not($CurrentValues.Contains($member))) {
                Write-Verbose "$member is not a Farm Administrator. Set result to false"
                $result = $false
            } else {
                Write-Verbose "$member is already a Farm Administrator. Skipping"
            }
        }
    }

    if ($MembersToExclude) {
        Write-Verbose "Processing MembersToExclude parameter"
        ForEach ($member in $MembersToExclude) {
            if ($CurrentValues.Contains($member)) {
                Write-Verbose "$member is a Farm Administrator. Set result to false"
                $result = $false
            } else {
                Write-Verbose "$member is not a Farm Administrator. Skipping"
            }
        }
    }

    return $result
}

function Change-SPFarmAdministrators {
Param ([Hashtable] $changeUsers)

    $result = Invoke-xSharePointCommand -Credential $InstallAccount -Arguments $changeUsers -ScriptBlock {
        $changeUsers = $args[0]

        if ($changeUsers.ContainsKey("Add")) {
            $caWebapp = Get-SPwebapplication -includecentraladministration | where {$_.IsAdministrationWebApplication}
            $caWeb = Get-SPweb($caWebapp.Url)
            $farmAdminGroup = $caWeb.AssociatedOwnerGroup

            ForEach ($loginName in $changeUsers.Add) {
                $caWeb.SiteGroups[$farmAdminGroup].AddUser($loginName,"","","")
            }
        }
        
        if ($changeUsers.ContainsKey("Remove")) {
            $caWebapp = Get-SPwebapplication -includecentraladministration | where {$_.IsAdministrationWebApplication}
            $caWeb = Get-SPweb($caWebapp.Url)
            $farmAdminGroup = $caWeb.AssociatedOwnerGroup

            ForEach ($loginName in $changeUsers.Remove) {
                $removeUser = get-spuser $loginName -web $caWebapp.Url
                $caWeb.SiteGroups[$farmAdminGroup].RemoveUser($removeUser)
            }
        }
    }
}

Export-ModuleMember -Function *-TargetResource

