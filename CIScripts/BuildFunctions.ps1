class Repo {
    [string] $Url;
    [string] $Branch;
    [string] $Dir;
    [string] $DefaultBranch;
    [bool] $AllowBranchOverride;

    [void] init([string] $Url, [string] $Branch, [string] $Dir, [string] $DefaultBranch, [bool] $AllowBranchOverride) {
        $this.Url = $Url
        $this.Branch = $Branch
        $this.Dir = $Dir
        $this.DefaultBranch = $DefaultBranch
        $this.AllowBranchOverride = $AllowBranchOverride
    }

    Repo ([string] $Url, [string] $Branch, [string] $Dir, [string] $DefaultBranch) {
        $this.init($Url, $Branch, $Dir, $DefaultBranch, $true)
    }

    Repo ([string] $Url, [string] $Branch, [string] $Dir, [string] $DefaultBranch, [bool] $AllowBranchOverride) {
        $this.init($Url, $Branch, $Dir, $DefaultBranch, $AllowBranchOverride)
    }
}

function Copy-Repos {
    Param ([Parameter(Mandatory = $true, HelpMessage = "List of repos to clone")] [Repo[]] $Repos)
    
    Write-Output "Cloning repositories"
    $CustomBranches = @($Repos.Where({ $_.Branch -ne $_.DefaultBranch }) | Select-Object -ExpandProperty Branch -Unique)
    $Repos.ForEach({
        if ($_.AllowBranchOverride) {
            # If there is only one unique custom branch provided, at first try to use it for all repos.
            # Otherwise, use branch specific for this repo.
            $CustomMultiBranch = $(if ($CustomBranches.Count -eq 1) { $CustomBranches[0] } else { $_.Branch })

            Write-Output $("Cloning " +  $_.Url + " from branch: " + $CustomMultiBranch)
            git clone -b $CustomMultiBranch $_.Url $_.Dir
        }

        if (($LASTEXITCODE -ne 0) -or ! $_.AllowBranchOverride) {
            Write-Output $("Cloning " +  $_.Url + " from branch: " + $_.Branch)
            git clone -b $_.Branch $_.Url $_.Dir

            if ($LASTEXITCODE -ne 0) {
                throw "Cloning from " + $_.Url + " failed"
            }
        }
    })
}

function Invoke-ContrailCommonActions {
    Param ([Parameter(Mandatory = $true)] [string] $ThirdPartyCache,
           [Parameter(Mandatory = $true)] [string] $VSSetupEnvScriptPath)
    
    Write-Output "Sourcing VS environment variables"
    Invoke-BatchFile "$VSSetupEnvScriptPath"
    
    Write-Output "Copying common third-party dependencies"
    New-Item -ItemType Directory .\third_party
    Copy-Item -Recurse "$ThirdPartyCache\common\*" third_party\

    Copy-Item tools\build\SConstruct .\
}

function Set-MSISignature {
    Param ([Parameter(Mandatory = $true)] [string] $SigntoolPath,
           [Parameter(Mandatory = $true)] [string] $CertPath,
           [Parameter(Mandatory = $true)] [string] $CertPasswordFilePath,
           [Parameter(Mandatory = $true)] [string] $MSIPath)
    
    $cerp = Get-Content $CertPasswordFilePath
    & $SigntoolPath sign /f $CertPath /p $cerp $MSIPath
    if ($LASTEXITCODE -ne 0) {
        throw "Signing $MSIPath failed"
    }
}

