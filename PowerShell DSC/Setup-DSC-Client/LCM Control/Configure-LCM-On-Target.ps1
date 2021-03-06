Configuration SetPullMode
 {
 param([string]$guid)
 Node $TargetNodeName
 {
 LocalConfigurationManager
 {
 ConfigurationMode = 'ApplyOnly'
ConfigurationID = $guid
 RefreshMode = 'Pull'
DownloadManagerName = ‘WebDownloadManager’
DownloadManagerCustomData = @{
 ServerUrl = $DSCServerURL;
         AllowUnsecureConnection = 'true' }
 }
 }
 }



# Generate the MOF File into the $ouptutdir
$OutputDir = "C:\temp";
$Guid= [guid]::NewGuid() 
$DSCServerURL = 'http://gig01srvdscman1:8080/PSDSCPullServer.svc'
$TargetNodeName = "gig01srvsqlhyt1"
$source = $OutputDir + '\' + $TargetNodeName +'.mof' 
$target= "C:\program files\windowspowershell\dscservice\configuration\$Guid.mof"


# Generate the MOF file for the ISS install
#nwisWebsite –MachineName $TargetNodeName -OutputPath $OutputDir;

# Copy over the .MOF file to the DSC Configuration Directory
copy $source $target

# Now generate the MOF File checksum
New-DSCChecksum $target

# Generate the MOF file for the LCM configuration
SetPullMode –guid $guid -OutputPath $OutputDir

# Push down the LCM configuration to the target node
Set-DSCLocalConfigurationManager –Computer $TargetNodeName -Path $OutputDir –Verbose
