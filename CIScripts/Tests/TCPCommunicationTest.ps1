function Test-TCPCommunication {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

    Write-Host "===> Running TCP Communication test"

    Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    $NetworkName = $TestConfiguration.DockerDriverConfiguration.NetworkConfiguration.NetworkName

    Write-Host "Creating containers"
    $ServerID, $ClientID = Invoke-Command -Session $Session -ScriptBlock {
        $ServerID = docker run --network $Using:NetworkName -d iis-tcptest
        $ClientID = docker run --network $Using:NetworkName -d microsoft/nanoserver ping -t localhost
        return $ServerID, $ClientID
    }

    . $PSScriptRoot\CommonTestCode.ps1

    Write-Host "Getting VM NetAdapter Information"
    $VMNetInfo = Get-RemoteNetAdapterInformation -Session $Session -AdapterName $TestConfiguration.AdapterName

    Write-Host "Getting vHost NetAdapter Information"
    $VHostInfo = Get-RemoteNetAdapterInformation -Session $Session -AdapterName $TestConfiguration.VHostName

    Write-Host "Getting Containers NetAdapter Information"
    $ServerNetInfo = Get-RemoteContainerNetAdapterInformation -Session $Session -ContainerID $ServerID
    $ClientNetInfo = Get-RemoteContainerNetAdapterInformation -Session $Session -ContainerID $ClientID

    Write-Host $("Setting a connection between " + $ServerNetInfo.MACAddress + " and " + $ClientNetInfo.MACAddress + "...")
    Invoke-Command -Session $Session -ScriptBlock {
        vif.exe --add $Using:VMNetInfo.IfName --mac $Using:VMNetInfo.MACAddress --vrf 0 --type physical
        vif.exe --add $Using:VHostInfo.IfName --mac $Using:VHostInfo.MACAddress --vrf 0 --type vhost --xconnect $Using:VMNetInfo.IfName

        vif.exe --add $Using:ServerNetInfo.IfName --mac $Using:ServerNetInfo.MACAddress --vrf 1 --type virtual
        vif.exe --add $Using:ClientNetInfo.IfName --mac $Using:ClientNetInfo.MACAddress --vrf 1 --type virtual

        nh.exe --create 1 --vrf 1 --type 2 --el2 --oif $Using:ServerNetInfo.IfIndex
        nh.exe --create 2 --vrf 1 --type 2 --el2 --oif $Using:ClientNetInfo.IfIndex
        nh.exe --create 3 --vrf 1 --type 6 --cen --cni 1 --cni 2

        rt.exe -c -v 1 -f 1 -e ff:ff:ff:ff:ff:ff -n 3
        rt.exe -c -v 1 -f 1 -e $Using:ServerNetInfo.MACAddress -n 1
        rt.exe -c -v 1 -f 1 -e $Using:ClientNetInfo.MACAddress -n 2
    }

    Write-Host "Executing netsh"
    Invoke-Command -Session $Session -ScriptBlock {
        docker exec $Using:ServerID netsh interface ipv4 add neighbors $Using:ServerNetInfo.AdapterFullName $Using:ClientNetInfo.IPAddress $Using:ClientNetInfo.MACAddressWindows
        docker exec $Using:ClientID netsh interface ipv4 add neighbors $Using:ClientNetInfo.AdapterFullName $Using:ServerNetInfo.IPAddress $Using:ServerNetInfo.MACAddressWindows
    } | Out-Null

    $Res = Invoke-Command -Session $Session -ScriptBlock {
        $ServerIP = $Using:ServerNetInfo.IPAddress
        docker exec $ClientID powershell "Invoke-WebRequest -Uri http://${ServerIP}:8080/ -ErrorAction Continue" | Write-Host
        return $LASTEXITCODE
    }

    Write-Host "Removing containers"
    Invoke-Command -Session $Session -ScriptBlock { docker rm -f $Using:ServerID } | Out-Null
    Invoke-Command -Session $Session -ScriptBlock { docker rm -f $Using:ClientID } | Out-Null

    if($Res -ne 0) {
        throw "===> TCP test failed!"
    }

    Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    Write-Host "===> Success!"
}
