[CmdletBinding()]
param(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPIncomingEmailSettings'
$script:DSCResourceFullName = 'MSFT_' + $script:DSCResourceName

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -DscResource $script:DSCResourceName
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:DSCModuleName `
        -DSCResourceName $script:DSCResourceFullName `
        -ResourceType 'Mof' `
        -TestType 'Unit'
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

try
{
    InModuleScope -ModuleName $script:DSCResourceFullName -ScriptBlock {
        Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
            BeforeAll {
                Invoke-Command -ScriptBlock $Global:SPDscHelper.InitializeScript -NoNewScope

                # Initialize tests

                # Mocks for all contexts
                Mock -CommandName 'Get-SPServiceInstance' -MockWith {
                    $serviceInstance =
                    @{
                        Service = @{
                            Enabled                          = $mock.Enabled
                            DropFolder                       = $mock.DropFolder
                            UseAutomaticSettings             = $mock.UseAutomaticSettings
                            ServerDisplayAddress             = $mock.ServerDisplayAddress
                            ServerAddress                    = $mock.ServerAddress
                            UseDirectoryManagementService    = $mock.UseDirectoryManagementService
                            RemoteDirectoryManagementService = $mock.RemoteDirectoryManagementService
                            DirectoryManagementServiceURL    = $mock.DirectoryManagementServiceURL
                            DistributionGroupsEnabled        = $mock.DistributionGroupsEnabled
                            DLsRequireAuthenticatedSenders   = $mock.DLsRequireAuthenticatedSenders
                        }
                    }
                    $serviceInstance = $serviceInstance | Add-Member -MemberType ScriptMethod -Name GetType -Value {
                        return @{ FullName = "Microsoft.SharePoint.Administration.SPIncomingEmailServiceInstance" } } -Force -PassThru
                    $serviceInstance.Service = $serviceInstance.Service | Add-Member -MemberType ScriptMethod -Name GetType -Value {
                        return @{ FullName = "Microsoft.SharePoint.Administration.SPIncomingEmailService" } } -Force -PassThru
                    $serviceInstance.Service = $serviceInstance.Service | Add-Member -MemberType ScriptMethod -Name Update -Value {
                        $Global:SPDscUpdateCalled = $true } -PassThru
                    return @($serviceInstance)
                }

                function Add-SPDscEvent
                {
                    param (
                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Message,

                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Source,

                        [Parameter()]
                        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
                        [System.String]
                        $EntryType,

                        [Parameter()]
                        [System.UInt32]
                        $EventID
                    )
                }
            }

            # Test contexts
            Context -Name 'Cannot retrieve instance of mail service' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance     = 'Yes'
                        Ensure               = 'Present'
                        UseAutomaticSettings = $true
                        ServerDisplayAddress = "contoso.com"
                    }

                    Mock -CommandName 'Get-SPServiceInstance' -MockWith {
                        $serviceInstance = @{ }
                        $serviceInstance = $serviceInstance | Add-Member -MemberType ScriptMethod -Name GetType -Value {
                            return $null } -Force -PassThru
                        return @($serviceInstance)
                    }
                }

                It 'Should return null values for the Get method' {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -BeNullorEmpty
                    $result.UseAutomaticSettings | Should -BeNullorEmpty
                    $result.UseDirectoryManagementService | Should -BeNullorEmpty
                    $result.RemoteDirectoryManagementURL | Should -BeNullorEmpty
                    $result.ServerAddress | Should -BeNullorEmpty
                    $result.DLsRequireAuthenticatedSenders | Should -BeNullorEmpty
                    $result.DistributionGroupsEnabled | Should -BeNullorEmpty
                    $result.ServerDisplayAddress | Should -BeNullorEmpty
                    $result.DropFolder | Should -BeNullorEmpty
                }

                It 'Should return false for the Test method' {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It 'Should throw and exception for the Set method' {
                    { Set-TargetResource @testParams } | Should -Throw "Error getting the SharePoint Incoming Email Service"
                }
            }

            Context -Name 'When configured values are correct' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance               = 'Yes'
                        Ensure                         = 'Present'
                        UseAutomaticSettings           = $false
                        UseDirectoryManagementService  = 'Remote'
                        RemoteDirectoryManagementURL   = 'http://server:adminport/_vti_bin/SharepointEmailWS.asmx'
                        DLsRequireAuthenticatedSenders = $false
                        DistributionGroupsEnabled      = $true
                        ServerDisplayAddress           = "contoso.com"
                        DropFolder                     = '\\MailServer\SharedFolder'
                    }

                    $mock = @{
                        TypeName                         = 'Microsoft SharePoint Foundation Incoming E-Mail'
                        Enabled                          = $true
                        DropFolder                       = $testParams.DropFolder
                        UseAutomaticSettings             = $testParams.UseAutomaticSettings
                        ServerDisplayAddress             = $testParams.ServerDisplayAddress
                        ServerAddress                    = $testParams.ServerAddress
                        UseDirectoryManagementService    = $true
                        RemoteDirectoryManagementService = $true
                        DirectoryManagementServiceURL    = $testParams.RemoteDirectoryManagementURL
                        DistributionGroupsEnabled        = $testParams.DistributionGroupsEnabled
                        DLsRequireAuthenticatedSenders   = $testParams.DLsRequireAuthenticatedSenders
                    }
                }

                It "Should return current values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be $testParams.Ensure
                    $result.UseAutomaticSettings | Should -Be $testParams.UseAutomaticSettings
                    $result.UseDirectoryManagementService | Should -Be $testParams.UseDirectoryManagementService
                    $result.RemoteDirectoryManagementURL | Should -Be $testParams.RemoteDirectoryManagementURL
                    $result.DLsRequireAuthenticatedSenders | Should -Be $testParams.DLsRequireAuthenticatedSenders
                    $result.DistributionGroupsEnabled | Should -Be $testParams.DistributionGroupsEnabled
                    $result.ServerDisplayAddress | Should -Be $testParams.ServerDisplayAddress
                    $result.DropFolder | Should -Be $testParams.DropFolder
                }

                It "Should return True for the Test method" {
                    Test-TargetResource @testParams | Should -Be $true
                }

            }

            Context -Name 'When configured values are incorrect' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance               = 'Yes'
                        Ensure                         = 'Present'
                        UseAutomaticSettings           = $false
                        UseDirectoryManagementService  = 'Remote'
                        RemoteDirectoryManagementURL   = 'http://server:adminport/_vti_bin/SharepointEmailWS.asmx'
                        DLsRequireAuthenticatedSenders = $false
                        DistributionGroupsEnabled      = $true
                        ServerDisplayAddress           = "contoso.com"
                        DropFolder                     = '\\MailServer\SharedFolder'
                    }

                    $mock = @{
                        Enabled                          = $true
                        DropFolder                       = $null
                        UseAutomaticSettings             = (-not $testParams.UseAutomaticSettings)
                        ServerDisplayAddress             = $testParams.ServerDisplayAddress
                        ServerAddress                    = $testParams.ServerAddress
                        UseDirectoryManagementService    = $true
                        RemoteDirectoryManagementService = $false
                        DirectoryManagementServiceURL    = $null
                        DistributionGroupsEnabled        = $testParams.DistributionGroupsEnabled
                        DLsRequireAuthenticatedSenders   = $testParams.DLsRequireAuthenticatedSenders
                    }
                }

                It "Should return current values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be $testParams.Ensure
                    $result.UseAutomaticSettings | Should -Be (-not $testParams.UseAutomaticSettings)
                    $result.UseDirectoryManagementService | Should -Be $true
                    $result.RemoteDirectoryManagementURL | Should -BeNullorEmpty
                    $result.DLsRequireAuthenticatedSenders | Should -Be $testParams.DLsRequireAuthenticatedSenders
                    $result.DistributionGroupsEnabled | Should -Be $testParams.DistributionGroupsEnabled
                    $result.ServerDisplayAddress | Should -Be $testParams.ServerDisplayAddress
                    $result.DropFolder | Should -BeNullorEmpty
                }

                It "Should return False for the Test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should update settings for the Set method" {
                    Set-TargetResource @testParams
                    $Global:SPDscUpdateCalled | Should -Be $true
                }
            }

            Context -Name 'When service is disabled, but should be enabled' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance               = 'Yes'
                        Ensure                         = 'Present'
                        UseAutomaticSettings           = $false
                        UseDirectoryManagementService  = 'Remote'
                        RemoteDirectoryManagementURL   = 'http://server:adminport/_vti_bin/SharepointEmailWS.asmx'
                        DLsRequireAuthenticatedSenders = $false
                        DistributionGroupsEnabled      = $true
                        ServerDisplayAddress           = "contoso.com"
                        DropFolder                     = '\\MailServer\SharedFolder'
                    }

                    $mock = @{
                        Enabled                          = $false
                        DropFolder                       = $null
                        UseAutomaticSettings             = $testParams.UseAutomaticSettings
                        ServerDisplayAddress             = $null
                        ServerAddress                    = $null
                        UseDirectoryManagementService    = $false
                        RemoteDirectoryManagementService = $false
                        DirectoryManagementServiceURL    = $null
                        DistributionGroupsEnabled        = $false
                        DLsRequireAuthenticatedSenders   = $false
                    }
                }

                It "Should return null values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be 'Absent'
                    $result.UseAutomaticSettings | Should -BeNullorEmpty
                    $result.UseDirectoryManagementService | Should -BeNullorEmpty
                    $result.RemoteDirectoryManagementURL | Should -BeNullorEmpty
                    $result.DLsRequireAuthenticatedSenders | Should -BeNullorEmpty
                    $result.DistributionGroupsEnabled | Should -BeNullorEmpty
                    $result.ServerDisplayAddress | Should -BeNullorEmpty
                    $result.DropFolder | Should -BeNullorEmpty
                }

                It "Should return False for the Test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should update settings for the Set method" {
                    Set-TargetResource @testParams
                    $Global:SPDscUpdateCalled | Should -Be $true
                }
            }

            Context -Name 'When service is enabled, but should be disabled' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance = 'Yes'
                        Ensure           = 'Absent'
                    }

                    $mock = @{
                        Enabled                          = $true
                        DropFolder                       = $null
                        UseAutomaticSettings             = $true
                        ServerDisplayAddress             = 'contoso.com'
                        ServerAddress                    = $null
                        UseDirectoryManagementService    = $false
                        RemoteDirectoryManagementService = $false
                        DirectoryManagementServiceURL    = $null
                        DistributionGroupsEnabled        = $false
                        DLsRequireAuthenticatedSenders   = $false
                    }
                }

                It "Should return current values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be 'Present'
                    $result.UseAutomaticSettings | Should -Be $mock.UseAutomaticSettings
                    $result.UseDirectoryManagementService | Should -Be 'No'
                    $result.RemoteDirectoryManagementURL | Should -BeNullorEmpty
                    $result.DLsRequireAuthenticatedSenders | Should -Be $mock.DLsRequireAuthenticatedSenders
                    $result.DistributionGroupsEnabled | Should -Be $mock.DistributionGroupsEnabled
                    $result.ServerDisplayAddress | Should -Be $mock.ServerDisplayAddress
                    $result.DropFolder | Should -BeNullorEmpty
                }

                It "Should return False for the Test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should update settings for the Set method" {
                    Set-TargetResource @testParams
                    $Global:SPDscUpdateCalled | Should -Be $true
                }
            }

            Context -Name 'When switching from manual to automatic settings' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance              = 'Yes'
                        Ensure                        = 'Present'
                        UseAutomaticSettings          = $true
                        UseDirectoryManagementService = 'No'
                        ServerDisplayAddress          = "contoso.com"
                    }

                    $mock = @{
                        Enabled                          = $true
                        DropFolder                       = '\\MailServer\SharedFolder'
                        UseAutomaticSettings             = (-not $testParams.UseAutomaticSettings)
                        ServerDisplayAddress             = $testParams.ServerDisplayAddress
                        ServerAddress                    = $null
                        UseDirectoryManagementService    = $false
                        RemoteDirectoryManagementService = $false
                        DirectoryManagementServiceURL    = $null
                        DistributionGroupsEnabled        = $false
                        DLsRequireAuthenticatedSenders   = $false
                    }
                }

                It "Should return current values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be $testParams.Ensure
                    $result.UseAutomaticSettings | Should -Be (-not $testParams.UseAutomaticSettings)
                    $result.UseDirectoryManagementService | Should -Be $testParams.UseDirectoryManagementService
                    $result.RemoteDirectoryManagementURL | Should -BeNullorEmpty
                    $result.DLsRequireAuthenticatedSenders | Should -Be $mock.DLsRequireAuthenticatedSenders
                    $result.DistributionGroupsEnabled | Should -Be $mock.DistributionGroupsEnabled
                    $result.ServerDisplayAddress | Should -Be $testParams.ServerDisplayAddress
                    $result.DropFolder | Should -Be $mock.DropFolder
                }

                It "Should return False for the Test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should update settings for the Set method" {
                    Set-TargetResource @testParams
                    $Global:SPDscUpdateCalled | Should -Be $true
                }
            }

            Context -Name 'When updating ServerAddress and Directory Managment Service' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance              = 'Yes'
                        Ensure                        = 'Present'
                        UseAutomaticSettings          = $false
                        UseDirectoryManagementService = 'Yes'
                        ServerDisplayAddress          = "contoso.com"
                        ServerAddress                 = "mail.contoso.com"
                        DropFolder                    = '\\MailServer\SharedFolder'
                    }

                    $mock = @{
                        Enabled                          = $true
                        DropFolder                       = $testParams.DropFolder
                        UseAutomaticSettings             = $testParams.UseAutomaticSettings
                        ServerDisplayAddress             = $testParams.ServerDisplayAddress
                        ServerAddress                    = "oldserver.contoso.com"
                        UseDirectoryManagementService    = $true
                        RemoteDirectoryManagementService = $true
                        DirectoryManagementServiceURL    = 'http://server:adminport/_vti_bin/SharepointEmailWS.asmx'
                        DistributionGroupsEnabled        = $false
                        DLsRequireAuthenticatedSenders   = $false
                    }
                }

                It "Should return null values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be 'Present'
                    $result.UseAutomaticSettings | Should -Be $mock.UseAutomaticSettings
                    $result.UseDirectoryManagementService | Should -Be 'Remote'
                    $result.RemoteDirectoryManagementURL | Should -Be $mock.DirectoryManagementServiceURL
                    $result.DLsRequireAuthenticatedSenders | Should -Be $mock.DLsRequireAuthenticatedSenders
                    $result.DistributionGroupsEnabled | Should -Be $mock.DistributionGroupsEnabled
                    $result.ServerDisplayAddress | Should -Be $mock.ServerDisplayAddress
                    $result.ServerAddress | Should -Be $mock.ServerAddress
                    $result.DropFolder | Should -Be $mock.DropFolder
                }

                It "Should return False for the Test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should update settings for the Set method" {
                    Set-TargetResource @testParams
                    $Global:SPDscUpdateCalled | Should -Be $true
                }
            }

            Context -Name 'When enabling Incoming Email, but not specifying required ServerDisplayAddress parameter' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance               = 'Yes'
                        Ensure                         = 'Present'
                        UseAutomaticSettings           = $false
                        UseDirectoryManagementService  = 'Remote'
                        RemoteDirectoryManagementURL   = 'http://server:adminport/_vti_bin/SharepointEmailWS.asmx'
                        DLsRequireAuthenticatedSenders = $false
                        DistributionGroupsEnabled      = $true
                        #ServerDisplayAddress           = "contoso.com"
                        DropFolder                     = '\\MailServer\SharedFolder'
                    }

                    $mock = @{
                        Enabled                          = $true
                        DropFolder                       = $null
                        UseAutomaticSettings             = $testParams.UseAutomaticSettings
                        ServerDisplayAddress             = $testParams.ServerDisplayAddress
                        ServerAddress                    = $testParams.ServerAddress
                        UseDirectoryManagementService    = $true
                        RemoteDirectoryManagementService = $true
                        DirectoryManagementServiceURL    = $testParams.RemoteDirectoryManagementURL
                        DistributionGroupsEnabled        = $testParams.DistributionGroupsEnabled
                        DLsRequireAuthenticatedSenders   = $testParams.DLsRequireAuthenticatedSenders
                    }
                }

                It "Should return current values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be $testParams.Ensure
                    $result.UseAutomaticSettings | Should -Be $testParams.UseAutomaticSettings
                    $result.UseDirectoryManagementService | Should -Be $testParams.UseDirectoryManagementService
                    $result.RemoteDirectoryManagementURL | Should -Be $testParams.RemoteDirectoryManagementURL
                    $result.DLsRequireAuthenticatedSenders | Should -Be $testParams.DLsRequireAuthenticatedSenders
                    $result.DistributionGroupsEnabled | Should -Be $testParams.DistributionGroupsEnabled
                    $result.ServerDisplayAddress | Should -Be $testParams.ServerDisplayAddress
                    $result.DropFolder | Should -BeNullorEmpty
                }

                It "Should return False for the Test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an exception for the Set method" {
                    { Set-TargetResource @testParams } | Should -Throw "ServerDisplayAddress parameter must be specified when enabling incoming email"
                }
            }

            Context -Name 'When enabling Incoming Email, but not specifying required UseAutomaticSettings parameter' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance               = 'Yes'
                        Ensure                         = 'Present'
                        #UseAutomaticSettings           = $false
                        UseDirectoryManagementService  = 'Remote'
                        RemoteDirectoryManagementURL   = 'http://server:adminport/_vti_bin/SharepointEmailWS.asmx'
                        DLsRequireAuthenticatedSenders = $false
                        DistributionGroupsEnabled      = $true
                        ServerDisplayAddress           = "contoso.com"
                        DropFolder                     = '\\MailServer\SharedFolder'
                    }

                    $mock = @{
                        Enabled                          = $true
                        DropFolder                       = $null
                        UseAutomaticSettings             = $true
                        ServerDisplayAddress             = $testParams.ServerDisplayAddress
                        ServerAddress                    = $testParams.ServerAddress
                        UseDirectoryManagementService    = $true
                        RemoteDirectoryManagementService = $true
                        DirectoryManagementServiceURL    = $testParams.RemoteDirectoryManagementURL
                        DistributionGroupsEnabled        = $testParams.DistributionGroupsEnabled
                        DLsRequireAuthenticatedSenders   = $testParams.DLsRequireAuthenticatedSenders
                    }
                }

                It "Should return current values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be $testParams.Ensure
                    $result.UseAutomaticSettings | Should -Be $mock.UseAutomaticSettings
                    $result.UseDirectoryManagementService | Should -Be $testParams.UseDirectoryManagementService
                    $result.RemoteDirectoryManagementURL | Should -Be $testParams.RemoteDirectoryManagementURL
                    $result.DLsRequireAuthenticatedSenders | Should -Be $testParams.DLsRequireAuthenticatedSenders
                    $result.DistributionGroupsEnabled | Should -Be $testParams.DistributionGroupsEnabled
                    $result.ServerDisplayAddress | Should -Be $testParams.ServerDisplayAddress
                    $result.DropFolder | Should -BeNullorEmpty
                }

                It "Should return False for the Test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an exception for the Set method" {
                    { Set-TargetResource @testParams } | Should -Throw "UseAutomaticSettings parameter must be specified when enabling incoming email."
                }
            }

            Context -Name 'When no RemoteDirectoryManagementURL specified for UseDirectoryManagementService = Remote' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance               = 'Yes'
                        Ensure                         = 'Present'
                        UseAutomaticSettings           = $false
                        UseDirectoryManagementService  = 'Remote'
                        DLsRequireAuthenticatedSenders = $false
                        DistributionGroupsEnabled      = $true
                        ServerDisplayAddress           = "contoso.com"
                        DropFolder                     = '\\MailServer\SharedFolder'
                    }

                    $mock = @{
                        Enabled                          = $true
                        DropFolder                       = $null
                        UseAutomaticSettings             = $testParams.UseAutomaticSettings
                        ServerDisplayAddress             = $testParams.ServerDisplayAddress
                        ServerAddress                    = $testParams.ServerAddress
                        UseDirectoryManagementService    = $true
                        RemoteDirectoryManagementService = $true
                        DirectoryManagementServiceURL    = $testParams.RemoteDirectoryManagementURL
                        DistributionGroupsEnabled        = $testParams.DistributionGroupsEnabled
                        DLsRequireAuthenticatedSenders   = $testParams.DLsRequireAuthenticatedSenders
                    }
                }

                It "Should return current values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be $testParams.Ensure
                    $result.UseAutomaticSettings | Should -Be $testParams.UseAutomaticSettings
                    $result.UseDirectoryManagementService | Should -Be $testParams.UseDirectoryManagementService
                    $result.RemoteDirectoryManagementURL | Should -Be $testParams.RemoteDirectoryManagementURL
                    $result.DLsRequireAuthenticatedSenders | Should -Be $testParams.DLsRequireAuthenticatedSenders
                    $result.DistributionGroupsEnabled | Should -Be $testParams.DistributionGroupsEnabled
                    $result.ServerDisplayAddress | Should -Be $testParams.ServerDisplayAddress
                    $result.DropFolder | Should -BeNullorEmpty
                }

                It "Should return False for the Test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an exception for the Set method" {
                    { Set-TargetResource @testParams } | Should -Throw "RemoteDirectoryManagementURL must be specified only when UseDirectoryManagementService is set to 'Remote'"
                }
            }

            Context -Name 'When AutomaticMode is false, but no DropFolder specified' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance               = 'Yes'
                        Ensure                         = 'Present'
                        UseAutomaticSettings           = $false
                        UseDirectoryManagementService  = 'Remote'
                        RemoteDirectoryManagementURL   = 'http://server:adminport/_vti_bin/SharepointEmailWS.asmx'
                        DLsRequireAuthenticatedSenders = $false
                        DistributionGroupsEnabled      = $true
                        ServerDisplayAddress           = "contoso.com"
                    }

                    $mock = @{
                        Enabled                          = $true
                        DropFolder                       = $null
                        UseAutomaticSettings             = $true
                        ServerDisplayAddress             = $testParams.ServerDisplayAddress
                        ServerAddress                    = $testParams.ServerAddress
                        UseDirectoryManagementService    = $true
                        RemoteDirectoryManagementService = $true
                        DirectoryManagementServiceURL    = $testParams.RemoteDirectoryManagementURL
                        DistributionGroupsEnabled        = $testParams.DistributionGroupsEnabled
                        DLsRequireAuthenticatedSenders   = $testParams.DLsRequireAuthenticatedSenders
                    }
                }

                It "Should return current values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be $testParams.Ensure
                    $result.UseAutomaticSettings | Should -Be $true
                    $result.UseDirectoryManagementService | Should -Be $testParams.UseDirectoryManagementService
                    $result.RemoteDirectoryManagementURL | Should -Be $testParams.RemoteDirectoryManagementURL
                    $result.DLsRequireAuthenticatedSenders | Should -Be $testParams.DLsRequireAuthenticatedSenders
                    $result.DistributionGroupsEnabled | Should -Be $testParams.DistributionGroupsEnabled
                    $result.ServerDisplayAddress | Should -Be $testParams.ServerDisplayAddress
                    $result.DropFolder | Should -BeNullorEmpty
                }

                It "Should return False for the Test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an exception for the Set method" {
                    { Set-TargetResource @testParams } | Should -Throw "DropFolder parameter must be specified when not using Automatic Mode"
                }
            }

            Context -Name 'When AutomaticMode is true, but a DropFolder was specified' -Fixture {
                BeforeAll {
                    $testParams = @{
                        IsSingleInstance               = 'Yes'
                        Ensure                         = 'Present'
                        UseAutomaticSettings           = $true
                        UseDirectoryManagementService  = 'Remote'
                        RemoteDirectoryManagementURL   = 'http://server:adminport/_vti_bin/SharepointEmailWS.asmx'
                        DLsRequireAuthenticatedSenders = $false
                        DistributionGroupsEnabled      = $true
                        ServerDisplayAddress           = "contoso.com"
                        DropFolder                     = '\\MailServer\SharedFolder'
                    }

                    $mock = @{
                        Enabled                          = $true
                        DropFolder                       = $null
                        UseAutomaticSettings             = $testParams.UseAutomaticSettings
                        ServerDisplayAddress             = $testParams.ServerDisplayAddress
                        ServerAddress                    = $testParams.ServerAddress
                        UseDirectoryManagementService    = $true
                        RemoteDirectoryManagementService = $true
                        DirectoryManagementServiceURL    = $testParams.RemoteDirectoryManagementURL
                        DistributionGroupsEnabled        = $testParams.DistributionGroupsEnabled
                        DLsRequireAuthenticatedSenders   = $testParams.DLsRequireAuthenticatedSenders
                    }
                }

                It "Should return current values for the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should -Be $testParams.Ensure
                    $result.UseAutomaticSettings | Should -Be $testParams.UseAutomaticSettings
                    $result.UseDirectoryManagementService | Should -Be $testParams.UseDirectoryManagementService
                    $result.RemoteDirectoryManagementURL | Should -Be $testParams.RemoteDirectoryManagementURL
                    $result.DLsRequireAuthenticatedSenders | Should -Be $testParams.DLsRequireAuthenticatedSenders
                    $result.DistributionGroupsEnabled | Should -Be $testParams.DistributionGroupsEnabled
                    $result.ServerDisplayAddress | Should -Be $testParams.ServerDisplayAddress
                    $result.DropFolder | Should -BeNullorEmpty
                }

                It "Should return False for the Test method" {
                    Test-TargetResource @testParams | Should -Be $false
                }

                It "Should throw an exception for the Set method" {
                    { Set-TargetResource @testParams } | Should -Throw "DropFolder parameter is not valid when using Automatic Mode"
                }
            }

        }
    }
}
finally
{
    Invoke-TestCleanup
}
