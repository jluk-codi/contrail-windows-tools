. $PSScriptRoot\InitializeCIScript.ps1

# Sourcing VM management functions
. $PSScriptRoot\VMUtils.ps1

# Setting all variables needed for New-TestbedVMs from Environment
. $PSScriptRoot\SetCommonVariablesForNewVMsFromEnv.ps1

$VMNames = $Env:VM_NAMES.Split(",")
for ($i = 0; $i -lt $VMNames.Count; $i++) {
    $VMNames[$i] = Get-SanitizedOrGeneratedVMName -VMName $VMNames[$i] -RandomNamePrefix "Test-"
}

Write-Output "Starting Testbeds:"
$VMNames.ForEach({ Write-Output $_ })

$Sessions = New-TestbedVMs -VMNames $VMNames -InstallArtifacts $true -PowerCLIScriptPath $PowerCLIScriptPath `
    -VIServerAccessData $VIServerAccessData -VMCreationSettings $VMCreationSettings -VMCredentials $VMCredentials `
    -ArtifactsDir $ArtifactsDir -DumpFilesLocation $DumpFilesLocation -DumpFilesBaseName $DumpFilesBaseName -MaxWaitVMMinutes $MaxWaitVMMinutes

Write-Output "Started Testbeds:"
$Sessions.ForEach({ Write-Output $_.ComputerName })
