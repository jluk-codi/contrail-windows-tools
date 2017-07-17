function Test-VTestScenarios {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

    Write-Host "Running vtest scenarios"

    Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    $VMSwitchName = $TestConfiguration.VMSwitchName
    $Res = Invoke-Command -Session $Session -ScriptBlock {
        Push-Location C:\Artifacts\

        vtest\all_tests_run.ps1 -VMSwitchName $Using:VMSwitchName -TestsFolder vtest\tests | Write-Host
        $Res = $LASTEXITCODE

        Pop-Location
        return $Res
    }

    if ($Res -ne 0) {
        throw "VTest scenarios test failed!"
    }

    Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    Write-Host "Success!"
}
