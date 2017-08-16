function Test-MultiEnableDisableExtension {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [int] $EnableDisableCount,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

    Write-Host "===> Running Multi Enable-Disable Extension Test ($EnableDisableCount times)..."

    foreach ($I in 1..$EnableDisableCount) {
        Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
        Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
    }

    Write-Host "===> Success!"
}
