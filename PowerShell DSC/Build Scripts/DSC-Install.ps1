<#

.SYNOPSIS
The script serves as the top shell for processing Infrastructure builds using PowerShell DSC

.DESCRIPTION
The script serves as the top shell for processing Infrastructure builds using PowerShell DSC. The DSCType Variable
directs the processing to the appropriate DSC Configuration Block.

.PARAMETER DSCType
    The type of Processing we wish the PowerShell DSC to undertake.
    C = Cluster Build using DSCBuildCluster.ps1
    A = Availability Group Build Using DSCBuildClusterAndAvailabilityGroup.ps1
    S = Stand-Alone SQL Build using DSCBuildSQLStandAlone.ps1

.PARAMETER DSCBuildFile
    The path to the .PS1 file containing the DSC Configuration Block we wish to use.

.PARAMETER DSCConfigurationData
    The path to the .PS1 file containing the DSC Configuration Data we wish to use.
    The Configuration Data will be merged into the Configuration Block and used to generate the MOF files
    which will guide the DSC LCM to build.

.EXAMPLE
 Invocation:                                                                                                 
     CD <appropriate path>                                                                                   
     .\DSC-Install.ps1 `                                                                                     
           -DSCType C | A | S (Cluster | Availability Group | Stand-Alone) `                                                                                                           
           -DSCConfigurationDataFile .\DSCConfigurationData\<config file>.psd1 `
           -DSCManagerHost '<Server Hosting the DSC Database>' `
           -DSCManagerInstanceName 'SQL Server Instance Hosting the DSC Database' `
           -DSCDatabase '<DSC Database NAme>' `
           -StoredProcParams '<ServerName to Build>'

    cd 'D:\DSC Scripts\Build Scripts'
    .\DSC-Install.ps1 -DSCType 'A' `
                      -DSCConfigurationDataFile .\DSCConfigurationData\DSCBuild-ClusterAndAvailabilityGroup__TESTING__Config.json `
                      -DSCManagerHost 'MININT-435D8DN' `
                      -DSCManagerInstanceName 'SQL2016INST1' `
                      -DSCDatabase 'DSC' `
                      -StoredProcParams 'GIG01SRVSQLT001'
    .\DSC-Install.ps1 -DSCType 'C' `
                      -DSCConfigurationDataFile .\DSCConfigurationData\DSCBuild-Cluster_Config.json `
                      -DSCManagerHost 'GIG01SRVDSCMAN1' `
                      -DSCManagerInstanceName 'DSCMAN' `
                      -DSCDatabase 'DSC' `
                      -StoredProcParams 'GIG01SRVSQLT008'
    .\DSC-Install.ps1 -DSCType 'S' `
                      -DSCConfigurationDataFile .\DSCConfigurationData\DSCBuild-SQLStandAlone__TESTING__Config.json `
                      -DSCManagerHost 'GIG01SRVDSCMAN1' `
                      -DSCManagerInstanceName 'DSCMAN' `
                      -DSCDatabase 'DSC' `
                      -StoredProcParams 'GIG01SRVSQLT004'


.NOTES

 Author: Dr David Thulborn
 Company: Microsoft

 Version History:																				              
																								              
     Version 1.0   -   Initial Write of Script as a proof of concept in Powershell 				              
     Version 1.1   -   Modularised code into the various sections									              
     Version 1.2   -   Introduced code to remotely install the required certificates                             
     Version 1.3   -   Introduced code to cope with blank SQLInstanceName(s) and offer default                   
     Version 1.4   -   Factorized code into Functions for future ease of reading                                 
     Version 1.5   -   Added Functions to Check the Cluster AD entries and correct as needed                     
     Version 1.6   -   Added Check for the Primary Node being able to host the cluster IP                        
     Version 1.7   -   Broke out the DSC Configuration Blocks to stand-alone files                               
     Version 1.8   -   Moved Solution over to using JSON Configuration Files for ease
     Version 1.9   -   Branch Retired
     Version 2.0   -   Add functionality to export JSON configuration file from SQL
     Version 2.1   -   Added Extra Credential collection for SSAS / SSRS and SSIS
     Version 2.2   -   Removed the Command Line Parameter calling the DSC Configuration File
                       Now we simply load all of the configuration Blocks
                       Fixed the Check-ADComputerAccountInTargetOU function
                       Fixed the Create-FileShareWitnessWithPermissions function
     Version 2.3   -   Current Version

.LINK
 none

#>

param (
    [Parameter(Mandatory=$true)][ValidateSet('C','A','S')][string]$DSCType,
    [Parameter(Mandatory=$true)][string]$DSCConfigurationDataFile,    
    [Parameter(Mandatory=$true)][string]$DSCManagerHost,
    [Parameter(Mandatory=$true)][string]$DSCManagerInstanceName,
    [Parameter(Mandatory=$true)][string]$DSCDatabase,
    [Parameter(Mandatory=$true)][string]$StoredProcParams
    )



Clear;
$DSCScriptVersion         = "2.3";
$OutputDir                = $env:TEMP;
$DSCHelperFunctionsFile   = Join-Path -Path $PSScriptRoot -ChildPath "DSC-Install-Helper-Functions.ps1";
$DSCLCMConfigBlockFile    = Join-Path -Path $PSScriptRoot -ChildPath "DSCBuildLibrary\DSCBuild-LCMConfiguration.ps1";
$DSCCluster               = Join-Path -Path $PSScriptRoot -ChildPath "DSCBuildLibrary\DSCBuild-Cluster.ps1";
$DSCStandAlone            = Join-Path -Path $PSScriptRoot -ChildPath "DSCBuildLibrary\DSCBuild-SQLStandAlone.ps1";
$DSCClusterAndAG          = Join-Path -Path $PSScriptRoot -ChildPath "DSCBuildLibrary\DSCBuild-ClusterAndAvailabilityGroup.ps1";


# Make sure we dont have any .MOF file or .meta.MOF files from previous runs
Get-ChildItem $OutputDir -Filter *.MOF | Foreach-Object { $file = $OutputDir + '\' + $_; Remove-Item $file; }


###############################################################################################################
#                                                                                                             #
#  Load in the Various Functions, Modules and Configurations we will need                                     #
#                                                                                                             #
###############################################################################################################

# Load the DSC Helper Functions
. $DSCHelperFunctionsFile;
Write-Host "DSC Helper Functions Loaded." -ForegroundColor Green;

# Load the DSC LCM Manager Configuration Block
. $DSCLCMConfigBlockFile;
Write-Host "DSC LCM Configuration Block Sucessfully Loaded." -ForegroundColor Green;

# Load the DSC Build Library Files
. $DSCCluster;
. $DSCStandAlone;
. $DSCClusterAndAG;
Write-Host "DSC Build Library Files Sucessfully Loaded." -ForegroundColor Green;

# Load the Required Modules
Load-PSModule -ModuleName ActiveDirectory;
Load-PSModule -ModuleName FailoverClusters;
Load-PSModule -ModuleName SQLPS;


#Extract the configuration data from SQL Server to JSON file
Export-DSCConfigurationToJSON -DSCManagerHost $DSCManagerHost `
                              -DSCManagerInstanceName $DSCManagerInstanceName `
                              -DSCDatabase $DSCDatabase `
                              -StoredProcParams $StoredProcParams `
                              -DSCConfigurationDataFile $DSCConfigurationDataFile;

# Import the DSC Configuration File
( $DSCConfigurationData ) = Import-DSCConfigurationFromJSON -DSCConfigurationDataFile $DSCConfigurationDataFile;

$DSCConfigurationDataFile = "$PSScriptRoot" + $DSCConfigurationDataFile.TrimStart(".");
           
# Get the DSC Configuration Data from the Data File
$DSCPullServerURL         = $DSCConfigurationData.AllNodes.DSCPullServerURL;
$DSCComplianceServerURL   = $DSCConfigurationData.AllNodes.DSCComplianceServerURL;
$DSCConfigurationFileDir  = $DSCConfigurationData.AllNodes.DSCConfigurationFileDir;
$DSCImageSource           = $DSCConfigurationData.AllNodes.DSCImageSource;


# Get the SQL Server Configuration Data from the Data File
$SQLVersion               = $DSCConfigurationData.AllNodes.SQL_Version;
$SQLInstanceName          = $DSCConfigurationData.AllNodes.SQL_InstanceName;
$SQLInstallDataDir        = $DSCConfigurationData.AllNodes.SQL_InstallDataDir
$SQLInstallSource         = Join-Path -Path $DSCImageSource -ChildPath $SQLVersion;
$SQLFeatureList           = $DSCConfigurationData.AllNodes.SQL_FeatureList;

# Get the Certificate location from the Data File, Import it and extract the Thumbprint
$CertificateFile          = $DSCConfigurationData.AllNodes.CertificateFile;
$PFXFile                  = $DSCConfigurationData.AllNodes.PFXFile;
$PFXPassword              = $DSCConfigurationData.AllNodes.PFXPassword;
$CertObject               = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2;
$CertObject.Import($CertificateFile);
$Thumbprint               = $CertObject.Thumbprint;

$ClusterName              = $DSCConfigurationData.AllNodes.Cluster_Name;
$Cluster_IPAddress1       = $DSCConfigurationData.AllNodes.Cluster_IPAddress1;
$Cluster_FSW_Base         = $DSCConfigurationData.AllNodes.Cluster_FSW_Base;
$TargetOU                 = $DSCConfigurationData.AllNodes.TargetOU;

$PrimaryNode              = ( $DSCConfigurationData.AllNodes | where-Object { $_.Role -eq "PrimaryNode" }).NodeName;
Write-Host "DSC Build Configuration Data Loaded." -ForegroundColor Green;

# Get the various credentials for the build
( $DomainAdminBuildCred, $DomainBuildCred, $sqlServiceCred, $sqlAgentCred, $SACred, $SSASCred, $SSRSCred, $SSISCred ) `
     = Get-BuildCredentials -SQLFeatureList $SQLFeatureList;
