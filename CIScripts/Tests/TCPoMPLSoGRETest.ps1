function Test-TCPoMPLSoGRE {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session1,
           [Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session2,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

    Write-Host "===> Running TCP over MPLS over GRE test"

    Initialize-TestConfiguration -Session $Session1 -TestConfiguration $TestConfiguration
    Initialize-TestConfiguration -Session $Session2 -TestConfiguration $TestConfiguration

    Write-Host "Running containers"
    $NetworkName = $TestConfiguration.DockerDriverConfiguration.NetworkConfiguration.NetworkName
    $ServerID = Invoke-Command -Session $Session1 -ScriptBlock { docker run --network $Using:NetworkName -d iis-tcptest }
    $ClientID = Invoke-Command -Session $Session2 -ScriptBlock { docker run --network $Using:NetworkName -id microsoft/nanoserver powershell }

    . $PSScriptRoot\CommonTestCode.ps1

    $ServerIP, $ClientIP = Initialize-MPLSoGRE -Session1 $Session1 -Session2 $Session2 `
        -Container1ID $ServerID -Container2ID $ClientID -TestConfiguration $TestConfiguration

    Write-Host "Invoking web request"
    $Res = Invoke-Command -Session $Session2 -ScriptBlock {
        $ServerIP = $Using:ServerIP
        docker exec $Using:ClientID powershell "Invoke-WebRequest -Uri http://${ServerIP}:8080/" | Write-Host
        return $LASTEXITCODE
    }

    Write-Host "Removing containers"
    Invoke-Command -Session $Session1 -ScriptBlock { docker rm -f $Using:ServerID } | Out-Null
    Invoke-Command -Session $Session2 -ScriptBlock { docker rm -f $Using:ClientID } | Out-Null

    if($Res -ne 0) {
        throw "===> TCP test failed!"
    }

    Clear-TestConfiguration -Session $Session1 -TestConfiguration $TestConfiguration
    Clear-TestConfiguration -Session $Session2 -TestConfiguration $TestConfiguration

    Write-Host "===> Success"
}
