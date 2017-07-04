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


    function New-RoutingInterface {
        Param (
            [Parameter(Mandatory=$true)][System.Management.Automation.Runspaces.PSSession] $Session,
            [Parameter(Mandatory=$true)][string]$SwitchName,
            [Parameter(Mandatory=$true)][string]$Name,
            [Parameter(Mandatory=$true)][ipaddress]$IPAddress
        )

        Write-Host "Setting up veth for forwarding..."
        $SNATVeth = Invoke-Command -Session $Session -ScriptBlock {
            Add-VMNetworkAdapter -ManagementOS -SwitchName $Using:SwitchName -Name $Using:Name | Out-Null

            $vmAdapter = Get-VMNetworkAdapter -ManagementOS | Where-Object Name -eq $Using:Name
            $macAddress = $vmAdapter.MacAddress -replace '..(?!$)', '$&-'

            $netAdapter = Get-NetAdapter | Where-Object Name -match $Using:Name
            $netAdapter | Remove-NetIPAddress -Confirm:$false | Out-Null
            $netAdapter | New-NetIPAddress -IPAddress $Using:IPAddress | Out-Null

            @{ `
                "Name" = $vmAdapter.Name; `
                "MacAddressDashed" = $macAddress; `
                "MacAddressColons" = $macAddress.replace("-", ":"); `
                "IfIndex" = $netAdapter.ifIndex; `
            }
        }
        $SNATVeth.Set_Item("vif", 104)
        $SNATVeth.Set_Item("nh", 104)
        Write-Host "Setting up veth for forwarding... DONE"

        $SNATVeth
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
            [Parameter(Mandatory=$true)][string] $ForwardingMAC,
            [Parameter(Mandatory=$true)][string] $GUID
        )

        # TODO: Remove `forwarding-mac` when Agent is functional
        Write-Host "Run vrouter_hyperv.py to provision SNAT VM..."
        $exitCode = Invoke-Command -Session $Session -ScriptBlock {
            python C:\snat-test\vrouter_hyperv.py create `
                --vm_location $Using:VmDirectory `
                --vhd_path $Using:DiskPath `
                --mgmt_vswitch_name $Using:MgmtSwitchName `
                --vrouter_vswitch_name $Using:VRouterSwitchName `
                --right-gw-cidr $Using:RightGW/24 `
                --left-gw-cidr $Using:LeftGW/24 `
                --forwarding-mac $Using:ForwardingMAC `
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

    $CONTAINER_GW = "10.0.0.1"
    $SNAT_GATEWAY_IP = "10.7.3.200"
    $SNAT_VETH_IP = "10.7.3.210"

    $DOCKER_NETWORK = "testnet"

    Restore-CleanTestConfiguration -sess $session -adapter $PhysicalAdapterName -testConfiguration $testConfiguration

    New-MgmtSwitch -Session $Session -MgmtSwitchName $SNAT_MGMT_SWITCH

    $SNATVeth = New-RoutingInterface -Session $Session `
        -SwitchName $VRouterSwitchName `
        -Name $SNAT_VETH_NAME `
        -IPAddress $SNAT_VETH_IP

    # TODO: Remove `ForwardingMAC` when Agent is functional
    New-SNATVM -Session $Session `
        -VmDirectory $SNAT_VM_DIR -DiskPath $SNAT_DISK_PATH `
        -MgmtSwitchName $SNAT_MGMT_SWITCH `
        -VRouterSwitchName $VRouterSwitchName `
        -RightGW $SNAT_GATEWAY_IP `
        -LeftGW $CONTAINER_GW `
        -ForwardingMAC $SNATVeth["MacAddressColons"] `
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


    Write-Host "Setting up routing rules..."
    $routeExitCode = Invoke-Command -Session $Session -ScriptBlock {
        route add $Using:SNAT_GATEWAY_IP mask 255.255.255.255 $Using:SNAT_VETH_IP "if" $Using:SNATVeth["IfIndex"] | Out-Null
    }
    Write-Host "Setting up routing rules... exitCode = $routeExitCode"
    Write-Host "Setting up routing rules... DONE"


    Write-Host "Setting up ARP rule for GW-veth forwarding..."
    Invoke-Command -Session $Session -ScriptBlock {
        netsh interface ipv4 add neighbor $Using:SNATVeth["IfIndex"] $Using:SNAT_GATEWAY_IP $Using:SnatRight["MacAddressDashed"]
    }
    Write-Host "Setting up ARP rule for GW-veth forwarding... DONE"


    Write-Host "Enable forwarding on the HNSTransparent adapter..."
    Invoke-Command -Session $Session -ScriptBlock {
        netsh interface ipv4 set interface $Using:HNSAdapter["IfIndex"] forwarding="enabled" | Out-Null
    }
    Write-Host "Enable forwarding on the HNSTransparent adapter... DONE"


    Write-Host "Start and configure test container..."
    $Container = Invoke-Command -Session $Session -ScriptBlock {
        $Id = $(docker run -id --network $Using:DOCKER_NETWORK microsoft/nanoserver powershell)

        $AdapterName = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty Name")
        $AdapterName = $AdapterName -replace 'vEthernet \((.*)\)', '$1'
        $MacAddress = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty MacAddress")
        $IfIndex = $(docker exec $Id powershell "Get-NetAdapter | Select -ExpandProperty IfIndex")

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


    $InternalVrf = 1
    $ExternalVrf = 2

    $BroadcastInternalNh = 110
    $BroadcastExternalNh = 111

    Write-Host "Configure vRouter..."
    Invoke-Command -Session $Session -ScriptBlock {
        $Env:PATH = "C:\Utils\;$Env:PATH"

        # Register physical adapter in Contrail
        vif.exe --add $Using:PhysicalAdapter["IfName"] --mac $Using:PhysicalAdapter["MacAddressColons"] --vrf 0 --type physical
        vif.exe --add HNSTransparent --mac $Using:PhysicalAdapter["MacAddressColons"] --vrf 0 --type vhost --xconnect $Using:PhysicalAdapter["IfName"]

        # Register container's NIC as vif
        vif.exe --add $Using:Container["AdapterName"] --mac $Using:Container["MacAddressColons"] --vrf $Using:InternalVrf --type virtual --vif $Using:Container["vif"]
        nh.exe --create $Using:Container["nh"] --vrf $Using:InternalVrf --type 2 --el2 --oif $Using:Container["vif"]
        rt.exe -c -v $Using:InternalVrf -f 1 -e $Using:Container["MacAddressColons"] -n $Using:Container["nh"]

        # Register SNAT's left adapter ("int")
        vif.exe --add $Using:SNATLeft["Name"] --mac $Using:SNATLeft["MacAddressColons"] --vrf $Using:InternalVrf --type virtual --vif $Using:SNATLeft["vif"]
        nh.exe --create $Using:SNATLeft["nh"] --vrf $Using:InternalVrf --type 2 --el2 --oif $Using:SNATLeft["vif"]
        rt.exe -c -v $Using:InternalVrf -f 1 -e $Using:SNATLeft["MacAddressColons"] -n $Using:SNATLeft["nh"]

        # Register SNAT's right adapter ("gw")
        vif.exe --add $Using:SNATRight["Name"] --mac $Using:SNATRight["MacAddressColons"] --vrf $Using:ExternalVrf --type virtual --vif $Using:SNATRight["vif"]
        nh.exe --create $Using:SNATRight["nh"] --vrf $Using:ExternalVrf --type 2 --el2 --oif $Using:SNATRight["vif"]
        rt.exe -c -v $Using:ExternalVrf -f 1 -e $Using:SNATRight["MacAddressColons"] -n $Using:SNATRight["nh"]

        # Register SNAT''s additional adapter ("veth")
        vif.exe --add $Using:SNATVeth["Name"] --mac $Using:SNATVeth["MacAddressColons"] --vrf $Using:ExternalVrf --type virtual --vif $Using:SNATVeth["vif"]
        nh.exe --create $Using:SNATVeth["nh"] --vrf $Using:ExternalVrf --type 2 --el2 --oif $Using:SNATVeth["vif"]
        rt.exe -c -v $Using:ExternalVrf -f 1 -e $Using:SNATVeth["MacAddressColons"] -n $Using:SNATVeth["nh"]

        # Broadcast NH (internal network)
        nh.exe --create $Using:BroadcastInternalNh --vrf $Using:InternalVrf --type 6 --cen --cni $Using:Container["nh"] --cni $Using:SNATLeft["nh"]
        rt.exe -c -v $Using:InternalVrf -f 1 -e ff:ff:ff:ff:ff:ff -n $Using:BroadcastInternalNh

        # Broadcast NH (external network)
        nh.exe --create $Using:BroadcastExternalNh --vrf $Using:ExternalVrf --type 6 --cen --cni $Using:SNATRight["nh"] --cni $Using:SNATVeth["nh"]
        rt.exe -c -v $Using:ExternalVrf -f 1 -e ff:ff:ff:ff:ff:ff -n $Using:BroadcastExternalNh
    }
    Write-Host "Configure vRouter... DONE"

    Write-Host "Installing Posh-SSH..."
    Invoke-Command -Session $Session -ScriptBlock {
        Install-Module -Repository PSGallery -Force -Confirm:$false PoSH-SSH
    }
    Write-Host "Installing Posh-SSH... DONE"


    Write-Host "Configure endhost..."
    $physicalMAC = $PhysicalAdapter["MacAddressColons"]

    $username = "ubuntu"
    $password = "ubuntu"

    $endhostPassword = ConvertTo-SecureString $password -AsPlainText -Force
    $endhostCredentials = New-Object System.Management.Automation.PSCredential($username, $endhostPassword)
    Invoke-Command -Session $Session -ScriptBlock {
        $endhostSession = New-SSHSession -IPAddress 10.7.3.10 -Credential $Using:endhostCredentials -AcceptKey
        Invoke-SSHCommand -SessionId $endhostSession.SessionId `
            -Command "echo $Using:password | sudo -S arp -i eth0 -s $Using:SNAT_GATEWAY_IP $Using:physicalMAC" | Out-Null
    }
    Write-Host "Configure endhost... DONE"

    $Res = Invoke-Command -Session $Session -ScriptBlock {
        docker exec $Using:Container["Id"] ping 10.7.3.10 | Write-Host
        $LASTEXITCODE
    }
    if ($Res -ne 0) {
        Write-Host "SNAT test failed"
        exit 1
    }

    Remove-SNATVM -Session $Session `
        -DiskPath $SNAT_DISK_PATH `
        -GUID $SNAT_GUID

    Test-VMAShouldBeCleanedUp -VMName $SNAT_VM_NAME -Session $Session
    Test-VHDXShouldBeCleanedUp -GUID $SNAT_GUID -DiskDir $SNAT_DISK_DIR -Session $Session
}
