class NetAdapterInformation {
    [int] $IfIndex;
    [string] $IfName;
    [string] $MACAddress;
}

class ContainerNetAdapterInformation {
    [string] $AdapterShortName;
    [string] $AdapterFullName;
    [string] $MACAddress;
    [string] $MACAddressWindows;
    [string] $IPAddress;
}

function Get-RemoteNetAdapterInformation {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [string] $AdapterName)

    $NetAdapterInformation = Invoke-Command -Session $Session -ScriptBlock {
        $Res = Get-NetAdapter $Using:AdapterName | Select-Object ifName,MacAddress,ifIndex

        return @{
            IfIndex = $Res.IfIndex;
            IfName = $Res.ifName;
            MacAddress = $Res.MacAddress.Replace("-", ":").ToLower();
        }
    }

    return [NetAdapterInformation] $NetAdapterInformation
}

function Get-RemoteContainerNetAdapterInformation {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [string] $ContainerID)

    $NetAdapterInformation = Invoke-Command -Session $Session -ScriptBlock {
        $NetAdapterCommand = "(Get-NetAdapter -Name 'vEthernet (Container NIC *)')[0]"

        $AdapterFullName = docker exec $Using:ContainerID powershell "${NetAdapterCommand}.Name"
        $AdapterShortName = [regex]::new("vEthernet \((.*)\)").Replace($AdapterFullName, "`$1")
        $MACAddressWindows = docker exec $Using:ContainerID powershell "${NetAdapterCommand}.MacAddress.ToLower()"
        $MACAddress = $MACAddressWindows.Replace("-", ":")
        $IPAddress = docker exec $Using:ContainerID powershell "(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias '${AdapterFullName}').IPAddress"

        return @{
            AdapterShortName = $AdapterShortName;
            AdapterFullName = $AdapterFullName;
            MACAddress = $MACAddress;
            MACAddressWindows = $MACAddressWindows;
            IPAddress = $IPAddress;
        }
    }

    return [ContainerNetAdapterInformation] $NetAdapterInformation
}

function Initialize-MPLSoGRE {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session1,
           [Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session2,
           [Parameter(Mandatory = $true)] [string] $Container1ID,
           [Parameter(Mandatory = $true)] [string] $Container2ID,
           [Parameter(Mandatory = $true)] [string] $AdapterName)

    function Initialize-VRouterStructures {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [NetAdapterInformation] $ThisVMNetInfo,
               [Parameter(Mandatory = $true)] [NetAdapterInformation] $OtherVMNetInfo,
               [Parameter(Mandatory = $true)] [ContainerNetAdapterInformation] $ThisContainerNetInfo,
               [Parameter(Mandatory = $true)] [ContainerNetAdapterInformation] $OtherContainerNetInfo,
               [Parameter(Mandatory = $true)] [string] $ThisIPAddress,
               [Parameter(Mandatory = $true)] [string] $OtherIPAddress)

        Invoke-Command -Session $Session -ScriptBlock {
            vif --add $Using:ThisVMNetInfo.IfName --mac $Using:ThisVMNetInfo.MacAddress --vrf 0 --type physical
            vif --add HNSTransparent --mac $Using:ThisVMNetInfo.MACAddress --vrf 0 --type vhost --xconnect $Using:ThisVMNetInfo.IfName
            vif --add $Using:ThisContainerNetInfo.AdapterShortName --mac $Using:ThisContainerNetInfo.MACAddress --vrf 1 --type virtual --vif 1

            nh --create 4 --vrf 0 --type 1 --oif 0
            nh --create 3 --vrf 1 --type 2 --el2 --oif 1
            nh --create 2 --vrf 0 --type 3 --oif $Using:ThisVMNetInfo.IfIndex `
                --dmac $Using:OtherVMNetInfo.MACAddress --smac $Using:ThisVMNetInfo.MACAddress `
                --dip $Using:OtherIPAddress --sip $Using:ThisIPAddress

            mpls --create 10 --nh 3

            rt -c -v 1 -f 1 -e $Using:OtherContainerNetInfo.MACAddress -n 2 -t 10 -x 0x07
            rt -c -v 0 -f 0 -p $Using:ThisIPAddress -l 32 -n 4 -x 0x0f
        }
    }

    Write-Host "Getting VM NetAdapter Information"
    $VM1NetInfo = Get-RemoteNetAdapterInformation -Session $Session1 -AdapterName $AdapterName
    $VM2NetInfo = Get-RemoteNetAdapterInformation -Session $Session2 -AdapterName $AdapterName

    Write-Host "Getting Containers NetAdapter Information"
    $Container1NetInfo = Get-RemoteContainerNetAdapterInformation -Session $Session1 -ContainerID $Container1ID
    $Container2NetInfo = Get-RemoteContainerNetAdapterInformation -Session $Session2 -ContainerID $Container2ID

    Write-Host "Initializing vRouter structures"
    # IPs of logical routers. They do not have to be IPs of the VMs.
    $VM1LogicalRouterIPAddress = "192.168.3.101"
    $VM2LogicalRouterIPAddress = "192.168.3.102"

    Initialize-VRouterStructures -Session $Session1 -ThisVMNetInfo $VM1NetInfo -OtherVMNetInfo $VM2NetInfo `
        -ThisContainerNetInfo $Container1NetInfo -OtherContainerNetInfo $Container2NetInfo `
        -ThisIPAddress $VM1LogicalRouterIPAddress -OtherIPAddress $VM2LogicalRouterIPAddress

    Initialize-VRouterStructures -Session $Session2 -ThisVMNetInfo $VM2NetInfo -OtherVMNetInfo $VM1NetInfo `
        -ThisContainerNetInfo $Container2NetInfo -OtherContainerNetInfo $Container1NetInfo `
        -ThisIPAddress $VM2LogicalRouterIPAddress -OtherIPAddress $VM1LogicalRouterIPAddress

    Write-Host "Executing netsh"
    Invoke-Command -Session $Session1 -ScriptBlock {
        $ContainerAdapterName = $Using:Container1NetInfo.AdapterFullName
        docker exec $Using:Container1ID netsh interface ipv4 add neighbors "$ContainerAdapterName" `
            $Using:Container2NetInfo.IPAddress $Using:Container2NetInfo.MACAddressWindows
    } | Out-Null
    Invoke-Command -Session $Session2 -ScriptBlock {
        $ContainerAdapterName = $Using:Container2NetInfo.AdapterFullName
        docker exec $Using:Container2ID netsh interface ipv4 add neighbors "$ContainerAdapterName" `
            $Using:Container1NetInfo.IPAddress $Using:Container1NetInfo.MACAddressWindows
    } | Out-Null

    return $Container1NetInfo.IPAddress, $Container2NetInfo.IPAddress
}
