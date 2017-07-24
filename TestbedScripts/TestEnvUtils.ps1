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
    $mac = docker exec $ContainerName powershell -Command {
        (Get-NetAdapter | Select-Object -first 1).macaddress
    }
    return $mac
}

function Initialize-ContainerInterface {
    Param ([Parameter(Mandatory = $true)] [string] $ContainerName,
           [Parameter(Mandatory = $true)] [string] $ContainerIP,
           [Parameter(Mandatory = $true)] [string] $PrefixLength,
           [Parameter(Mandatory = $true)] [string] $TheOtherMac,
           [Parameter(Mandatory = $true)] [string] $TheOtherIP)
    $command = ('$ifname = (Get-NetAdapter | Select-Object -first 1).Name; ' +`
        '$ip_set_properly = (New-NetIPAddress -interfacealias ' +`
        '$ifname -ipaddress {0} -prefixlength {1}).Length; ' +`
        'arp -s {2} {3} | Out-Null; ' +`
        '$arp_set_properly = $LASTEXITCODE; ' +`
        'return $($ip_set_properly -gt 0 -and $arp_set_properly -eq 0)' `
        ) -f $ContainerIP, $PrefixLength, $TheOtherIP, $TheOtherMac
    $Res = docker exec $ContainerName powershell -Command $command 2>&1
    return $Res
}

function Initialize-ContainerInterfaces {
    Write-Host "Initializing network interfaces for containers... "
    Write-Host -NoNewline "Reading MAC address of '$Env:Container1Name'... "
    $Mac1 = Get-MacOfContainer -ContainerName $Env:Container1Name
    Write-Host $Mac1
    Write-Host -NoNewline "Reading MAC address of '$Env:Container2Name'... "
    $Mac2 = Get-MacOfContainer -ContainerName $Env:Container2Name
    Write-Host $Mac2
    Write-Host -NoNewline "Setting up network interface for '$Env:Container1Name'..."
    $Res = Initialize-ContainerInterface -ContainerName $Env:Container1Name `
        -ContainerIP $Env:Container1IP -PrefixLength $Env:ContainerIPPrefixLength `
        -TheOtherMac $mac2 -TheOtherIP $Env:Container2IP
    if ($Res -eq $true) {
        Write-Host "Done."
    } else {
        Write-Host "Failed."
    }
    Write-Host -NoNewline "Setting up network interface for '$Env:Container2Name'..."
    $Res = Initialize-ContainerInterface -ContainerName $Env:Container2Name `
        -ContainerIP $Env:Container2IP -PrefixLength $Env:ContainerIPPrefixLength `
        -TheOtherMac $mac1 -TheOtherIP $Env:Container1IP
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

function Initialize-ForwardingRules {
    Write-Host "TODO: Initializing forwarding rules..."
    # TODO JW-884
}

# Relies on system environment variables: DockerNetworkName,
# VRouterPhysicalIfName, DockerNetworkName, Container1Name, Container1IP,
# Container2Name, Container2IP.
function Initialize-DockerNetworkAccordingToEnv {
    Initialize-DockerNetwork -PhysicalIfName $Env:VRouterPhysicalIfName `
        -NetworkName $Env:DockerNetworkName
    Initialize-Container -ContainerName $Env:Container1Name -NetworkName `
        $Env:DockerNetworkName -IPAddress $Env:Container1IP
    Initialize-Container -ContainerName $Env:Container2Name -NetworkName `
        $Env:DockerNetworkName -IPAddress $Env:Container2IP
    Initialize-ContainerInterfaces
    Initialize-ForwardingRules
}

# Relies on environment variables: Container1Name, Container2Name,
# DockerNetworkName.
function Remove-DockerNetworkAccordingToEnv {
    Remove-Container -ContainerName $Env:Container1Name
    Remove-Container -ContainerName $Env:Container2Name
    Remove-DockerNetwork -NetworkName $Env:DockerNetworkName
}

# Relies on environment variables: AgentExecutablePath,
# AgentConfigFile.
function Run-Agent {
    Write-Host "Starting Agent..."
    $arguments = "--config_file", $Env:AgentConfigurationFile
    &$Env:AgentExecutablePath $arguments
}

# Relies on environment variable: AgentExecutableName.
function Stop-Agent {
    Write-Host "Stopping agent..."
    Stop-ProcessIfExists $Env:AgentExecutableName
}

# Sets up an environment consisting of:
# 1) vRouter Extension,
# 2) Agent,
# 3) 2 docker containers.
# It is assumed that proper artifacts are installed as it is done by
# spawn-testbed-new Jenkins job.
# Relies on environment variables: VMSwitchName, ForwardingExtensionName
# and on dependencies of Initialize-DockerNetworkAccordingToEnv.
function Initialize-SimpleEnvironment {
    Write-Host "Initializing simple test environment..."
    Initialize-DockerNetworkAccordingToEnv
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

    Run-Agent
}

# Removes test environment created by Initialize-SimpleEnvironment.
# Relies on environment variables (indirectly) - see
# Remove-DockerNetworkAccordingToEnv, Stop-Agent, Disable-VRouterExtension.
function Remove-SimpleEnvironment {
    Write-Host "Removing simple test environment..."
    Remove-DockerNetworkAccordingToEnv
    Stop-Agent
    Disable-VRouterExtension
}
