function Run-Test {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [string] $TestExecutable)
    Write-Host -NoNewline "===> Agent tests: running $TestExecutable... "
    $Res = Invoke-Command -Session $Session -ScriptBlock {
        $Res = Invoke-Command -ScriptBlock {
            $ErrorActionPreference = "SilentlyContinue"
            Invoke-Expression "C:\Artifacts\$using:TestExecutable --config C:\Artifacts\vnswa_cfg.ini" | Out-Null
            $LASTEXITCODE
        }
        
        return $Res
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
    $Res = Invoke-Command -Session $Session -ScriptBlock {
        $env:Path += ";C:\Program Files\Juniper Networks\Agent"
    }
    Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration
    Invoke-Command -Session $Session -ScriptBlock {
        $ConfigurationFile = "C:\Artifacts\vnswa_cfg.ini"
        $Configuration = Get-Content $ConfigurationFile
        $VirtualInterfaceName = (Get-NetAdapter -Name "vEthernet (HNSTransparent)").IfName
        $PhysicalInterfaceName = (Get-NetAdapter -Name "Ethernet1").IfName
        $Configuration = $Configuration -replace "name=.*", "name=$VirtualInterfaceName"
        $Configuration = $Configuration -replace "physical_interface=.*", "physical_interface=$PhysicalInterfaceName"
        Set-Content $ConfigurationFile $Configuration
    }

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
        Throw "===> Agent tests: some tests failed."
    }
}
