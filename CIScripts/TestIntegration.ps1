. $PSScriptRoot\InitializeCIScript.ps1

# Sourcing VM management functions
. $PSScriptRoot\VMUtils.ps1

# Setting all variables needed for New-TestbedVMs from Environment
. $PSScriptRoot\SetCommonVariablesForNewVMsFromEnv.ps1

# There are always 2 VMs created for running all tests
$VMsNeeded = 2

$VMBaseName = Get-SanitizedOrGeneratedVMName -VMName $Env:VM_NAME -RandomNamePrefix "Core-"
$VMNames = [System.Collections.ArrayList] @()
for ($i = 0; $i -lt $VMsNeeded; $i++) {
    $VMNames += $VMBaseName + "-" + $i.ToString()
}

Write-Host "Starting Testbeds:"
$VMNames.ForEach({ Write-Host $_ })

$Sessions = New-TestbedVMs -VMNames $VMNames -InstallArtifacts $true -PowerCLIScriptPath $PowerCLIScriptPath `
    -VIServerAccessData $VIServerAccessData -VMCreationSettings $VMCreationSettings -VMCredentials $VMCredentials `
    -ArtifactsDir $ArtifactsDir -DumpFilesLocation $DumpFilesLocation -DumpFilesBaseName $DumpFilesBaseName -MaxWaitVMMinutes $MaxWaitVMMinutes

Write-Host "Started Testbeds:"
$Sessions.ForEach({ Write-Host $_.ComputerName })

# Sourcing test functions
. $PSScriptRoot\Tests\Tests.ps1

$DockerNetworkConfiguration = [DockerNetworkConfiguration] @{
    TenantName = $Env:DOCKER_NETWORK_TENANT_NAME;
    NetworkName = $Env:DOCKER_NETWORK_NAME;
}

$DockerDriverConfiguration = [DockerDriverConfiguration] @{
    Username = $Env:DOCKER_DRIVER_USERNAME;
    Password = $Env:DOCKER_DRIVER_PASSWORD;
    AuthUrl = $Env:DOCKER_DRIVER_AUTH_URL;
    ControllerIP = $Env:DOCKER_DRIVER_CONTROLLER_IP;
    NetworkConfiguration = $DockerNetworkConfiguration;
}

$TestConfiguration = [TestConfiguration] @{
    AdapterName = $Env:ADAPTER_NAME;
    VMSwitchName = "Layered " + $Env:ADAPTER_NAME;
    ForwardingExtensionName = $Env:FORWARDING_EXTENSION_NAME;
    DockerDriverConfiguration = $DockerDriverConfiguration;
}

# TODO: JW-838: Add parameters after tests implementation
Test-ExtensionLongLeak -Session $Sessions[0] -TestDurationHours $Env:LEAK_TEST_DURATION -TestConfiguration $TestConfiguration
Test-MultiEnableDisableExtension -Session $Sessions[0] -EnableDisableCount $Env:MULTI_ENABLE_DISABLE_EXTENSION_COUNT -TestConfiguration $TestConfiguration
Test-VTestScenarios -Session $Sessions[0] -TestConfiguration $TestConfiguration
Test-TCPCommunication
Test-ICMPoMPLSoGRE -Session1 $Sessions[0] -Session2 $Sessions[1] -TestConfiguration $TestConfiguration
Test-TCPOverMPLSOverGRE
Test-SNAT
Test-DockerDriver -Session $Sessions[0] -TestConfiguration $TestConfiguration

Write-Host "Removing VMs..."
Remove-TestbedVMs -VMNames $VMNames -PowerCLIScriptPath $PowerCLIScriptPath -VIServerAccessData $VIServerAccessData
