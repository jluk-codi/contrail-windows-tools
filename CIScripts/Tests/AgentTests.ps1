function Run-Test {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [string] $TestExecutable)
    Write-Host -NoNewline "===> Agent tests: running $TestExecutable... "
    $Res = Invoke-Command -Session $Session -ScriptBlock {
        & C:\Artifacts\$using:TestExecutable
        $LASTEXITCODE
    }
    if ($Res -eq 0) {
        Write-Host "Succeeded."
    } else {
        Write-Host "Failed (exit code: $Res)."
    }
    return $Res
}

function Test-Agent {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)
    Write-Host "===> Agent tests: setting up an environment."
    Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    $Res = 0
    $AgentTextExecutables = Get-ChildItem .\output\agent | Where-Object {$_.Name -match '^[\W\w]*test[\W\w]*.exe$'}
    Foreach ($TestExecutable in $AgentTextExecutables) {
        $TestRes = Run-Test -Session $Session -TestExecutable $TestExecutable
        if ($TestRes -ne 0) {
            $Res = 1
        }
    }

    Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration | Out-Null
    Write-Host "===> Agent tests: environment has been cleaned up."
    if ($Res -eq 0) {
        Write-Host "===> Agent tests: all tests succeeded."
    } else {
        Write-Host "===> Agent tests: some tests failed."
    }

    return $Res
}
