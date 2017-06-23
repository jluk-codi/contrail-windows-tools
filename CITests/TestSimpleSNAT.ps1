function Test-SimpleSNAT {
    Param (
        # PS session to testbed VM
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.Runspaces.PSSession]
        $Session,

        # Physical adapter name
        [Parameter(Mandatory=$true)]
        [string]
        $PhysicalAdapterName,

        # vRouter vSwitch
        [Parameter(Mandatory=$true)]
        [string]
        $VRouterSwitchName
    )


    function CreateMgmtSwitch {
        Param (
            [Parameter(Mandatory=$true)]
            [System.Management.Automation.Runspaces.PSSession]
            $Session,

            [Parameter(Mandatory=$true)]
            [string]
            $MgmtSwitchName
        )

        Write-Host "Creating MGMT switch..."
        $oldSwitches = Invoke-Command -Session $Session -ScriptBlock {
            Get-VMSwitch | ? Name -eq $Using:MgmtSwitchName
        }
        if ($oldSwitches) {
            Throw "MGMT switch alredy exists!"
        }

        $newVmSwitch = Invoke-Command -Session $Session -ScriptBlock {
            New-VMSwitch -Name $Using:MgmtSwitchName -SwitchType Internal
        }
        if (!$newVmSwitch) {
            Throw "Failed to create MGMT switch"
        }

        Write-Host "Creating MGMT switch... DONE"
    }


    function ProvisionSNATVM {
        Param (
            [Parameter(Mandatory=$true)][System.Management.Automation.Runspaces.PSSession] $Session,
            [Parameter(Mandatory=$true)][string] $VmDirectory,
            [Parameter(Mandatory=$true)][string] $DiskPath,
            [Parameter(Mandatory=$true)][string] $MgmtSwitchName,
            [Parameter(Mandatory=$true)][string] $GUID
        )

        Write-Host "Run vrouter_hyperv.py to provision SNAT VM..."
        $exitCode = Invoke-Command -Session $Session -ScriptBlock {
            python C:\snat-test\vrouter_hyperv.py create `
                --vm_location $Using:VmDirectory `
                --vhd_path $Using:DiskPath `
                --mgmt_vswitch_name $Using:MgmtSwitchName `
                --vrouter_vswitch_name $Using:VRouterSwitchName `
                $Using:GUID `
                $Using:GUID `
                $Using:GUID
            
            $lastexitcode
        }

        if ($exitCode == 0) {
            Write-Host "Run vrouter_hyperv.py to provision SNAT VM... DONE"
        } else {
            Throw "Run vrouter_hyperv.py to provision SNAT VM... FAILED"
        }
    }

    # SNAT VM options
    $SNAT_MGMT_SWITCH = "snat-mgmt"
    #$SNAT_MGMT_ADAPTER = $SNAT_MGMT_SWITCH
    $SNAT_DISK_PATH = "C:\snat-vm-image\snat-vm-image.vhdx"
    $SNAT_VM_DIR = "C:\snat-vm"

    # Some random GUID for vrouter_hyperv.py
    $SNAT_GUID = "d8cf77cb-b9b1-4d7d-ad3c-ef54f417cb5f"

    # Container config
    $DOCKER_NETWORK = "testnet"
    $CONTAINER_IP = "10.0.0.128"
    $CONTAINER_GW = "10.0.0.1"

    # TODO: SNAT interfaces MAC addresses
    $SNATLeft = @{ `
        "Name" = "int"; `
        "MacAddressDashed" = "DE-AD-BE-EF-00-02"; `
        "MacAddressColons" = "DE:AD:BE:EF:00:02"; `
        "vif" = 102; `
        "nh" = 102; `
    }
    $SNATRight = @{ `
        "Name" = "gw"; `
        "MacAddressDashed" = "DE-AD-BE-EF-00-03"; `
        "MacAddressColons" = "DE:AD:BE:EF:00:03"; `
        "vif" = 103; `
        "nh" = 103; `
    }
    $SNATVeth = @{ `
        "Name" = "veth"; `
        "MacAddressDashed" = "DE-AD-BE-EF-00-04"; `
        "MacAddressColons" = "DE:AD:BE:EF:00:04"; `
        "vif" = 104; `
        "nh" = 104; `
    }

    #CreateMgmtSwitch -Session $Session -MgmtSwitchName $SNAT_MGMT_SWITCH
    # TODO: SNAT test should use vRouter connected to adapter which is attached to network with
    #       some sort of endpoint
    #ProvisionSNATVM -Session $Session -VmDirectory $SNAT_VM_DIR -DiskPath `
        #$SNAT_DISK_PATH -MgmtSwitchName $SNAT_MGMT_SWITCH -GUID $SNAT_GUID

    Write-Host "Extracting physical adapter data..."
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
    Write-Host "Extracting physical adapter data... DONE"

    # TODO: Should use HNSTransparent interface index
    Write-Host "Enable forwarding on the physical adapter..."
    Invoke-Command -Session $Session -ScriptBlock {
        netsh interface ipv4 set interface $Using:PhysicalAdapter["IfIndex"] forwarding="enabled"
    }
    Write-Host "Enable forwarding on the physical adapter... DONE"

    Write-Host "Start and configure test container..."
    $Container = Invoke-Command -Session $Session -ScriptBlock {
        $Id = $(docker run -id --network $Using:DOCKER_NETWORK microsoft/nanoserver powershell)

        $AdapterName = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty Name")
        $MacAddress = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty MacAddress")
        $IfIndex = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty IfIndex")

        docker exec $Id powershell "New-NetIPAddress -IPAddress $Using:CONTAINER_IP -DefaultGateway $Using:CONTAINER_GW -PrefixLength 24 -InterfaceIndex $ifIndex"
        # TODO: MAC_INT - mac address of the left NIC
        docker exec $Id powershell "netsh interface ipv4 add neighbors $IfIndex $Using:CONTAINER_GW $($Using:SNATLeft["MacAddressDashed"])"

        @{ `
            "Id" = $Id; `
            "AdapterName" = $AdapterName; `
            "MacAddressDashed" = $MacAddress; `
            "MacAddressColons" = $MacAddress.replace("-", ":"); `
            "IfIndex" = $IfIndex; `
        }
    }
    Write-Host "Start and configure test container... DONE"

    # vRouter object ids
    $Container["vif"] = 101
    $Container["nh"] = 101

    #$BroadcastNh = 110

    Write-Host "Configure vRouter..."
    Invoke-Command -Session $Session -ScriptBlock {
        $Env:PATH = "C:\Utils\;$Env:PATH"

        # Register physical adapter in Contrail
        vif.exe --add $Using:PhysicalAdapter["IfName"] --mac $Using:PhysicalAdapter["MacAddressColons"] --vrf 0 --type physical
        vif.exe --add HNSTransparent --mac $Using:PhysicalAdapter["MacAddressColons"] --vrf 0 --type vhost --xconnect $Using:PhysicalAdapter["IfName"]

        # Register container's NIC as vif
        vif.exe --add $Using:Container["AdapterName"] --mac $Using:Container["MacAddress"] --vrf 1 --type virtual --vif $Using:Container["vif"]
        nh.exe --create $Using:Container["nh"] --vrf 1 --type 2 --el2 --oif $Using:Container["vif"]
        rt.exe -c -v 1 -f 1 -e $Using:Container["MacAddress"] -n $Using:Container["nh"]

        # Register SNAT's left adapter ("int")
        vif.exe --add $Using:SNATLeft["Name"] --mac $Using:SNATLeft["MacAddressColons"] --vrf 1 --type virtual --vif $Using:SNATLeft["Name"]
        nh.exe --create $Using:SNATLeft["nh"] --vrf 1 --type 2 --el2 --oif $Using:SNATLeft["vif"]
        rt.exe -c -v 1 -f 1 -e $Using:SNATLeft["MacAddressColons"] -n $Using:SNATLeft["nh"]

        # Register SNAT's right adapter ("gw")
        vif.exe --add $Using:SNATRight["Name"] --mac $Using:SNATRight["MacAddressColons"] --vrf 0 --type virtual --vif $Using:SNATRight["vif"]
        nh.exe --create $Using:SNATRight["nh"] --vrf 0 --type 2 --el2 --oif $Using:SNATRight["vif"]
        rt.exe -c -v 0 -f 1 -e $Using:SNATRight["MacAddressColons"] -n $Using:SNATRight["nh"]

        # Register SNAT''s additional adapter ("veth")
        vif.exe --add $Using:SNATVeth["Name"] --mac $Using:SNATVeth["MacAddressColons"] --vrf 0 --type virtual --vif $Using:SNATVeth["vif"]
        nh.exe --create $Using:SNATVeth["nh"] --vrf 0 --type 2 --el2 --oif $Using:SNATVeth["vif"]
        rt.exe -c -v 0 -f 1 -e $Using:SNATVeth["MacAddressColons"] -n $Using:SNATVeth["nh"]

        # Broadcast NH
        # TODO: Is this broadcast nexthop really needed?
        #nh.exe --create $Using:BroadcastNh --vrf 1 --type 6 --cen --cni $Using:ContainerNh --cni $Using:SNATLeftNh
    }
    Write-Host "Configure vRouter... DONE"
}