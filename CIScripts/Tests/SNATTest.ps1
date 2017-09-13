class SNATConfiguration {
    [string] $EndhostIP;
    [string] $VethIP;
    [string] $GatewayIP;
    [string] $ContainerGatewayIP;
    [string] $EndhostUsername;
    [string] $EndhostPassword;
    [string] $DiskDir;
    [string] $DiskFileName;
    [string] $VMDir;
}

function Test-SNAT {
    Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
           [Parameter(Mandatory = $true)] [SNATConfiguration] $SNATConfiguration,
           [Parameter(Mandatory = $true)] [TestConfiguration] $TestConfiguration)

    function New-MgmtSwitch {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $MgmtSwitchName)

        Write-Output "Creating MGMT switch..."
        $OldSwitches = Invoke-Command -Session $Session -ScriptBlock {
            return Get-VMSwitch -Name $Using:MgmtSwitchName -ErrorAction SilentlyContinue
        }
        if ($OldSwitches) {
            throw "MGMT switch already exists."
        }

        Invoke-Command -Session $Session -ScriptBlock {
            New-VMSwitch -Name $Using:MgmtSwitchName -SwitchType Internal | Out-Null
        }

        Write-Output "Creating MGMT switch... DONE"
    }

    function Remove-MgmtSwitch {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $MgmtSwitchName)

        Write-Output "Removing MGMT switch..."

        Invoke-Command -Session $Session -ScriptBlock {
            return Remove-VMSwitch -Name $Using:MgmtSwitchName -Force
        }

        Write-Output "Removing MGMT switch... DONE"
    }

    function New-RoutingInterface {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $SwitchName,
               [Parameter(Mandatory = $true)] [string] $Name,
               [Parameter(Mandatory = $true)] [ipaddress] $IPAddress)

        Write-Output "Setting up veth for forwarding..."
        $SNATVeth = Invoke-Command -Session $Session -ScriptBlock {
            Add-VMNetworkAdapter -ManagementOS -SwitchName $Using:SwitchName -Name $Using:Name | Out-Null

            $VMAdapter = Get-VMNetworkAdapter -ManagementOS | Where-Object Name -EQ $Using:Name
            $MacAddress = $VMAdapter.MacAddress -replace '..(?!$)', '$&-'

            $NetAdapter = Get-NetAdapter | Where-Object Name -Match $Using:Name | Where-Object Status -EQ Up
            $NetAdapter | Remove-NetIPAddress -Confirm:$false | Out-Null
            $NetAdapter | New-NetIPAddress -IPAddress $Using:IPAddress | Out-Null

            return @{
                Name = $VMAdapter.Name;
                IfName = $NetAdapter.IfName;
                IfIndex = $NetAdapter.IfIndex;
                MacAddressWindows = $MacAddress;
                MacAddress = $MacAddress.Replace("-", ":");
            }
        }

        Write-Output "Setting up veth for forwarding... DONE"

        return $SNATVeth
    }

    function Remove-RoutingInterface {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $Name)

        Write-Output "Removing routing interface..."

        Invoke-Command -Session $Session -ScriptBlock {
            $NetAdapter = Get-NetAdapter | Where-Object Name -Match $Using:Name
            $NetAdapter | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            $NetAdapter | Disable-NetAdapter -Confirm:$false
            Remove-VMNetworkAdapter -ManagementOS -Name $Using:Name
        }

        Write-Output "Removing routing interface... DONE"
    }

    function New-SNATVM {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $VmDirectory,
               [Parameter(Mandatory = $true)] [string] $DiskPath,
               [Parameter(Mandatory = $true)] [string] $MgmtSwitchName,
               [Parameter(Mandatory = $true)] [string] $VRouterSwitchName,
               [Parameter(Mandatory = $true)] [string] $RightGW,
               [Parameter(Mandatory = $true)] [string] $LeftGW,
               [Parameter(Mandatory = $true)] [string] $ForwardingMAC,
               [Parameter(Mandatory = $true)] [string] $GUID)

        # TODO: Remove `forwarding-mac` when Agent is functional
        Write-Output "Run vrouter_hyperv.py to provision SNAT VM..."
        $Res = Invoke-Command -Session $Session -ScriptBlock {
            python "C:\Program Files\Juniper Networks\Agent\vrouter_hyperv.py" create `
                --vm_location $Using:VmDirectory `
                --vhd_path $Using:DiskPath `
                --mgmt_vswitch_name $Using:MgmtSwitchName `
                --vrouter_vswitch_name $Using:VRouterSwitchName `
                --right-gw-cidr $Using:RightGW/24 `
                --left-gw-cidr $Using:LeftGW/24 `
                --forwarding-mac $Using:ForwardingMAC `
                $Using:GUID `
                $Using:GUID `
                $Using:GUID | Out-Null

            return $LASTEXITCODE
        }

        if ($Res -ne 0) {
            throw "Run vrouter_hyperv.py to provision SNAT VM... FAILED"
        }

        Write-Output "Run vrouter_hyperv.py to provision SNAT VM... DONE"
    }

    function Remove-SNATVM {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $DiskPath,
               [Parameter(Mandatory = $true)] [string] $GUID)

        Write-Output "Run vrouter_hyperv.py to remove SNAT VM..."
        $Res = Invoke-Command -Session $Session -ScriptBlock {
            python "C:\Program Files\Juniper Networks\Agent\vrouter_hyperv.py" destroy `
                --vhd_path $Using:DiskPath `
                $Using:GUID `
                $Using:GUID `
                $Using:GUID | Out-Null

            return $LASTEXITCODE
        }

        if ($Res -ne 0) {
            throw "Run vrouter_hyperv.py to remove SNAT VM... FAILED"
        }

        Write-Output "Run vrouter_hyperv.py to remove SNAT VM... DONE"
    }

    function Set-EndhostConfiguration {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $PhysicalMac,
               [Parameter(Mandatory = $true)] [string] $EndhostIP,
               [Parameter(Mandatory = $true)] [string] $GatewayIP,
               [Parameter(Mandatory = $true)] [string] $EndhostUsername,
               [Parameter(Mandatory = $true)] [string] $EndhostPassword)

        Write-Output "Configure endhost..."

        $EndhostSecurePassword = ConvertTo-SecureString $EndhostPassword -AsPlainText -Force
        $EndhostCredentials = New-Object System.Management.Automation.PSCredential($EndhostUsername, $EndhostSecurePassword)
        Invoke-Command -Session $Session -ScriptBlock {
            $EndhostSession = New-SSHSession -IPAddress $Using:EndhostIP -Credential $Using:EndhostCredentials -AcceptKey
            Invoke-SSHCommand -SessionId $EndhostSession.SessionId `
                -Command "echo $Using:EndhostPassword | sudo -S arp -i eth0 -s $Using:GatewayIP $Using:PhysicalMac" | Out-Null
        }

        Write-Output "Configure endhost... DONE"
    }

    function Set-VRouterConfiguration {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [NetAdapterInformation] $PhysicalAdapter,
               [Parameter(Mandatory = $true)] [NetAdapterInformation] $VHostAdapter,
               [Parameter(Mandatory = $true)] [ContainerNetAdapterInformation] $ContainerAdapter,
               [Parameter(Mandatory = $true)] [VMNetAdapterInformation] $SNATLeft,
               [Parameter(Mandatory = $true)] [VMNetAdapterInformation] $SNATRight,
               [Parameter(Mandatory = $true)] $SNATVeth)

        Write-Output "Configure vRouter..."

        $InternalVrf = 1
        $ExternalVrf = 2

        $ContainerVif = 101
        $ContainerNh = 101

        $SNATLeftVif = 102
        $SNATLeftNh = 102

        $SNATRightVif = 103
        $SNATRightNh = 103

        $SNATVethVif = 104
        $SNATVethNh = 104

        $BroadcastInternalNh = 110
        $BroadcastExternalNh = 111

        Write-Output "Proceeding to configure adapters"

        Invoke-Command -Session $Session -ScriptBlock {
            # Register physical adapter in Contrail
            Write-Output "Configuring physical and vHost adapters"
            vif --add $Using:PhysicalAdapter.IfName --mac $Using:PhysicalAdapter.MacAddress --vrf 0 --type physical
            vif --add $Using:VHostAdapter.IfName --mac $Using:VHostAdapter.MacAddress --vrf 0 --type vhost --xconnect $Using:PhysicalAdapter.IfName

            # Register container's NIC as vif
            Write-Output "Configuring NIC adapter"
            vif --add $Using:ContainerAdapter.IfName --mac $Using:ContainerAdapter.MacAddress --vrf $Using:InternalVrf --type virtual
            nh --create $Using:ContainerNh --vrf $Using:InternalVrf --type 2 --el2 --oif $Using:ContainerAdapter.ifIndex
            rt -c -v $Using:InternalVrf -f 1 -e $Using:ContainerAdapter.MacAddress -n $Using:ContainerNh

            # Register SNAT's left adapter ("int")
            Write-Output "Configuring int adapter"
            vif --add "int" --mac $Using:SNATLeft.MacAddress --vrf $Using:InternalVrf --type virtual --guid $Using:SNatLeft.GUID --vif $Using:SNATLeftVif
            nh --create $Using:SNATLeftNh --vrf $Using:InternalVrf --type 2 --el2 --oif $Using:SNATLeftVif
            rt -c -v $Using:InternalVrf -f 1 -e $Using:SNATLeft.MacAddress -n $Using:SNATLeftNh

            # Register SNAT's right adapter ("gw")
            Write-Output "Configuring gw adapter"
            vif --add "gw" --mac $Using:SNATRight.MacAddress --vrf $Using:ExternalVrf --type virtual --guid $Using:SNATRight.GUID --vif $Using:SNATRightVif
            nh --create $Using:SNATRightNh --vrf $Using:ExternalVrf --type 2 --el2 --oif $Using:SNATRightVif
            rt -c -v $Using:ExternalVrf -f 1 -e $Using:SNATRight.MacAddress -n $Using:SNATRightNh

            # Register SNAT's additional adapter ("veth")
            Write-Output "Configuring veth adapter"
            vif --add $Using:SNATVeth.ifName --mac $Using:SNATVeth.MacAddress --vrf $Using:ExternalVrf --type virtual
            nh --create $Using:SNATVethNh --vrf $Using:ExternalVrf --type 2 --el2 --oif $Using:SNATVeth.ifIndex
            rt -c -v $Using:ExternalVrf -f 1 -e $Using:SNATVeth.MacAddress -n $Using:SNATVethNh

            # Broadcast NH (internal network)
            Write-Output "Configuring broadcast (internal)"
            nh --create $Using:BroadcastInternalNh --vrf $Using:InternalVrf --type 6 --cen --cni $Using:ContainerNH --cni $Using:SNATLeftNh
            rt -c -v $Using:InternalVrf -f 1 -e ff:ff:ff:ff:ff:ff -n $Using:BroadcastInternalNh

            # Broadcast NH (external network)
            Write-Output "Configuring broadcast (external)"
            nh --create $Using:BroadcastExternalNh --vrf $Using:ExternalVrf --type 6 --cen --cni $Using:SNATRightNh --cni $Using:SNATVethNh
            rt -c -v $Using:ExternalVrf -f 1 -e ff:ff:ff:ff:ff:ff -n $Using:BroadcastExternalNh
        }

        Write-Output "Configure vRouter... DONE"
    }

    function Set-RoutingRules {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $GatewayIP,
               [Parameter(Mandatory = $true)] [string] $VethIP,
               [Parameter(Mandatory = $true)] [int] $SNATVethIfIndex)

        Write-Output "Setting up routing rules..."

        $Res = Invoke-Command -Session $Session -ScriptBlock {
            route add $Using:GatewayIP mask 255.255.255.255 $Using:VethIP "if" $Using:SNATVethIfIndex | Out-Null
            $LASTEXITCODE
        }

        if ($Res -ne 0) {
            throw "Setting up routing rules... FAILED"
        }

        Write-Output "Setting up routing rules... DONE"
    }

    function Set-GWVethForwarding {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [int] $SNATVethIfIndex,
               [Parameter(Mandatory = $true)] [string] $GatewayIP,
               [Parameter(Mandatory = $true)] [string] $SNATRightMacAddressWindows)

        Write-Output "Setting up ARP rule for GW-veth forwarding..."

        $Res = Invoke-Command -Session $Session -ScriptBlock {
            netsh interface ipv4 add neighbor $Using:SNATVethIfIndex $Using:GatewayIP $Using:SNATRightMacAddressWindows | Out-Null
            $LASTEXITCODE
        }

        if ($Res -ne 0) {
            throw "Setting up ARP rule for GW-veth forwarding... FAILED"
        }

        Write-Output "Setting up ARP rule for GW-veth forwarding... DONE"
    }

    function Set-HNSTransparentForwarding {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [int] $HNSAdapterIfIndex)

        Write-Output "Enable forwarding on the HNSTransparent adapter..."

        $Res = Invoke-Command -Session $Session -ScriptBlock {
            netsh interface ipv4 set interface $Using:HNSAdapterIfIndex forwarding="enabled" | Out-Null
            $LASTEXITCODE
        }

        if ($Res -ne 0) {
            throw "Enable forwarding on the HNSTransparent adapter... FAILED"
        }

        Write-Output "Enable forwarding on the HNSTransparent adapter... DONE"
    }

    function Test-VMAShouldBeCleanedUp {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $VmName)

        Write-Output "Checking if VM was cleaned up..."
        $VM = Invoke-Command -Session $Session -ScriptBlock {
            return Get-VM $Using:VmName -ErrorAction SilentlyContinue
        }

        if($VM) {
            throw "===> SNAT VM was not properly cleaned up! Test FAILED"
        }

        Write-Output "===> SNAV VM was properly cleaned up! Test succeeded"
    }

    function Test-VHDXShouldBeCleanedUp {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $DiskDir,
               [Parameter(Mandatory = $true)] [string] $GUID)

        Write-Output "Checking if VHDX was cleaned up..."
        $VM = Invoke-Command -Session $Session -ScriptBlock {
            return Get-ChildItem $Using:DiskDir\*$Using:GUID*
        }

        if($VM) {
            throw "===> SNAT VHDX was not properly cleaned up! Test FAILED"
        }

        Write-Output "===> SNAT VHDX was properly cleaned up! Test succeeded"
    }

    function Test-CanPingEndhostFromContainer {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $ContainerID,
               [Parameter(Mandatory = $true)] [string] $EndhostIP)

        $Res = Invoke-Command -Session $Session -ScriptBlock {
            docker exec $Using:ContainerID ping $Using:EndhostIP | Write-Output
            $LASTEXITCODE
        }
        if ($Res -ne 0) {
            throw "===> SNAT test failed"
        }
    }

    Write-Output "===> Running Simple SNAT test"

    Initialize-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    . $PSScriptRoot\CommonTestCode.ps1

    # SNAT VM options
    $SNATMgmtSwitchName = "snat-mgmt"
    $SNATDiskPath = $SNATConfiguration.DiskDir + "\" + $SNATConfiguration.DiskFileName

    # Some random GUID for vrouter_hyperv.py
    $NameLen = 14
    $SNAT_GUID = [guid]::NewGuid().Guid
    $SNATVMName = "contrail-wingw-$SNAT_GUID"
    $SNATLeftName = "int-$SNAT_GUID".Substring(0, $NameLen)
    $SNATRightName = "gw-$SNAT_GUID".Substring(0, $NameLen)
    $SNATVethName = "veth-$SNAT_GUID".Substring(0, $NameLen)

    New-MgmtSwitch -Session $Session -MgmtSwitchName $SNATMgmtSwitchName

    $SNATVeth = New-RoutingInterface -Session $Session `
        -SwitchName $TestConfiguration.VMSwitchName `
        -Name $SNATVethName `
        -IPAddress $SNATConfiguration.VethIP

    # TODO: JW-976: Remove `ForwardingMAC` when Agent is functional
    New-SNATVM -Session $Session `
        -VmDirectory $SNATConfiguration.VMDir -DiskPath $SNATDiskPath `
        -MgmtSwitchName $SNATMgmtSwitchName `
        -VRouterSwitchName $TestConfiguration.VMSwitchName `
        -RightGW $SNATConfiguration.GatewayIP `
        -LeftGW $SNATConfiguration.ContainerGatewayIP `
        -ForwardingMAC $SNATVeth.MacAddress `
        -GUID $SNAT_GUID

    Write-Output "Extracting adapters data..."
    $PhysicalAdapter = Get-RemoteNetAdapterInformation -Session $Session -AdapterName $TestConfiguration.AdapterName
    $VHostAdapter = Get-RemoteNetAdapterInformation -Session $Session -AdapterName $TestConfiguration.VHostName
    $HNSAdapter = Get-RemoteNetAdapterInformation -Session $Session -AdapterName $TestConfiguration.VHostName
    $SNATLeft = Get-RemoteVMNetAdapterInformation -Session $Session -AdapterName $SNATLeftName -VMName $SNATVMName
    $SNATRight = Get-RemoteVMNetAdapterInformation -Session $Session -AdapterName $SNATRightName -VMName $SNATVMName
    Write-Output "Extracting adapters data... DONE"

    # TODO: JW-976: Remove `Set-GWVethForwarding` and `Set-HNSTransparentForwarding` when Agent is functional?
    Set-RoutingRules -Session $Session -GatewayIP $SNATConfiguration.GatewayIP -VethIP $SNATConfiguration.VethIP -SNATVethIfIndex $SNATVeth.IfIndex
    Set-GWVethForwarding -Session $Session -SNATVethIfIndex $SNATVeth.IfIndex -GatewayIP $SNATConfiguration.GatewayIP -SNATRightMacAddressWindows $SNATRight.MacAddressWindows
    Set-HNSTransparentForwarding -Session $Session -HNSAdapterIfIndex $HNSAdapter.IfIndex

    Write-Output "Start and configure test container..."
    $DockerNetwork = $TestConfiguration.DockerDriverConfiguration.NetworkConfiguration.NetworkName
    $ContainerID = Invoke-Command -Session $Session -ScriptBlock { docker run -id --network $Using:DockerNetwork microsoft/nanoserver powershell }
    $ContainerNetInfo = Get-RemoteContainerNetAdapterInformation -Session $Session -ContainerID $ContainerID
    Write-Output "Start and configure test container... DONE"

    Set-VRouterConfiguration -Session $Session -PhysicalAdapter $PhysicalAdapter -VHostAdapter $VHostAdapter `
        -ContainerAdapter $ContainerNetInfo -SNATLeft $SNATLeft -SNATRight $SNATRight -SNATVeth $SNATVeth

    Set-EndhostConfiguration -Session $Session -PhysicalMac $PhysicalAdapter.MacAddress `
        -EndhostIP $SNATConfiguration.EndhostIP -GatewayIP $SNATConfiguration.GatewayIP `
        -EndhostUsername $SNATConfiguration.EndhostUsername -EndhostPassword $SNATConfiguration.EndhostPassword

    Test-CanPingEndhostFromContainer -Session $Session -ContainerID $ContainerID -EndhostIP $SNATConfiguration.EndhostIP

    Invoke-Command -Session $Session -ScriptBlock { docker rm -f $Using:ContainerID } | Out-Null

    Remove-SNATVM -Session $Session -DiskPath $SNATDiskPath -GUID $SNAT_GUID
    Remove-RoutingInterface -Session $Session -Name $SNATVethName
    Remove-MgmtSwitch -Session $Session -MgmtSwitchName $SNATMgmtSwitchName

    Test-VMAShouldBeCleanedUp -VMName $SNATVMName -Session $Session
    Test-VHDXShouldBeCleanedUp -GUID $SNAT_GUID -DiskDir $SNATConfiguration.DiskDir -Session $Session

    Clear-TestConfiguration -Session $Session -TestConfiguration $TestConfiguration

    Write-Output "===> Success"
}
