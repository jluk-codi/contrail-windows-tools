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

# TODO: JW-838: Add parameters after tests implementation
Test-ExtensionLongLeak
Test-MultiEnableDisableExtension
Test-VTestScenarios
Test-TCPCommunication
Test-ICMPOverMPLSOverGRE
Test-TCPOverMPLSOverGRE
Test-SNAT
Test-DockerDriver

Write-Host "Removing VMs..."
Remove-TestbedVMs -VMNames $VMNames -PowerCLIScriptPath $PowerCLIScriptPath -VIServerAccessData $VIServerAccessData
