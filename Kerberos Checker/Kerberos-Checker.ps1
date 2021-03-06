<#

.SYNOPSIS
The script serves as the top shell for processing Infrastructure builds using PowerShell DSC

.DESCRIPTION
The script attempts to determine what the KERBEROS Configuration for a solution should be,
and check to ensure those configuration values are set accordingly.

.PARAMETER ServerName
    The ServerName (Server\Instance) we wish to check Kerberos Cofiguration of. This can be:
    1) The Hostname (for a Default SQL Instance)
    2) The Hostname\InstanceName in the case of a named instance. 
    3) The ServerName (<Hostname>\<InstanceName>) 

.PARAMETER FixIT
    The FixIT flag is to attempt to repair any Kerberos related issue which are found

.EXAMPLE
 Invocation:                                                                                                 
     cd <appropriate path>                                                                                   
     .\Kerberos-Checker.ps1 -ServerName '<hostname>\<instancename>' -AGName <Availability Group> -FixIT 'Y|y|N|n|1|0';
     
     cd "D:\Microsoft\Development\Kerberos Checker"
     .\Kerberos-Checker.ps1 -ServerName '2014_AG_CAP' -AGName "ABCorp_AG_2014" -FixIT 'N'
     .\Kerberos-Checker.ps1 -ServerName 'SQLNode1' -AGName "ABCorp_AG_2014" -FixIT 'N'
     .\Kerberos-Checker.ps1 -ServerName 'SQLNode3' -AGName "ABCorp_AG_2014" -FixIT 'N'
     .\Kerberos-Checker.ps1 -ServerName 'SQLNode5' -AGName "ABCorp_AG_2014" -FixIT 'N'
     .\Kerberos-Checker.ps1 -ServerName 'SQLFCI' -FixIT 'N'
     .\Kerberos-Checker.ps1 -ServerName 'DSCMaster' -FixIT 'Y'

.NOTES

 Author: Dr David Thulborn
 Company: Microsoft

 Version History:																				              
																								              
     Version 1.0   -   Initial Write of Script as a proof of concept in Powershell 				              

.LINK
 none

#>

param (
    [Parameter(Mandatory=$true)][string]$ServerName,
    [Parameter(Mandatory=$false)][string]$AGName,
    [Parameter(Mandatory=$true)][ValidateSet('Y', 'y', 'N', 'n', 1, 0, $true, $false)][string]$FixIT
    )

Clear;

Set-StrictMode -Version 1.0
$ScriptVersion = "1.0";


