Param (
    # PS session to testbed VM
    [Parameter(Mandatory=$true)]
    [System.Management.Automation.Runspaces.PSSession]
    $Session,

    # Physical adapter name
    [Parameter(Mandatory=$true)]
    [string]
    $PhysicalAdapterName,

    # MGMT vSwitch
    [Parameter(Mandatory=$true)]
    [string]
    $MgmtSwitchName,

    # vRouter vSwitch
    [Parameter(Mandatory=$true)]
    [string]
    $VRouterSwitchName,

    # Docker container network
    [Parameter(Mandatory=$false)]
    [string]
    $DockerNetwork = "testnet"
)


# SNAT VM options
$SNAT_DISK_PATH = "C:\snat-vm-image\snat-vm-image.vhdx"
$SNAT_VM_DIR = "C:\snat-vm"

# Some random GUID for vrouter_hyperv.py
$SNAT_GUID = "d8cf77cb-b9b1-4d7d-ad3c-ef54f417cb5f"

# Container config
$CONTAINER_IP = "10.0.0.128"
$CONTAINER_GW = "10.0.0.1"

# TODO: Create MGMT switch
# TODO: SNAT test should use vRouter connected to adapter which is attached to network with
#       some sort of endpoint

Write-Host "Run vrouter_hyperv.py to provision SNAT VM"
Invoke-Command -Session $Session -ScriptBlock {
    python .\vrouter_hyperv.py create `
        --vm_location $Using:SNAT_VM_DIR `
        --vhd_path $Using:SNAT_DISK_PATH `
        --mgmt_vswitch_name $Using:MgmtSwitchName `
        --vrouter_vswitch_name $Using:VRouterSwitchName `
        $Using:SNAT_GUID `
        $Using:SNAT_GUID `
        $Using:SNAT_GUID
}


Write-Host "Extract physical adapter data"
$PhysicalAdapter = Invoke-Command -Session $Session -ScriptBlock {
    $adapter = Get-NetAdapter -Name $Using:PhysicalAdapterName | Select-Object Name,IfName,IfIndex,MacAddress

    @{ `
        "Name" = $adapter.Name; `
        "IfName" = $adapter.IfName; `
        "IfIndex" = $adapter.IfIndex; `
        "MacAddressDashed" = $adapter.MacAddress; `
        "MacAddressColons" = $adapter.MacAddress.replace("-", ":"); `
    }
}

Write-Host "Enable forwarding on the physical adapter"
Invoke-Command -Session $Session -ScriptBlock {
    netsh interface ipv4 set interface $Using:PhysicalAdapter["IfIndex"] forwarding="enabled"
}


Write-Host "Start and configure test container"
$Container = Invoke-Command -Session $Session -ScriptBlock {
    $Id = $(docker run -id --network $Using:DockerNetwork microsoft/nanoserver powershell)

    $AdapterName = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty Name")
    $MacAddress = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty MacAddress")
    $IfIndex = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty IfIndex")

    docker exec $Id powershell "New-NetIPAddress -IPAddress $Using:CONTAINER_IP -DefaultGateway $Using:CONTAINER_GW -PrefixLength 24 -InterfaceIndex $ifIndex"
    # TODO: MAC_INT - mac address of the left NIC
    docker exec $Id powershell "netsh interface ipv4 add neighbors $IfIndex $Using:CONTAINER_GW MAC_INT"

    @{ `
        "Id" = $Id; `
        "AdapterName" = $AdapterName; `
        "MacAddressDashed" = $MacAddress; `
        "MacAddressColons" = $MacAddress.replace("-", ":"); `
        "IfIndex" = $IfIndex; `
    }
}

# vRouter object ids
$ContainerVif = $ContainerNh = 101
$SNATLeftVif = $SNATLeftNh = 102
$SNATRightVif = $SNATRightNh = 103
$SNATVethVif = $SNATVethNh = 104
$BroadcastNh = 110

Write-Host "Configure vRouter"
Invoke-Command -Session $Session -ScriptBlock {
    # Register physical adapter in Contrail
    vif.exe --add $Using:PhysicalAdapter["IfName"] --mac $Using:PhysicalAdapter["MacAddressColons"] --vrf 0 --type physical
    vif.exe --add HNSTransparent --mac $Using:PhysicalAdapter["MacAddressColons"] --vrf 0 --type vhost --xconnect $Using:PhysicalAdapter["IfName"]

    # Register container's NIC as vif
    vif.exe --add $Using:Container["AdapterName"] --mac $Using:Container["MacAddress"] --vrf 1 --type virtual --vif $Using:ContainerVif
    nh.exe --create $Using:ContainerNh --vrf 1 --type 2 --el2 --oif $Using:ContainerVif
    rt.exe -c -v 1 -f 1 -e $Using:Container["MacAddress"] -n $Using:ContainerNh

    # Register SNAT's left adapter ("int")
    vif.exe --add $Using:SNATLeftName --mac $Using:SNATLeftMacAddress --vrf 1 --type virtual --vif $Using:SNATLeftVif
    nh.exe --create $Using:SNATLeftNh --vrf 1 --type 2 --el2 --oif $Using:SNATLeftVif
    rt.exe -c -v 1 -f 1 -e $Using:SNATLeftMacAddress -n $Using:SNATLeftNh

    # Register SNAT's right adapter ("gw")
    vif.exe --add $Using:SNATRightName --mac $Using:SNATRightMacAddress --vrf 0 --type virtual --vif $Using:SNATRightVif
    nh.exe --create $Using:SNATRightNh --vrf 0 --type 2 --el2 --oif $Using:SNATRightVif
    rt.exe -c -v 0 -f 1 -e $Using:SNATRightMacAddress -n $Using:SNATRightNh

    # Register SNAT''s additional adapter ("veth")
    vif.exe --add $Using:SNATVethName --mac $Using:SNATVethMacAddress --vrf 0 --type virtual --vif $Using:SNATVethVif
    nh.exe --create $Using:SNATVethNh --vrf 0 --type 2 --el2 --oif $Using:SNATVethVif
    rt.exe -c -v 0 -f 1 -e $Using:SNATVethMacAddress -n $Using:SNATVethNh

    # Broadcast NH
    # TODO: Is this broadcast nexthop really needed?
    nh.exe --create $Using:BroadcastNh --vrf 1 --type 6 --cen --cni $Using:ContainerNh --cni $Using:SNATLeftNh
}
