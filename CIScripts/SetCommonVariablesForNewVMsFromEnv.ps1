$PowerCLIScriptPath = $Env:POWER_CLI_SCRIPT_PATH
$MaxWaitVMMinutes = $Env:MAX_WAIT_VM_MINUTES

$VIServerAccessData = [VIServerAccessData] @{
    Username = $Env:VISERVER_USERNAME;
    Password = $Env:VISERVER_PASSWORD;
    Server = $Env:VISERVER_ADDRESS;
}

$VMCreationSettings = [NewVMCreationSettings] @{
    ResourcePoolName = $Env:CI_RESOURCE_POOL_NAME;
    TemplateName = $Env:CI_TEMPLATE_NAME;
    CustomizationSpecName = $Env:CI_CUSTOMIZATION_SPEC_NAME;
    DatastoresList = $Env:CI_DATASTORES.Split(",");
    NewVMLocation = $Env:CI_VM_LOCATION;
}

$VMUsername = $Env:VM_USERNAME
$VMPassword = $Env:VM_PASSWORD | ConvertTo-SecureString -AsPlainText -Force
$VMCredentials = New-Object System.Management.Automation.PSCredential($VMUsername, $VMPassword)

$ArtifactsDir = $Env:ARTIFACTS_DIR
$DumpFilesLocation = $Env:DUMP_FILES_LOCATION
$DumpFilesBaseName = ($Env:JOB_BASE_NAME + "_" + $Env:BUILD_NUMBER)