function Invoke-DockerDriverBuild {
    Param ([Parameter(Mandatory = $true)] [string] $DriverSrcPath,
           [Parameter(Mandatory = $true)] [string] $SigntoolPath,
           [Parameter(Mandatory = $true)] [string] $CertPath,
           [Parameter(Mandatory = $true)] [string] $CertPasswordFilePath)
    
    $Env:GOPATH=pwd
    
    New-Item -ItemType Directory ./bin
    Push-Location bin

    Write-Output "Installing test runner"
    go get -u -v github.com/onsi/ginkgo/ginkgo

    Write-Output "Building driver"
    go build -v $DriverSrcPath

    $srcPath = "$Env:GOPATH/src/$DriverSrcPath"
    Write-Output $srcPath

    Write-Output "Precompiling tests"
    $modules = @("driver", "controller", "hns", "hnsManager")
    $modules.ForEach({
        .\ginkgo.exe build $srcPath/$_
        Move-Item $srcPath/$_/$_.test ./
    })

    Write-Output "Copying Agent API python script"
    Copy-Item $srcPath/scripts/agent_api.py ./

    Write-Output "Intalling MSI builder"
    go get -u -v github.com/mh-cbon/go-msi

    Write-Output "Building MSI"
    Push-Location $srcPath
    & "$Env:GOPATH/bin/go-msi" make --msi docker-driver.msi --arch x64 --version 0.1 --src template --out $pwd/gomsi
    Pop-Location

    Move-Item $srcPath/docker-driver.msi ./
    
    Set-MSISignature -SigntoolPath $SigntoolPath -CertPath $CertPath -CertPasswordFilePath $CertPasswordFilePath -MSIPath "docker-driver.msi"

    Pop-Location
}

function Invoke-ExtensionBuild {
    Param ([Parameter(Mandatory = $true)] [string] $ThirdPartyCache,
           [Parameter(Mandatory = $true)] [string] $SigntoolPath,
           [Parameter(Mandatory = $true)] [string] $CertPath,
           [Parameter(Mandatory = $true)] [string] $CertPasswordFilePath)
    
    Write-Output "Copying Extension dependencies"
    Copy-Item -Recurse "$ThirdPartyCache\extension\*" third_party\
    Copy-Item -Recurse third_party\cmocka vrouter\test\

    
    Write-Output "Building Extension and Utils"
    scons vrouter
    if ($LASTEXITCODE -ne 0) {
        throw "Building vRouter solution failed"
    }

    $vRouterMSI = "build\debug\vrouter\extension\vRouter.msi"
    $utilsMSI = "build\debug\vrouter\utils\utils.msi"
    
    Write-Output "Signing utilsMSI"
    Set-MSISignature -SigntoolPath $SigntoolPath -CertPath $CertPath -CertPasswordFilePath $CertPasswordFilePath -MSIPath $utilsMSI
    
    Write-Output "Signing vRouterMSI"
    Set-MSISignature -SigntoolPath $SigntoolPath -CertPath $CertPath -CertPasswordFilePath $CertPasswordFilePath -MSIPath $vRouterMSI
}

function Invoke-AgentBuild {
    Param ([Parameter(Mandatory = $true)] [string] $ThirdPartyCache)
    
    Write-Output "Copying Agent dependencies"
    Copy-Item -Recurse "$ThirdPartyCache\agent\*" third_party/

    
    Write-Output "Building Agent, MSI and API"
    scons controller/src/vnsw/contrail_vrouter_api:sdist
    if ($LASTEXITCODE -ne 0) {
        throw "Building API failed"
    }
    scons contrail-vrouter-agent.msi -j 2
    if ($LASTEXITCODE -ne 0) {
        throw "Building Agent failed"
    }

    Write-Output "Building tests"

    $Tests = @()

    # KSync tests almost work
    # $Tests = @("agent:test_ksync", "src/ksync:ksync_test")

    # TODO: Add other tests here once they are functional.

    if ($Tests.count -gt 0) {
        $TestsString = $Tests -join " "

        $BuildCommand = "scons"
        $TestsBuildCommand = "{0} {1}" -f "$BuildCommand", "$TestsString"
        Invoke-Expression $TestsBuildCommand
        if ($LASTEXITCODE -ne 0) {
            throw "Building tests failed"
        }
    } else {
        Write-Output "    No tests to build."
    }
}

