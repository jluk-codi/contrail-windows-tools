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
        $VRouterSwitchName,

        $testConfiguration
    )


    function New-MgmtSwitch {
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
            Get-VMSwitch | Where-Object Name -eq $Using:MgmtSwitchName
        }
        if ($oldSwitches) {
            Write-Host "MGMT switch already exists. Won't create a new one."
            return
        }

        $newVmSwitch = Invoke-Command -Session $Session -ScriptBlock {
            New-VMSwitch -Name $Using:MgmtSwitchName -SwitchType Internal
        }
        if (!$newVmSwitch) {
            Throw "Failed to create MGMT switch"
        }

        Write-Host "Creating MGMT switch... DONE"
    }


    function New-SNATVM {
        Param (
            [Parameter(Mandatory=$true)][System.Management.Automation.Runspaces.PSSession] $Session,
            [Parameter(Mandatory=$true)][string] $VmDirectory,
            [Parameter(Mandatory=$true)][string] $DiskPath,
            [Parameter(Mandatory=$true)][string] $MgmtSwitchName,
            [Parameter(Mandatory=$true)][string] $VRouterSwitchName,
            [Parameter(Mandatory=$true)][string] $RightGW,
            [Parameter(Mandatory=$true)][string] $LeftGW,
            [Parameter(Mandatory=$true)][string] $GUID
        )

        Write-Host "Run vrouter_hyperv.py to provision SNAT VM..."
        $stdout = Invoke-Command -Session $Session -ScriptBlock {
            # TODO(sodar): Add from _gw_ to _veth_ 
            python C:\snat-test\vrouter_hyperv.py create `
                --vm_location $Using:VmDirectory `
                --vhd_path $Using:DiskPath `
                --mgmt_vswitch_name $Using:MgmtSwitchName `
                --vrouter_vswitch_name $Using:VRouterSwitchName `
                --right-gw-cidr $Using:RightGW/24 `
                --left-gw-cidr $Using:LeftGW/24 `
                $Using:GUID `
                $Using:GUID `
                $Using:GUID
        }
        Write-Host $stdout

        $exitCode = Invoke-Command -Session $Session -ScriptBlock {
            $LASTEXITCODE
        }

        Write-Host "Run vrouter_hyperv.py to provision SNAT VM... exitCode = $exitCode;"
        if ($exitCode -eq 0) {
            Write-Host "Run vrouter_hyperv.py to provision SNAT VM... DONE"
        } else {
            Throw "Run vrouter_hyperv.py to provision SNAT VM... FAILED"
        }
    }

    function Remove-SNATVM {
        Param (
            [Parameter(Mandatory=$true)][System.Management.Automation.Runspaces.PSSession] $Session,
            [Parameter(Mandatory=$true)][string] $DiskPath,
            [Parameter(Mandatory=$true)][string] $GUID
        )

        Write-Host "Run vrouter_hyperv.py to remove SNAT VM..."
        $exitCode = Invoke-Command -Session $Session -ScriptBlock {
            python C:\snat-test\vrouter_hyperv.py destroy `
                --vhd_path $Using:DiskPath `
                $Using:GUID `
                $Using:GUID `
                $Using:GUID | Out-Null
            
            $LASTEXITCODE
        }

        Write-Host "Run vrouter_hyperv.py to remove SNAT VM... exitCode = $exitCode;"
        if ($exitCode -eq 0) {
            Write-Host "Run vrouter_hyperv.py to remove SNAT VM... DONE"
        } else {
            Throw "Run vrouter_hyperv.py to remove SNAT VM... FAILED"
        }
    }

    function Test-VMAShouldBeCleanedUp {
        Param (
            [Parameter(Mandatory=$true)][System.Management.Automation.Runspaces.PSSession] $Session,
            [Parameter(Mandatory=$true)][string] $VmName
        )

        Write-Host "Checking if VM was cleaned up..."
        $vm = Invoke-Command -Session $Session -ScriptBlock {
            Get-VM $Using:VmName
        }
        if($vm -eq $null) {
            Write-Host "SNAV VM was properly cleaned up! Test succeeded"
        } else {
            Throw "SNAT VM was not properly cleaned up! Test FAILED"
        }
    }

    function Test-VHDXShouldBeCleanedUp {
        Param (
            [Parameter(Mandatory=$true)][System.Management.Automation.Runspaces.PSSession] $Session,
            [Parameter(Mandatory=$true)][string] $DiskDir,
            [Parameter(Mandatory=$true)][string] $GUID
        )

        Write-Host "Checking if VHDX was cleaned up..."
        $vm = Invoke-Command -Session $Session -ScriptBlock {
            Get-ChildItem $Using:DiskDir\*$Using:GUID*
        }
        if($vm -eq $null) {
            Write-Host "SNAV VHDX was properly cleaned up! Test succeeded"
        } else {
            Throw "SNAT VHDX was not properly cleaned up! Test FAILED"
        }
    }


    # SNAT VM options
    $SNAT_MGMT_SWITCH = "snat-mgmt"
    #$SNAT_MGMT_ADAPTER = $SNAT_MGMT_SWITCH
    $SNAT_DISK_DIR = "C:\snat-vm-image"
    $SNAT_DISK_PATH = $SNAT_DISK_DIR + "\snat-vm-image.vhdx"
    $SNAT_VM_DIR = "C:\snat-vm"

    # Some random GUID for vrouter_hyperv.py
    $NAME_LEN = 14
    $SNAT_GUID = "d8cf77cb-b9b1-4d7d-ad3c-ef54f417cb5f"
    $SNAT_VM_NAME = "contrail-wingw-$SNAT_GUID"
    $SNAT_LEFT_NAME = "int-$SNAT_GUID".Substring(0, $NAME_LEN)
    $SNAT_RIGHT_NAME = "gw-$SNAT_GUID".Substring(0, $NAME_LEN)
    $SNAT_VETH_NAME = "veth-$SNAT_GUID".Substring(0, $NAME_LEN)
    $SNAT_GATEWAY_IP = "10.7.3.200"

    # Container config
    $DOCKER_NETWORK = "testnet"
    $CONTAINER_GW = "10.0.0.1"

    Restore-CleanTestConfiguration -sess $session -adapter $PhysicalAdapterName -testConfiguration $testConfiguration

    New-MgmtSwitch -Session $Session -MgmtSwitchName $SNAT_MGMT_SWITCH

    New-SNATVM -Session $Session `
        -VmDirectory $SNAT_VM_DIR -DiskPath $SNAT_DISK_PATH `
        -MgmtSwitchName $SNAT_MGMT_SWITCH `
        -VRouterSwitchName $VRouterSwitchName `
        -RightGW $SNAT_GATEWAY_IP `
        -LeftGW $CONTAINER_GW `
        -GUID $SNAT_GUID


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


    Write-Host "Extracting HNSTransparent adapter data..."
    $HNSAdapter = Invoke-Command -Session $Session -ScriptBlock {
        $adapter = Get-NetAdapter | Where-Object Name -Match "HNSTransparent" | Select-Object Name,IfName,IfIndex,MacAddress

        @{ `
            "Name" = $adapter.Name; `
            "IfName" = $adapter.IfName; `
            "IfIndex" = $adapter.IfIndex; `
            "MacAddressDashed" = $adapter.MacAddress; `
            "MacAddressColons" = $adapter.MacAddress.replace("-", ":"); `
        }
    }
    Write-Host "Extracting HNSTransparent adapter data... DONE"


    Write-Host "Extracting VM left adapter data..."
    $SNATLeft = Invoke-Command -Session $Session -ScriptBlock {
        $vmName = ${Using:SNAT_VM_NAME}
        $adapterName = ${Using:SNAT_LEFT_NAME}
        $macAddress = Get-VMNetworkAdapter -VMName $vmName -Name $adapterName | Select-Object -ExpandProperty MacAddress
        $macAddress = $macAddress -replace '..(?!$)', '$&-'

        @{ `
            "Name" = $adapterName; `
            "MacAddressDashed" = $macAddress; `
            "MacAddressColons" = $macAddress.replace("-", ":"); `
        }
    }
    $SNATLeft.Set_Item("vif", 102)
    $SNATLeft.Set_Item("nh", 102)
    Write-Host "Extracting VM left adapter data... DONE"


    Write-Host "Extracting VM right adapter data..."
    $SNATRight = Invoke-Command -Session $Session -ScriptBlock {
        $vmName = ${Using:SNAT_VM_NAME}
        $adapterName = ${Using:SNAT_RIGHT_NAME}
        $macAddress = Get-VMNetworkAdapter -VMName $vmName -Name $adapterName | Select-Object -ExpandProperty MacAddress
        $macAddress = $macAddress -replace '..(?!$)', '$&-'

        @{ `
            "Name" = $adapterName; `
            "MacAddressDashed" = $macAddress; `
            "MacAddressColons" = $macAddress.replace("-", ":"); `
        }
    }
    $SNATRight.Set_Item("vif", 103)
    $SNATRight.Set_Item("nh", 103)
    Write-Host "Extracting VM right adapter data... DONE"


    Write-Host "Setting up veth for forwarding..."
    $SNATVeth = Invoke-Command -Session $Session -ScriptBlock {
        Add-VMNetworkAdapter -ManagementOS -SwitchName $Using:VRouterSwitchName -Name $Using:SNAT_VETH_NAME | Out-Null

        $adapter = Get-VMNetworkAdapter -ManagementOS | Where-Object Name -eq $Using:SNAT_VETH_NAME
        $macAddress = $adapter.MacAddress -replace '..(?!$)', '$&-'

        @{ `
            "Name" = $adapter.Name; `
            "MacAddressDashed" = $macAddress; `
            "MacAddressColons" = $macAddress.replace("-", ":"); `
        }
    }
    $SNATVeth.Set_Item("vif", 104)
    $SNATVeth.Set_Item("nh", 104)
    Write-Host "Setting up veth for forwarding... DONE"


    Write-Host "Enable forwarding on the HNSTransparent adapter..."
    Invoke-Command -Session $Session -ScriptBlock {
        netsh interface ipv4 set interface $Using:HNSAdapter["IfIndex"] forwarding="enabled"
    }
    Write-Host "Enable forwarding on the HNSTransparent adapter... DONE"


    Write-Host "Start and configure test container..."
    $Container = Invoke-Command -Session $Session -ScriptBlock {
        $Id = $(docker run -id --network $Using:DOCKER_NETWORK microsoft/nanoserver powershell)

        $AdapterName = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty Name")
        $AdapterName = $AdapterName -replace 'vEthernet \((.*)\)', '$1'
        $MacAddress = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty MacAddress")
        $IfIndex = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty IfIndex")

        docker exec $Id netsh interface ipv4 add neighbors $IfIndex $Using:CONTAINER_GW $Using:SNATLeft["MacAddressDashed"] | Out-Null

        @{ `
            "Id" = $Id; `
            "AdapterName" = $AdapterName; `
            "MacAddressDashed" = $MacAddress; `
            "MacAddressColons" = $MacAddress.replace("-", ":"); `
            "IfIndex" = $IfIndex; `
        }
    }
    $Container.Set_Item("vif", 101)
    $Container.Set_Item("nh", 101)
    Write-Host "Start and configure test container... DONE"


    Write-Host "Configure vRouter..."
    Invoke-Command -Session $Session -ScriptBlock {
        $Env:PATH = "C:\Utils\;$Env:PATH"

        # Register physical adapter in Contrail
        vif.exe --add $Using:PhysicalAdapter["IfName"] --mac $Using:PhysicalAdapter["MacAddressColons"] --vrf 0 --type physical
        vif.exe --add HNSTransparent --mac $Using:PhysicalAdapter["MacAddressColons"] --vrf 0 --type vhost --xconnect $Using:PhysicalAdapter["IfName"]

        # Register container's NIC as vif
        vif.exe --add $Using:Container["AdapterName"] --mac $Using:Container["MacAddressColons"] --vrf 1 --type virtual --vif $Using:Container["vif"]
        nh.exe --create $Using:Container["nh"] --vrf 1 --type 2 --el2 --oif $Using:Container["vif"]
        rt.exe -c -v 1 -f 1 -e $Using:Container["MacAddressColons"] -n $Using:Container["nh"]

        # Register SNAT's left adapter ("int")
        vif.exe --add $Using:SNATLeft["Name"] --mac $Using:SNATLeft["MacAddressColons"] --vrf 1 --type virtual --vif $Using:SNATLeft["vif"]
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

    # TODO: Test-ShouldBeAbleToPingEndhostFromContainer -Container1
    # TODO: Test-ShouldBeAbleToPingEndhostFromContainer -DifferentContainerInSameSubnet

    $Res = Invoke-Command -Session $Session -ScriptBlock {
        docker exec $Using:Container["Id"] ping 10.7.3.10 | Write-Host
        $LASTEXITCODE
    }
    if ($Res -ne 0) {
        Write-Host "SNAT tet failed"
        exit 1
    }

    Remove-SNATVM -Session $Session `
        -DiskPath $SNAT_DISK_PATH `
        -GUID $SNAT_GUID

    Test-VMAShouldBeCleanedUp -VMName $SNAT_VM_NAME -Session $Session
    Test-VHDXShouldBeCleanedUp -GUID $SNAT_GUID -DiskDir $SNAT_DISK_DIR -Session $Session
}

. .\RestoreCleanTestConfiguration.ps1

$vmSwitchName = "Layered Ethernet1"
$forwardingExtensionName = "vRouter forwarding extension"

$ddrv_cfg = [pscustomobject] @{
    os_username = "admin"
    os_password = "secret123"
    os_auth_url = "http://10.7.0.54:5000/v2.0"
    os_controller_ip = "10.7.0.54"
    os_tenant_name = "admin"
}

$testConfiguration = [pscustomobject] @{
    dockerDriverCfg = $ddrv_cfg
    forwardingExtensionName = $forwardingExtensionName
    vmSwitchName = $vmSwitchName
}

$session = New-PSSession -ComputerName MK-snat
Copy-Item -ToSession $session  -Force `
    -Path C:\Users\mk\Source\Repos\controller\src\vnsw\opencontrail-vrouter-netns\opencontrail_vrouter_netns\* `
    -Destination C:\snat-test\
Test-SimpleSNAT -Session $session -PhysicalAdapterName Ethernet1 -VRouterSwitchName $vmSwitchName -testConfiguration $testConfiguration