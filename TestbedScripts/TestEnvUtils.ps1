# Utility functions provided as a mean to simplify setting up test environment
# for manual tests of Agent.
# By default relevant environment variables are created in Setup-EnvVars.ps1.
# Example usage can be seen in Setup-SimpleTestEnv.ps1.

function Stop-ProcessIfExists {
    Param ([Parameter(Mandatory = $true)] [string] $ProcessName)
    $Proc = Get-Process $ProcessName -ErrorAction SilentlyContinue
    if ($Proc) {
        $Proc | Stop-Process -Force
    }
}

function Test-IsProcessRunning {
    Param ([Parameter(Mandatory = $true)] [string] $ProcessName)
    $Proc = Get-Process $ProcessName -ErrorAction SilentlyContinue
    return $(if ($Proc) { $true } else { $false })
}

function Initialize-DockerNetwork {
    Param ([Parameter(Mandatory = $true)] [string] $PhysicalIfName,
           [Parameter(Mandatory = $true)] [string] $NetworkName)
    Write-Host -NoNewline "Checking if docker network '$NetworkName' exists... "
    $NotExists = Invoke-Command -ScriptBlock {
        docker network inspect $NetworkName 2>&1 | Out-Null
        $LASTEXITCODE
    }
    if ($NotExists -eq 0) {
        Write-Host "Yes."
    } else {
        Write-Host "No."
        Write-Host -NoNewline $("Creating docker network '$NetworkName' on " +`
            "network interface '$PhysicalIfName'...")
        docker network create -d transparent `
            -o com.docker.network.windowsshim.interface=$PhysicalIfName `
            $NetworkName 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed."
            throw "Without docker network further efforts are pointless!"
        } else {
            Write-Host "Done."
        }
    }
}

function Get-MacOfContainer {
    Param ([Parameter(Mandatory = $true)] [string] $ContainerName)
    Write-Host -NoNewline "Reading MAC address of '$ContainerName'... "
    $Mac = docker exec $ContainerName powershell -Command {
        (Get-NetAdapter | Select-Object -First 1).MacAddress
    }
    Write-Host $Mac
    return $Mac
}

function Get-FriendlyNameOfContainer {
    Param ([Parameter(Mandatory = $true)] [string] $ContainerName)
    Write-Host -NoNewline "Reading interface name of '$ContainerName'... "
    $Name = docker exec $ContainerName powershell -Command {
        (Get-NetAdapter | Select-Object -First 1).Name
    }
    Write-Host "$Name"
    if ($Name -match "\S+\s\((?<FriendlyName>[\S\s]+)\)") {
        $FriendlyName = $matches.FriendlyName
        Write-Host "    Friendly name of the interface is: $FriendlyName"
        return $FriendlyName
    } else {
        Write-Host "    Could not fetch friendly name of the interface."
        return ""
    }
}

function Initialize-ContainerInterface {
    Param ([Parameter(Mandatory = $true)] [string] $ContainerName,
           [Parameter(Mandatory = $true)] [string] $ContainerIP,
           [Parameter(Mandatory = $true)] [string] $PrefixLength,
           [Parameter(Mandatory = $true)] [string] $TheOtherMac,
           [Parameter(Mandatory = $true)] [string] $TheOtherIP)
    $Command = ('$IfName = (Get-NetAdapter | Select-Object -First 1).Name; ' +`
        '$IPAddressesCount = (New-NetIPAddress -InterfaceAlias ' +`
        '$IfName -IPAddress {0} -PrefixLength {1}).Length; ' +`
        'arp -s {2} {3} | Out-Null; ' +`
        '$ARPSetProperly = $LASTEXITCODE; ' +`
        'return $($IPAddressesCount -gt 0 -and $ARPSetProperly -eq 0)' `
        ) -f $ContainerIP, $PrefixLength, $TheOtherIP, $TheOtherMac
    $Res = docker exec $ContainerName powershell -Command $Command 2>&1
    return $Res
}

# Relies on system environment variables: Container1Name, Container1IP,
# Container2Name, Container2IP, ContainerIPPrefixLength.
function Initialize-ContainerInterfaces {
    Param ([Parameter(Mandatory = $true)] [string] $Mac1,
           [Parameter(Mandatory = $true)] [string] $Mac2)
    Write-Host "Initializing network interfaces for containers... "
    Write-Host -NoNewline "Setting up network interface for '$Env:Container1Name'... "
    $Res = Initialize-ContainerInterface -ContainerName $Env:Container1Name `
        -ContainerIP $Env:Container1IP -PrefixLength $Env:ContainerIPPrefixLength `
        -TheOtherMac $Mac2 -TheOtherIP $Env:Container2IP
    if ($Res -eq $true) {
        Write-Host "Done."
    } else {
        Write-Host "Failed."
    }
    Write-Host -NoNewline "Setting up network interface for '$Env:Container2Name'... "
    $Res = Initialize-ContainerInterface -ContainerName $Env:Container2Name `
        -ContainerIP $Env:Container2IP -PrefixLength $Env:ContainerIPPrefixLength `
        -TheOtherMac $Mac1 -TheOtherIP $Env:Container1IP
    if ($Res -eq $true) {
        Write-Host "Done."
    } else {
        Write-Host "Failed."
    }
}

function Initialize-Container {
    Param ([Parameter(Mandatory = $true)] [string] $ContainerName,
           [Parameter(Mandatory = $true)] [string] $NetworkName,
           [Parameter(Mandatory = $true)] [string] $IPAddress)
    Write-Host -NoNewline "Checking if container '$ContainerName' exists... "
    $NotExists = Invoke-Command -ScriptBlock {
        docker inspect $ContainerName 2>&1 | Out-Null
        $LASTEXITCODE
    }
    if ($NotExists -ne 0) {
        Write-Host "No."
        Write-Host -NoNewline $("Creating containter '$ContainerName' " +`
            "in network '$NetworkName'... ")
        $Res = Invoke-Command -ScriptBlock {
            docker run -i --rm -d --net $NetworkName --name $ContainerName `
                microsoft/nanoserver powershell 2>&1 | Out-Null
            $LASTEXITCODE
        }
        if ($Res -ne 0) {
            Write-Host "Failed."
        } else {
            Write-Host "Done."
        }
    } else {
        Write-Host "Yes."
    }
}

function Test-IsVRouterExtensionEnabled {
    Param ([Parameter(Mandatory = $true)] [string] $VMSwitchName,
           [Parameter(Mandatory = $true)] [string] $ForwardingExtensionName)
    $VMSwitchExtension = $(Get-VMSwitchExtension `
        -VMSwitchName $VMSwitchName -Name $ForwardingExtensionName `
        -ErrorAction SilentlyContinue)
    return $($VMSwitchExtension.Enabled -and $VMSwitchExtension.Running)
}

function Remove-Container {
    Param ([Parameter(Mandatory = $true)] [string] $ContainerName)
    Write-Host -NoNewline "Removing container '$ContainerName'... "
    docker stop $ContainerName 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed."
    } else {
        Write-Host "Done."
    }
}

function Remove-DockerNetwork {
    Param ([Parameter(Mandatory = $true)] [string] $NetworkName)
    Write-Host -NoNewline "Removing docker network '$NetworkName'... "
    docker network rm $NetworkName 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed."
    } else {
        Write-Host "Done."
    }
}

function Enable-VRouterExtension {
    Param ([Parameter(Mandatory = $true)] [string] $VMSwitchName,
           [Parameter(Mandatory = $true)] [string] $ForwardingExtensionName)
    Write-Host -NoNewline "Enabling vRouter Extension... "
    Get-VMSwitchExtension -VMSwitchName $VMSwitchName `
        -Name $ForwardingExtensionName | Enable-VMSwitchExtension | Out-Null
    $Res = Test-IsVRouterExtensionEnabled -VMSwitchName $VMSwitchName `
        -ForwardingExtensionName $ForwardingExtensionName
    if ($Res -eq $true) {
        Write-Host "Done."
    } else {
        Write-Host "Failed."
        throw "Without vRouter Extension further efforts are pointless!"
    }
}

function Disable-VRouterExtension {
    Param ([Parameter(Mandatory = $true)] [string] $VMSwitchName,
           [Parameter(Mandatory = $true)] [string] $ForwardingExtensionName)
    Write-Host -NoNewline "Disabling vRouter Extension... "
    $Disabled = Get-VMSwitchExtension -VMSwitchName $VMSwitchName `
        -Name $ForwardingExtensionName | Disable-VMSwitchExtension
    if ($Disabled -eq $false) {
        Write-Host "Failed."
    } else {
        Write-Host "Done."
    }
}

# Relies on system environment variables: VRouterPhysicalIfName
function Initialize-ForwardingRules {
    Param ([Parameter(Mandatory = $true)] [string] $MacPhysical,
           [Parameter(Mandatory = $true)] [string] $MacHNSTransparent,
           [Parameter(Mandatory = $true)] [string] $Mac1,
           [Parameter(Mandatory = $true)] [string] $Mac2,
           [Parameter(Mandatory = $true)] [string] $Container1IfName,
           [Parameter(Mandatory = $true)] [string] $Container2IfName)
    Write-Host "Initializing forwarding rules..."
    $MacPhysicalUnixFormat = $MacPhysical -Replace "-", ":"
    $MacHNSTransparentUnixFormat = $MacHNSTransparent -Replace "-", ":"
    $Mac1UnixFormat = $Mac1 -Replace "-", ":"
    $Mac2UnixFormat = $Mac2 -Replace "-", ":"

    Write-Host -NoNewline "Setting up vifs... "
    $VifsSetUp = $true
    vif --add (Get-NetAdapter -Name "$Env:VRouterPhysicalIfName").IfName --mac $MacPhysicalUnixFormat --vrf 0 --type physical
    if ($LASTEXITCODE -ne 0) {
        $VifsSetUp = $false
    }
    vif --add HNSTransparent --mac $MacHNSTransparentUnixFormat --vrf 0 --type vhost --xconnect (Get-NetAdapter -Name "$Env:VRouterPhysicalIfName").IfName
    if ($LASTEXITCODE -ne 0) {
        $VifsSetUp = $false
    }
    vif --add $Container1IfName --mac $Mac1UnixFormat --vrf 1 --type virtual --vif 1111
    if ($LASTEXITCODE -ne 0) {
        $VifsSetUp = $false
    }
    vif --add $Container2IfName --mac $Mac2UnixFormat --vrf 1 --type virtual --vif 2222
    if ($LASTEXITCODE -ne 0) {
        $VifsSetUp = $false
    }
    if($VifsSetUp -eq $true) {
        Write-Host "Done."
    } else {
        Write-Host "Failed."
    }

    Write-Host -NoNewline "Setting up next hops..."
    $NHsSetUp = $true
    nh --create 1 --vrf 1 --type 2 --el2 --oif 1111
    if ($LASTEXITCODE -ne 0) {
        $NHsSetUp = $false
    }
    nh --create 2 --vrf 1 --type 2 --el2 --oif 2222
    if ($LASTEXITCODE -ne 0) {
        $NHsSetUp = $false
    }
    if($NHsSetUp -eq $true) {
        Write-Host "Done."
    } else {
        Write-Host "Failed."
    }

    Write-Host -NoNewline "Setting up routes..."
    $RTsSetUp = $true
    rt -c -v 1 -f 1 -e $Mac1UnixFormat -n 1
    if ($LASTEXITCODE -ne 0) {
        $RTsSetUp = $false
    }
    rt -c -v 1 -f 1 -e $Mac2UnixFormat -n 2
    if ($LASTEXITCODE -ne 0) {
        $RTsSetUp = $false
    }
    if($RTsSetUp -eq $true) {
        Write-Host "Done."
    } else {
        Write-Host "Failed."
    }
}

# Relies on environment variables: Container1Name, Container2Name,
# DockerNetworkName.
function Remove-DockerNetworkAccordingToEnv {
    Remove-Container -ContainerName $Env:Container1Name
    Remove-Container -ContainerName $Env:Container2Name
    Remove-DockerNetwork -NetworkName $Env:DockerNetworkName
}

# Relies on environment variable: AgentExecutableName.
function Stop-Agent {
    Write-Host "Stopping agent..."
    Stop-ProcessIfExists $Env:AgentExecutableName
}

# Sets up an environment consisting of:
# 1) vRouter Extension,
# 2) 2 docker containers.
# It is assumed that proper artifacts are installed as it is done by
# spawn-testbed-new Jenkins job.
# Relies on environment variables: VMSwitchName, ForwardingExtensionName,
# Container1Name, Container2Name, Container1IP, Container2IP,
# VRouterPhysicalIfName, DockerNetworkName, ContainerIPPrefixLength.
function Initialize-SimpleEnvironment {
    Write-Host "Initializing simple test environment..."

    Initialize-DockerNetwork -PhysicalIfName $Env:VRouterPhysicalIfName `
        -NetworkName $Env:DockerNetworkName
    Initialize-Container -ContainerName $Env:Container1Name -NetworkName `
        $Env:DockerNetworkName -IPAddress $Env:Container1IP
    Initialize-Container -ContainerName $Env:Container2Name -NetworkName `
        $Env:DockerNetworkName -IPAddress $Env:Container2IP

    $Mac1 = Get-MacOfContainer -ContainerName $Env:Container1Name
    $Mac2 = Get-MacOfContainer -ContainerName $Env:Container2Name
    $Container1IfName = Get-FriendlyNameOfContainer -ContainerName $Env:Container1Name
    $Container2IfName = Get-FriendlyNameOfContainer -ContainerName $Env:Container2Name

    Initialize-ContainerInterfaces -Mac1 $Mac1 -Mac2 $Mac2
    $MacPhysical = (Get-NetAdapter -Name "$Env:VRouterPhysicalIfName").MacAddress
    $MacHNSTransparent = (Get-NetAdapter -Name "vEthernet (HNSTransparent)").MacAddress

    Write-Host -NoNewline "Checking if vRouter Extension is enabled... "
    $Res = Test-IsVRouterExtensionEnabled -VMSwitchName $Env:VMSwitchName `
        -ForwardingExtensionName $Env:ForwardingExtensionName
    if ($Res -ne $true) {
        Write-Host "No."
        Enable-VRouterExtension -VMSwitchName $Env:VMSwitchName `
            -ForwardingExtensionName $Env:ForwardingExtensionName
    } else {
        Write-Host "Yes."
    }

    Initialize-ForwardingRules -MacPhysical $MacPhysical -MacHNSTransparent $MacHNSTransparent -Mac1 $Mac1 -Mac2 $Mac2 -Container1IfName $Container1IfName -Container2IfName $Container2IfName
}

# Removes test environment created by Initialize-SimpleEnvironment.
# Relies on environment variables (indirectly) - see
# Stop-Agent, Remove-DockerNetworkAccordingToEnv.
function Remove-SimpleEnvironment {
    Write-Host "Removing simple test environment..."
    Stop-Agent
    Remove-DockerNetworkAccordingToEnv
}
