function Test-ExtensionLongLeak {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [int] $TestDurationHours,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

    if ($TestDurationHours -eq 0) {
        Write-Host "Extension leak test skipped."
        return
    }

    Write-Host "Running Extension leak test. Duration: ${TestDurationHours}h..."

    Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    $TestStartTime = Get-Date
    $TestEndTime = ($TestStartTime).AddHours($TestDurationHours)

    Write-Host "It's $TestStartTime. Going to sleep until $TestEndTime."

    $CurrentTime = $TestStartTime
    while ($CurrentTime -lt $TestEndTime) {
        Start-Sleep -s (60 * 10) # 10 minutes
        $CurrentTime = Get-Date
        Write-Host "It's $CurrentTime. Sleeping..."
    }

    Write-Host "Waking up!"

    Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    Write-Host "Success!"
}
