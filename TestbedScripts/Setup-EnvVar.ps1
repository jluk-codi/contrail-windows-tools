Write-Host "Setting up environment variables..."
$Env:VRouterDirectory = "C:\Artifacts"
$Env:VRouterPhysicalIfName = "Ethernet1"
$Env:VMSwitchName = "Layered " + $Env:VRouterPhysicalIfName
$Env:ForwardingExtensionName = "vRouter forwarding extension"
$Env:DockerNetworkName = "The-Juniper-Crew"
$Env:Container1Name = "Vigorous-Bitcoin-Miner"
$Env:Container2Name = "Jolly-Lumberjack"
$Env:Container1IP = "192.168.0.1"
$Env:Container2IP = "192.168.0.2"
$Env:AgentExecutableName = "contrail-vrouter-agent.exe"
$Env:AgentExecutablePath = $(Join-Path "C:\Program Files\Juniper Networks\Agent" $Env:AgentExecutableName)
$Env:AgentConfigurationFile = "contrail-vrouter-agent.conf"
