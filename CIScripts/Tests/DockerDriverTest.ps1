function Test-DockerDriver {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

    Write-Host "Running Docker Driver test."

    $TestFailed = $false
    $TestsPath = "C:\Program Files\Juniper Networks\"
    $AdapterName = $TestConfiguration.AdapterName

    # Some of tests requires static IP address
    Invoke-Command -Session $Session -ScriptBlock {
        netsh interface ipv4 set address name=$Using:AdapterName static 10.100.10.0 255.255.0.0 10.100.10.1
    }

    $TestFiles = @("controller", "hns", "hnsManager", "driver")
    foreach ($TestFile in $TestFiles) {
        $TestFilePath = ".\" + $TestFile + ".test.exe"
        $Command = @($TestFilePath, "--ginkgo.noisyPendings", "--ginkgo.failFast", "--ginkgo.progress", "--ginkgo.v", "--ginkgo.trace")
        if ($TestFile -ne "controller") {
            $Command += ("--netAdapter=" + $TestConfiguration.AdapterName)
        }
        $Command = $Command -join " "

        $Res = Invoke-Command -Session $Session -ScriptBlock {
            Push-Location $Using:TestsPath

            # Invoke-Command used as a workaround for temporary ErrorActionPreference modification
            $Res = Invoke-Command -ScriptBlock {
                $ErrorActionPreference = "SilentlyContinue"
                Invoke-Expression -Command $Using:Command | Write-Host
                return $LASTEXITCODE
            }

            Pop-Location

            return $Res
        }

        if ($Res -ne 0) {
            $TestFailed = $true
            break
        }
    }

    # Reverting address to DHCP
    Invoke-Command -Session $Session -ScriptBlock {
        netsh interface ipv4 set address name=$Using:AdapterName dhcp
    }

    # Copying test results
    $TestFiles.ForEach({
        Copy-Item -FromSession $Session -Path ($TestsPath + $_ + "_junit.xml") -ErrorAction SilentlyContinue
    })

    if ($TestFailed -eq $true) {
        throw "Docker Driver test failed."
    }

    Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    Write-Host "Success"
}
