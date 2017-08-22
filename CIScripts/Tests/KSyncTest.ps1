function Test-KSync {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)
    Write-Host "===> KSync tests: setting up an environment."
    Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    Write-Host -NoNewline "===> KSync tests: running ksync_test.exe... "
    $KSync_Test_1 = Invoke-Command -Session $Session -ScriptBlock {
        & C:\Artifacts\ksync_test.exe
        $LASTEXITCODE
    }
    if ($KSync_Test_1 -eq 0) {
        Write-Host "Succeeded."
    } else {
        Write-Host "Failed."
    }

    Write-Host -NoNewline "===> KSync tests: running test_ksync.exe... "
    $KSync_Test_2 = Invoke-Command -Session $Session -ScriptBlock {
        & C:\Artifacts\test_ksync.exe
        $LASTEXITCODE
    }
    if ($KSync_Test_2 -eq 0) {
        Write-Host "Succeeded."
    } else {
        Write-Host "Failed."
    }
    
    Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration | Out-Null
    Write-Host "===> KSync tests: environment has been cleaned up."

    return $(if ($KSync_Test_1 -eq 0 -and $KSync_Test_2 -eq 0) { 0 } else { 1 })
}