Write-Host "Credentials Collected." -ForegroundColor Green;

Write-Host "Collection of Prerequisites completed." -ForegroundColor Green;


###############################################################################################################
#                                                                                                             #
#  Check the Pre-requisites to ensure the PowerShell DSC script will complete                                 #
#  then Build the MOF files using PowerShell DSC                                                              #
#                                                                                                             #
###############################################################################################################

Write-Host "";
Write-Host "###############################################################################################################" -ForegroundColor Green;
Write-Host "#                                                                                                             #" -ForegroundColor Green;
Write-Host "#    Starting to Process the DSC Build...using DSC SCript Version $DSCScriptVersion                                         #" -ForegroundColor Green;
Write-Host "#                                                                                                             #" -ForegroundColor Green;
Write-Host "###############################################################################################################" -ForegroundColor Green;

# Generate the the NODE MOF Files for the Build 
# this is the call to DSC to generate MOF files
Switch ($DSCType) 
    {
        'A' #AvailabilityGroup
            {
                Check-ADAccountExists `
                    -AccountCredential $sqlServiceCred;
                Check-ADAccountExists `
                    -AccountCredential $sqlAgentCred;

                # Determine the Path for the SQL Server Executable to be inserted into the FireWall
                ( $SQLProgram ) = Get-FireWallPath `
                                    -SQLVersion $SQLVersion `
                                    -SQLInstallDataDir $SQLInstallDataDir `
                                    -SQLInstanceName $SQLInstanceName;
                
                # Create the FileShare for the Cluster, and assign the appropriate permissions
                Create-FileShareWitnessWithPermissions `
                    -ClusterName $ClusterName `
                    -Cluster_FSW_Base $Cluster_FSW_Base;

                # Make sure the Cluster CNO exists, and is DISABLED
                Check-ADClusterCNOExists `
                    -ClusterName $ClusterName;

                # Make sure the Computer Account is in the correct OU
                Check-ADComputerAccountInTargetOU `
                    -TargetNodeName $ClusterName `
                    -TargetOU $TargetOU `
                    -DomainAdminBuildCred $DomainAdminBuildCred;
                
                # Make sure the correct IP Address for the cluster has been specified
                Check-ClusterIPAddress `
                    -PrimaryNode $PrimaryNode `
                    -Cluster_IPAddress $Cluster_IPAddress1;

                
                # Call the DSC Module to Build the MOF files
                BuildClusterAndSQLAvailabilityGroup `
                    -ConfigurationData $DSCConfigurationData `
                    -OutputPath $OutputDir;
            }
        'C' #Cluster
            {
                # Create the FileShare for the Cluster, and assign the appropriate permissions
                Create-FileShareWitnessWithPermissions `
                    -ClusterName $ClusterName `
                    -Cluster_FSW_Base $Cluster_FSW_Base;

                # Make sure the Cluster CNO exists, and is DISABLED
                Check-ADClusterCNOExists `
                    -ClusterName $ClusterName;

                # Make sure the Computer Account is in the correct OU
                Check-ADComputerAccountInTargetOU `
                    -TargetNodeName $ClusterName `
                    -TargetOU $TargetOU `
                    -DomainAdminBuildCred $DomainAdminBuildCred;

                # Make sure the correct IP Address for the cluster has been specified
                Check-ClusterIPAddress `
                    -PrimaryNode $PrimaryNode `
                    -ClusterIPAddress1 $Cluster_IPAddress1;

                # Call the DSC Module to Build the MOF files
                BuildCluster -ConfigurationData $DSCConfigurationData -OutputPath $OutputDir;
            }
        'S' #Stand-Alone
            {
                Check-ADAccountExists `
                    -AccountCredential $sqlServiceCred;
                Check-ADAccountExists `
                    -AccountCredential $sqlAgentCred;

                # Determine the Path for the SQL Server Executable to be inserted into the FireWall
                ( $SQLProgram ) = Get-FireWallPath `
                                    -SQLVersion $SQLVersion `
                                    -SQLInstallDataDir $SQLInstallDataDir `
                                    -SQLInstanceName $SQLInstanceName;

                # Make sure the Computer Account is in the correct OU
                Check-ADComputerAccountInTargetOU `
                    -TargetNodeName $PrimaryNode `
                    -TargetOU $TargetOU `
                    -DomainAdminBuildCred $DomainAdminBuildCred;

                # Call the DSC Module to Build the MOF files
                BuildSQLServer `
                    -ConfigurationData $DSCConfigurationData `
                    -OutputPath $OutputDir;
            }
    }


###############################################################################################################
#                                                                                                             #
#  Process the MOF files which have just been generated and push them to the Target nodes                     #
#                                                                                                             #
###############################################################################################################
write-host "Mof File generation complete.  Loop over all MOF files and move out to nodes"

# Loop Over all MOF files which have been created
Get-ChildItem $OutputDir -Filter *.MOF | Foreach-Object {
	$TargetNodeName          = [IO.Path]::GetFileNameWithoutExtension($_);
    $Guid                    = [guid]::NewGuid();
	$source                  = $OutputDir + '\' + $_;
	$target                  = $DSCConfigurationFileDir + $Guid + '.mof';

	# Copy over the .MOF file to the DSC Configuration Directory
	Move-Item $source $target -Force
	
	# Now generate the MOF File checksum
	New-DSCChecksum $target -Force
	
    
    # Remotely Install Certificate on Target Node if required
    [Bool]$CertificateAlreadyPresent = $false;

    $CertificateAlreadyPresent = Check-CertificateAlreadyInstalled -TargetNodeName $TargetNodeName -Thumbprint $Thumbprint;
    
    If ( $CertificateAlreadyPresent -eq $False ) # If it is not present, Install it
        {
            Install-RemoteCertificate `
            -TargetNodeName $TargetNodeName `
            -CertFile $CertificateFile `
            -PFXFile $PFXFile `
            -PFXPassword $PFXPassword `
            -DomainBuildCred $DomainBuildCred;
        }

	# Generate the MOF file for the LCM configuration
	# These MOF Files reference the GUIDs for the actual MOFs
	# with the required configuration in them
	SetPullMode `
        –guid $Guid `
        -TargetNodeName $TargetNodeName `
        -DSCPullServerURL $DSCPullServerURL `
        -DSCComplianceServerURL $DSCComplianceServerURL `
        -Thumbprint $Thumbprint `
        -OutputPath $OutputDir;

	# Push down the LCM configuration to the target node
	Set-DSCLocalConfigurationManager `
        –Computer $TargetNodeName `
        -Path $OutputDir `
        –Verbose -Force;

	}


###############################################################################################################
#                                                                                                             #
#  Backup the Configuration File used to drive the DSC build                                                  #
#                                                                                                             #
###############################################################################################################

# Backup the Configuration File now the build has actually started.
Write-Host "Backing Up the Configuration File." -ForegroundColor Green;
BackupConfigurationFile -ConfigurationDataFile $DSCConfigurationDataFile;


Write-Host "Script Completed - DSC Build in Progress...." -ForegroundColor Green;
Write-Host "Please Check the Targets for Build Progress...." -ForegroundColor Green;
