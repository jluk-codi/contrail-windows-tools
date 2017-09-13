function Test-ExtensionLongLeak {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [int] $TestDurationHours,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

    if ($TestDurationHours -eq 0) {
        Write-Output "===> Extension leak test skipped."
        return
    }

    Write-Output "===> Running Extension leak test. Duration: ${TestDurationHours}h..."

    Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    $TestStartTime = Get-Date
    $TestEndTime = ($TestStartTime).AddHours($TestDurationHours)

    Write-Output "It's $TestStartTime. Going to sleep until $TestEndTime."

    $CurrentTime = $TestStartTime
    while ($CurrentTime -lt $TestEndTime) {
        Start-Sleep -s (60 * 10) # 10 minutes
        $CurrentTime = Get-Date
        Write-Output "It's $CurrentTime. Sleeping..."
    }

    Write-Output "Waking up!"

    Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    Write-Output "===> Success!"
}
