function Test-ICMPoMPLSoGRE {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session1,
           [Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session2,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

    Write-Host "===> Running ICMP over MPLS over GRE test"

    Initialize-TestConfiguration -Session $Session1 -TestConfiguration $TestConfiguration
    Initialize-TestConfiguration -Session $Session2 -TestConfiguration $TestConfiguration

    Write-Host "Running containers"
    $NetworkName = $TestConfiguration.DockerDriverConfiguration.NetworkConfiguration.NetworkName
    $Container1ID = Invoke-Command -Session $Session1 -ScriptBlock { docker run --network $Using:NetworkName -d microsoft/nanoserver ping -t localhost }
    $Container2ID = Invoke-Command -Session $Session2 -ScriptBlock { docker run --network $Using:NetworkName -d microsoft/nanoserver ping -t localhost }

    . $PSScriptRoot\CommonTestCode.ps1

    $Container1IP, $Container2IP = Initialize-MPLSoGRE -Session1 $Session1 -Session2 $Session2 `
        -Container1ID $Container1ID -Container2ID $Container2ID -AdapterName $TestConfiguration.AdapterName

    Write-Host "Testing ping"
    $Res1 = Invoke-Command -Session $Session1 -ScriptBlock {
        docker exec $Using:Container1ID powershell "ping $Using:Container2IP > null 2>&1; `$LASTEXITCODE;"
    }
    $Res2 = Invoke-Command -Session $Session2 -ScriptBlock {
        docker exec $Using:Container2ID powershell "ping $Using:Container1IP > null 2>&1; `$LASTEXITCODE;"
    }

    Write-Host "Removing containers"
    Invoke-Command -Session $Session1 -ScriptBlock { docker rm -f $Using:Container1ID } | Out-Null
    Invoke-Command -Session $Session2 -ScriptBlock { docker rm -f $Using:Container2ID } | Out-Null

    if (($Res1 -ne 0) -or ($Res2 -ne 0)) {
        throw "===> Multi-host ping test failed!"
    }

    Clear-TestConfiguration -Session $Session1 -TestConfiguration $TestConfiguration
    Clear-TestConfiguration -Session $Session2 -TestConfiguration $TestConfiguration

    Write-Host "===> Success"
}
