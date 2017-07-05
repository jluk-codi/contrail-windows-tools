if ($Env:ENABLE_TRACE -eq $true) {
    Set-PSDebug -Trace 1
}

# Refresh Path and PSModulePath
$Env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")
$Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

# Stop script on error
$ErrorActionPreference = "Stop"

# Sourcing New-TestbedVMs function
. $PSScriptRoot\SpawnVM.ps1

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

$VMNames = $Env:VM_NAMES.Split(",")
for ($i = 0; $i -lt $VMNames.Count; $i++) {
    # Replace all empty or "Auto" names to random generated names
    if (($VMNames[$i] -eq "Auto") -or ($VMNames[$i].Length -eq 0)) {
        $VMNames[$i] = "Test-" + [string]([guid]::NewGuid().Guid).Replace("-", "").ToUpper().Substring(0, 6)
    }
}

Write-Host "Starting Testbeds:"
$VMNames.ForEach({ Write-Host $_ })

$Sessions = New-TestbedVMs -VMNames $VMNames -InstallArtifacts $true -PowerCLIScriptPath $PowerCLIScriptPath `
    -VIServerAccessData $VIServerAccessData -VMCreationSettings $VMCreationSettings -VMCredentials $VMCredentials `
    -ArtifactsDir $ArtifactsDir -DumpFilesLocation $DumpFilesLocation -DumpFilesBaseName $DumpFilesBaseName -MaxWaitVMMinutes $MaxWaitVMMinutes

Write-Host "Started Testbeds:"
$Sessions.ForEach({ Write-Host $_.ComputerName })
