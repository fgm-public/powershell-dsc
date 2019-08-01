
#Requires -module xActiveDirectory
#Requires -module xDnsServer
#Requires -module xDHCPServer
#Requires -module xPendingReboot

<#
    .SYNOPSIS
        Promote HA Active Directory domain with DNS and DHCP services
    .DESCRIPTION
        This configuration promote a highly available Active Directory
        domain with two domain controllers. DNS servers with forward and
        reverse lookup zones, authorized DHCP servers with two scopes,
        both located on DC's.

    .PARAMETER DomainAdministratorCred
        Domain Administrator password

    .PARAMETER SafemodeAdministratorCred
        Domain Administrator password (recovery mode)

    .PARAMETER NewADUserCred
        First AD user password

    .EXAMPLE
        $config_params = @{
            ConfigurationData = '.\ConfigurationData.psd1';
            SafemodeAdministratorCred = 'safepass';
            DomainAdministratorCred = 'adminpass';
            NewADUserCred = 'userpass';
        }
        ADComplete @config_params    
    
    .NOTES
        01.08.2019 - public version
#>

Configuration ADComplete
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $DomainAdministratorCred,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SafemodeAdministratorCred,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $NewADUserCred
    )

    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName xDnsServer
    Import-DscResource -ModuleName xDHCPServer
    Import-DscResource -ModuleName xPendingReboot

    Node $AllNodes.Where{ $_.Role -eq 'Primary DC' }.NodeName
    {
        #Get-NetAdapter |
        #    Disable-NetAdapterBinding -ComponentID ms_tcpip6 -PassThru

        LocalConfigurationManager            
        {            
            ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'            
            RebootNodeIfNeeded = $true            
        }           

        Script 'Disable IPv6'
        {
            SetScript = {
                Get-NetAdapter |
                    Disable-NetAdapterBinding -ComponentID ms_tcpip6 -PassThru
            }
            TestScript = { $false
                <#(Get-NetAdapter |
                    Get-NetAdapterBinding |
                        Where-Object ComponentID -eq ms_tcpip6).Enabled[0] -eq $false#>
            }
            GetScript = {
                @{Result = ((Get-NetAdapter |
                    Get-NetAdapterBinding |
                        Where-Object ComponentID -eq ms_tcpip6).Enabled)
                }
            }
        }
        
        WindowsFeature 'ADDS'
        {
            Ensure = 'Present'
            Name   = 'AD-Domain-Services'
        }

        WindowsFeature 'DHCP'
        {
            Name   = 'DHCP'
            Ensure = 'Present'
            IncludeAllSubFeature = $true
        }
        
        xADDomain 'FirstDS'
        {
            DomainName                    = $ConfigurationData.ADConfig.DomainName
            DomainAdministratorCredential = $DomainAdministratorCred
            SafemodeAdministratorPassword = $SafemodeAdministratorCred
            #DnsDelegationCredential       = $DNSDelegationCred
            ForestMode                    = $ConfigurationData.ADConfig.FFL
            DependsOn                     = '[WindowsFeature]ADDS'
        }

        xPendingReboot Reboot0
        {
            Name      = "RebootServer"
            DependsOn = '[xADDomain]FirstDS'
        }

        xWaitForADDomain 'DscForestWait'
        {
            DomainName           = $ConfigurationData.ADConfig.DomainName
            DomainUserCredential = $DomainAdministratorCred
            RetryCount           = $ConfigurationData.ADConfig.RetryCount
            RetryIntervalSec     = $ConfigurationData.ADConfig.RetryIntervalSec
            DependsOn            = '[xADDomain]FirstDS'
        }

        xADUser 'FirstUser'
        {
            DomainName                    = $ConfigurationData.ADConfig.DomainName
            DomainAdministratorCredential = $DomainAdministratorCred
            UserName                      = 'user'
            Password                      = $NewADUserCred
            Ensure                        = 'Present'
            DependsOn                     = '[xWaitForADDomain]DscForestWait'
        }
    
        xDnsServerADZone addReverseADZone
        {
            Name                = $ConfigurationData.DNSConfig.Name
            DynamicUpdate       = $ConfigurationData.DNSConfig.DynamicUpdate
            ReplicationScope    = $ConfigurationData.DNSConfig.ReplicationScope
            Ensure              = 'Present'
            DependsOn           = '[xWaitForADDomain]DscForestWait'
        }

        xDhcpServerScope Scope
        {
            Ensure          = 'Present'
            Name            = $Node.DHCPScopeName
            ScopeID         = $ConfigurationData.DHCPConfig.ScopeID
            IPStartRange    = $Node.DHCPStartRange
            IPEndRange      = $Node.DHCPEndRange
            SubnetMask      = $ConfigurationData.DHCPConfig.SubnetMask
            LeaseDuration   = $ConfigurationData.DHCPConfig.LeaseDuration
            State           = $ConfigurationData.DHCPConfig.State
            AddressFamily   = $ConfigurationData.DHCPConfig.AddressFamily
            DependsOn       = '[WindowsFeature]DHCP'
        } 

        xDhcpServerOption Option
        {
            Ensure              = 'Present'
            ScopeID             = $ConfigurationData.DHCPConfig.ScopeID
            DnsDomain           = $ConfigurationData.DHCPConfig.DnsDomain
            Router              = $ConfigurationData.DHCPConfig.Router
            DnsServerIPAddress  = $ConfigurationData.DHCPConfig.DnsServerIPAddress
            AddressFamily       = $ConfigurationData.DHCPConfig.AddressFamily
            DependsOn           = '[xDhcpServerScope]Scope'
        }

        xDhcpServerAuthorization LocalServerActivation
        {
            Ensure = 'Present'
            DependsOn = @(
                            '[xDhcpServerScope]Scope',
                            '[xWaitForADDomain]DscForestWait'
                        )
        }

        xPendingReboot Reboot1
        { 
            Name = "RebootServer"
        }
    }

    Node $AllNodes.Where{ $_.Role -eq 'Replica DC' }.NodeName
    {

        LocalConfigurationManager            
        {            
            ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'            
            RebootNodeIfNeeded = $true            
        }           

        Script 'Disable IPv6'
        {
            SetScript = {
                Get-NetAdapter |
                    Disable-NetAdapterBinding -ComponentID ms_tcpip6 -PassThru
            }
            TestScript = { $false
                <#(Get-NetAdapter |
                    Get-NetAdapterBinding |
                        Where-Object ComponentID -eq ms_tcpip6).Enabled[0] -eq $false#>
            }
            GetScript = {
                @{Result = ((Get-NetAdapter |
                    Get-NetAdapterBinding |
                        Where-Object ComponentID -eq ms_tcpip6).Enabled)
                }
            }
        }
        
        WindowsFeature 'ADDS'
        {
            Ensure = 'Present'
            Name   = 'AD-Domain-Services'
        }

        WindowsFeature 'DHCP'
        {
            Name   = 'DHCP'
            Ensure = 'Present'
            IncludeAllSubFeature = $true
        }

        xWaitForADDomain 'DscForestWait'
        {
            DomainName           = $ConfigurationData.ADConfig.DomainName
            DomainUserCredential = $DomainAdministratorCred
            RetryCount           = $ConfigurationData.ADConfig.RetryCount
            RetryIntervalSec     = $ConfigurationData.ADConfig.RetryIntervalSec
            DependsOn            = '[WindowsFeature]ADDS'
        }

        xADDomainController 'SecondDC'
        {
            DomainName                    = $ConfigurationData.ADConfig.DomainName
            DomainAdministratorCredential = $DomainAdministratorCred
            SafemodeAdministratorPassword = $SafemodeAdministratorCred
            DependsOn                     = '[xWaitForADDomain]DscForestWait'
        }

        xDhcpServerScope Scope
        {
            Ensure          = 'Present'
            Name            = $Node.DHCPScopeName
            ScopeID         = $ConfigurationData.DHCPConfig.ScopeID
            IPStartRange    = $Node.DHCPStartRange
            IPEndRange      = $Node.DHCPEndRange
            SubnetMask      = $ConfigurationData.DHCPConfig.SubnetMask
            LeaseDuration   = $ConfigurationData.DHCPConfig.LeaseDuration
            State           = $ConfigurationData.DHCPConfig.State
            AddressFamily   = $ConfigurationData.DHCPConfig.AddressFamily
            DependsOn       = @(
                                '[WindowsFeature]DHCP',
                                '[xADDomainController]SecondDC'
                                )
        } 

        xDhcpServerOption Option
        {
            Ensure              = 'Present'
            ScopeID             = $ConfigurationData.DHCPConfig.ScopeID
            DnsDomain           = $ConfigurationData.DHCPConfig.DnsDomain
            Router              = $ConfigurationData.DHCPConfig.Router
            DnsServerIPAddress  = $ConfigurationData.DHCPConfig.DnsServerIPAddress
            AddressFamily       = $ConfigurationData.DHCPConfig.AddressFamily
            DependsOn           = '[xDhcpServerScope]Scope'
        }

        xDhcpServerAuthorization LocalServerActivation
        {
            Ensure = 'Present'
            DependsOn = @(
                            '[xDhcpServerScope]Scope',
                            '[xADDomainController]SecondDC'
                        )
        }

        xPendingReboot Reboot0
        {
            Name      = "RebootServer"
            DependsOn = '[xADDomainController]SecondDC'
        }
    }
}

@(
    'xDHCPServer',
    'xDNSServer',
    'xActiveDirectory',
    'xPendingReboot'
) |	ForEach-Object {Install-Module $_ -Force}

Set-Location 'Z:\Git\Repos\Powershell_DSC\ADComplete'

$cred = (Get-Credential Administrator)
$safe = (Get-Credential Administrator)
$user = (Get-Credential User@corp.contoso.com)
$domain = (Get-Credential Administrator@corp.contoso.com)

$config_params = @{
    ConfigurationData = '.\ConfigurationData.psd1';
    SafemodeAdministratorCred = $safe;
    DomainAdministratorCred = $domain;
    NewADUserCred = $user;
}
ADComplete @config_params

$start_dsc_params = @{
    Path = '.\ADComplete\';
    Credential = $cred;
    Wait = $true;
    Verbose = $true;
    Force = $true;
}
Start-DscConfiguration @start_dsc_params