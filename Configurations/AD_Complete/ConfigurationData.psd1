@{
    AllNodes = @(
        @{
            NodeName         = 'DC-1'
            Role             = 'Primary DC'
            DHCPScopeName    = 'First_Scope'
            DHCPStartRange = '172.16.1.101'
            DHCPEndRange = '172.16.1.150'
            PsDscAllowPlainTextPassword = $true
            #CertificateFile  = 'C:\publicKeys\targetNode.cer'
            #Thumbprint       = 'AC23EA3A9E291A75757A556D0B71CBBF8C4F6FD8'
        },
        @{
            NodeName         = 'DC-2'
            Role             = 'Replica DC'
            DHCPScopeName    = 'Second_Scope'
            DHCPStartRange = '172.16.1.151'
            DHCPEndRange = '172.16.1.200'
            PsDscAllowPlainTextPassword = $true
            #CertificateFile  = 'C:\publicKeys\targetNode.cer'
            #Thumbprint       = 'AC23EA3A9E291A75757A556D0B71CBBF8C4F6FD8'
        }
    )

    ADConfig = @{
        DomainName       = 'corp.contoso.com'
        FFL              = 'WinThreshold'
        RetryCount       = 20
        RetryIntervalSec = 30
    }

    DNSConfig = @{
        Name = '1.16.172.in-addr.arpa'
        ReplicationScope = 'Forest'
        DynamicUpdate = 'Secure'
    }

    DHCPConfig = @{
        ScopeID = '172.16.1.0'
        SubnetMask = '255.255.255.0'
        Router = '172.16.1.1'
        DnsDomain = 'corp.contoso.com'
        DnsServerIPAddress = @("172.16.1.11",
                               "172.16.1.12")
        LeaseDuration = '12:00:00'
        State = 'Active'
        AddressFamily = 'IPv4'
    }
}