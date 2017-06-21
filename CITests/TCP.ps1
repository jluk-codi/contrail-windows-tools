function Test-TCP ([PSSession]$sess, [string]$adapter) {
    Invoke-Command -Session $sess -ScriptBlock {
        docker network create --ipam-driver windows --driver Contrail -o tenant=multi_host_ping_test -o network=testnet testnet

        $server_id = docker run --network testnet -d iis-tcptest; $server_id
        $client_id = docker run --network testnet -d microsoft/nanoserver ping -t localhost; $client_id

        $res = Get-NetAdapter $Using:adapter | Select Name,ifName,MacAddress,ifIndex
        $vm_mac = $res.MacAddress.Replace("-", ":").ToLower(); $vm_mac
        $vm_ifName = $res.ifName; $vm_ifName

        $server_adapter_fullname = docker exec $server_id powershell "(Get-NetAdapter -Name *Container*)[0].Name"; $server_adapter_fullname
        $server_adapter_shortname = $server_adapter_fullname.Split("()")[1].Trim(); $server_adapter_shortname

        $client_adapter_fullname = docker exec $client_id powershell "(Get-NetAdapter -Name *Container*)[0].Name"; $client_adapter_fullname
        $client_adapter_shortname = $client_adapter_fullname.Split("()")[1].Trim(); $client_adapter_shortname

        $server_mac_win = docker exec $server_id powershell "(Get-NetAdapter -Name *Container*)[0].MacAddress.ToLower()"; $server_mac_win
        $server_mac = $server_mac_win.Replace("-", ":"); $server_mac

        $client_mac_win = docker exec $client_id powershell "(Get-NetAdapter -Name *Container*)[0].MacAddress.ToLower()"; $client_mac_win
        $client_mac = $client_mac_win.Replace("-", ":"); $client_mac

        vif.exe --add $vm_ifName --mac $vm_mac --vrf 0 --type physical
        vif.exe --add HNSTransparent --mac $vm_mac --vrf 0 --type vhost --xconnect $vm_ifName

        vif.exe --add $server_adapter_shortname --mac $server_mac --vrf 1 --type virtual --vif 1
        vif.exe --add $client_adapter_shortname --mac $client_mac --vrf 1 --type virtual --vif 2

        nh.exe --create 1 --vrf 1 --type 2 --el2 --oif 1
        nh.exe --create 2 --vrf 1 --type 2 --el2 --oif 2
        #nh.exe --create 3 --vrf 1 --type 6 --cen --cni 1 --cni 2 # TODO: Uncomment after SNAT merge

        #rt.exe -c -v 1 -f 1 -e ff:ff:ff:ff:ff:ff -n 3 # TODO: Uncomment after SNAT merge
        rt.exe -c -v 1 -f 1 -e $server_mac -n 1
        rt.exe -c -v 1 -f 1 -e $client_mac -n 2

        $server_IP = docker exec $server_id powershell "(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias vEthernet*).IPAddress"; $server_IP
        $client_IP = docker exec $client_id powershell "(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias vEthernet*).IPAddress"; $client_IP

        docker exec $server_id netsh interface ipv4 add neighbors $server_adapter_fullname $client_IP $client_mac_win
        docker exec $client_id netsh interface ipv4 add neighbors $client_adapter_fullname $server_IP $server_mac_win

        $test_succeeded = $TRUE

        try {
            $res = docker exec $client_id powershell "(Invoke-WebRequest -Uri http://${server_ip}:8080/).StatusCode"
            if ($res -ne 200) { $test_succeeded = $False }
        } catch {
            $test_succeeded = $False
        }

        if (-Not $test_succeeded) {
            Write-Host "TCP test failed!"
            exit 1
        }
    }
}