( $HostName, $InstanceName ) = $ServerName.split('\');

if ( $Hostname -ne $null ) { $HostName = ( $Hostname ).Trim(); };
if ( $InstanceName -ne $null ) { $InstanceName = ( $InstanceName ).Trim(); };

Switch ($FixIT) 
    {
        { $_ -in "y", "Y", 1 } 
            {
                $FixIT = $true;
            }
        { $_ -in "n", "N", 0 }
            {
                $FixIT = $false;
            }
    }


###############################################################################################################
#                                                                                                             #
#  Load in the Various Functions and Modules we will need                                                     #
#                                                                                                             #
###############################################################################################################

# Load the DSC Helper Functions
. "$PSScriptRoot\Kerberos-Helper-Functions.ps1";
Write-Host "Helper Functions Loaded." -ForegroundColor Green;

# Load the Required Modules
Load-PSModule -ModuleName ActiveDirectory;
Load-PSModule -ModuleName FailoverClusters;
Load-PSModule -ModuleName SQLPS;

$DomainAdminCred   = Get-Credential -UserName "ABCorp\Administrator" -Message "Enter the Domain Admin Account Details";
Write-Host "Credential Collecteds." -ForegroundColor Green; 


# Initialize the SPN arrays for the Solution
[System.Collections.ArrayList]$ExistingSPNs = @();
[System.Collections.ArrayList]$ListenerSPNs = @();
[System.Collections.ArrayList]$RequiredSPNs = @();
[System.Collections.ArrayList]$NodeAccounts = @();


# Connect to the Instance which has been specified.
# This could be a Stand-Alone instance, a Clsuter or an Availability Group Node.
( $SQLEnvDS )  = Get-SQLEnvironment -ServerName $ServerName;
$is_clustered = ( $SQLEnvDS.Tables.Clustered ).Trim();
$is_HADR      = ( $SQLEnvDS.Tables.HADR ).Trim();


if ( $is_HADR -eq "0" )
    {
        # Stand-Alone or Clustered Machine
        [System.Collections.ArrayList]$NodeSPNs = @();
        ( $SQLServDS )  = Get-SQLServiceInfo -ServerName $ServerName;
        $TCPPort        = ( $SQLServDS.Tables.PortNumber ).Trim();
        ( $Domain, $ServiceAccount ) = ( $SQLServDS.Tables.ServiceAccount ).split('\').Trim();

        ( $NodeSPNs ) = Get-NodeSPNs -ServerName $ServerName -TCPPort $TCPPort;
        for ( $index = 0; $index -lt ( $NodeSPNs.Count ); $index++ )
            {
                if ( $NodeSPNs.Item($index) -match "MSSQLSvc" )
                    {
                        $RequiredSPNs.Add($NodeSPNs[$index]) | Out-Null;
                    }
            }
    }
else
    {
        # This is an Availability Group
        # So now we need to find the other nodes within the AG
        # and loop through them to find the rest of the SPN details
        ( $SQLEnvDS )  = Get-SQLAGEnvironment -ServerName $ServerName -AGName $AGName;
        if ( $SQLEnvDS.tables.rows.count -eq 0 )
            {
                Write-Host "No Data Returned for this AG on this Node??." -ForegroundColor Red;
                exit(0);
            }

        foreach ( $Node in $SQLEnvDS.Tables | where { $_.Role -eq "node" } )
            {
                # Loop through the AG Nodes, building the SPNs
                [System.Collections.ArrayList]$NodeSPNs = @();
                $ServerName = $Node.Name;
                ( $SQLServDS )  = Get-SQLServiceInfo -ServerName $ServerName;
                $TCPPort        = ( $SQLServDS.Tables.PortNumber ).Trim();

                if ( $SQLServDS.Tables.ServiceAccount -match "\\" )
                    {
                        ( $Domain, $ServiceAccount ) = ( $SQLServDS.Tables.ServiceAccount ).split('\').Trim();
                    }
                elseif ( $SQLServDS.Tables.ServiceAccount -match "@" )
                    {
                        ( $ServiceAccount, $Domain ) = ( $SQLServDS.Tables.ServiceAccount ).split('@').Trim();
                        $ServiceAccount = $ServiceAccount.Substring(0, 20); # The SAM can only be a max of 20 characters long
                    }

                $NodeAccounts.Add($ServiceAccount) | Out-NUll;                

                ( $NodeSPNs ) = Get-NodeSPNs -ServerName $ServerName -TCPPort $TCPPort;
                for ( $index = 0; $index -lt ( $NodeSPNs.Count ); $index++ )
                    {
                        if ( $NodeSPNs.Item($index) -match "MSSQLSvc" )
                            {
                                $SPN = $NodeSPNs[$index];
                                $RequiredSPNs.Add($SPN) | Out-Null;
                            }
                    }
            }
        # Finally add in the listener SPN since this is an AG
        $Listener = ( $SQLEnvDS.Tables | where { $_.Role -eq "listener" } ).Name;
        ( $ListenerSPNs ) = Get-NodeSPNs -ServerName $Listener -TCPPort $TCPPort;
        for ( $index = 0; $index -lt ( $ListenerSPNs.Count ); $index++ )
            {
                if ( $ListenerSPNs.Item($index) -match "MSSQLSvc" )
                    {
                        $RequiredSPNs.Add($ListenerSPNs[$index]) | Out-Null;
                    }
            }

        $result = Check-ServiceAccountsAreTheSame -NodeAccounts $NodeAccounts;

        if ($result -eq $false )
            {
                Write-Host "The Service Accounts from the AG Nodes are not the same." -ForegroundColor Red;
                Write-Host "The Accounts ought to be identical for Kerberos to work" -ForegroundColor Red;
                Write-Host "Otherwise SPNs will need to be re-registered everytime there is a failover." -ForegroundColor Red;
                Write-Host "Please See: https://msdn.microsoft.com/en-us/library/ff878487(v=sql.110).aspx#PrerequisitesSI" -ForegroundColor Blue;
                exit(0);
            }

    }


# Get the SPNs for this Service Account from AD
$ExistingSPNs = Get-ExistingSPNs -ExistingSPNs $ExistingSPNs -Domain $Domain -ServiceAccount $ServiceAccount -Hostname $Hostname;

# Compare the SPNs required for the solution against the SPNs which are present in AD
$MissingSPNs = $RequiredSPNs |? { $ExistingSPNs -notcontains $_ };

# Highlight the missing SPNs (if any)
if ( $MissingSPNs.Count -ne 0 )
    {
        Write-Host "Account: $ServiceAccount is missing SPNs:" -ForegroundColor Red;
        Write-Host "";
        for ( $index = 0; $index -lt ( $MissingSPNs.Count ); $index++ )
            {
                $SPN = $MissingSPNs[$index];
                Write-Host "$SPN" -ForegroundColor Red;
            }
        Write-Host "";

        # If the FixIT Flag has been set to TRUE - add the SPNs which are missing
        if ( $FixIT -eq $true )
            {
                Write-Host "Adding Missing SPNs Automatically." -ForegroundColor Green;
                Add-MissingSPNs `
                    -MissingSPNs $MissingSPNs `
                    -Domain $Domain `
                    -ServiceAccount $ServiceAccount `
                    -Hostname $Hostname `
                    -DomainAdminCred $DomainAdminCred;
            }
        else
            {
                Write-Host "To add manually, use: SETSPN -s <SPN> $ServiceAccount" -ForegroundColor Red;
                Write-Host "To automatically add, re-run the statement with the FixIT flag set to 'Y|y|1|`$true'" -ForegroundColor Red;
            }
    }
else
    {
         if ( $Domain -eq "NT Service" )
             {
                 Write-Host "All SPNs for Machine Account: $Hostname`$ appear to be present." -ForegroundColor Green;
             }
        else
            {
                Write-Host "All SPNs for Service Account: $ServiceAccount appear to be present." -ForegroundColor Green;
            }
    }