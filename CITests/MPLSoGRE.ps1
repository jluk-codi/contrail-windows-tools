function Test-MPLSoGRE ([PSSession]$sess1, [PSSession]$sess2, [string]$adapterName) {
    Write-Host "Creating networks"
    Invoke-Command -Session $sess2 -ScriptBlock { docker network create --ipam-driver windows --driver Contrail -o tenant=multi_host_ping_test -o network=testnet testnet }
    Invoke-Command -Session $sess1 -ScriptBlock { docker network create --ipam-driver windows --driver Contrail -o tenant=multi_host_ping_test -o network=testnet testnet }
    
    Write-Host "Running containers"
    $container1_id = Invoke-Command -Session $sess1 -ScriptBlock { docker run --network testnet -d microsoft/nanoserver ping -t localhost }; $container1_id
    $container2_id = Invoke-Command -Session $sess2 -ScriptBlock { docker run --network testnet -d microsoft/nanoserver ping -t localhost }; $container2_id
    
    Write-Host "Getting MAC and ifName of VMs"
    $res1 = Invoke-Command -Session $sess1 -ScriptBlock { Get-NetAdapter $Using:adapter | Select Name,ifName,MacAddress,ifIndex }
    $res2 = Invoke-Command -Session $sess2 -ScriptBlock { Get-NetAdapter $Using:adapter | Select Name,ifName,MacAddress,ifIndex }
    
    $vm1_mac = $res1.MacAddress.Replace("-", ":").ToLower(); $vm1_mac
    $vm2_mac = $res2.MacAddress.Replace("-", ":").ToLower(); $vm2_mac
    
    $vm1_ifName = $res1.ifName; $vm1_ifName
    $vm2_ifName = $res2.ifName; $vm2_ifName
    
    Write-Host "Getting MAC and interface Names of Containers"
    $res1 = Invoke-Command -Session $sess1 -ScriptBlock { docker exec $Using:container1_id powershell "Get-NetAdapter | Select-Object Name,ifName,MacAddress | Format-List" }
    $res2 = Invoke-Command -Session $sess2 -ScriptBlock { docker exec $Using:container2_id powershell "Get-NetAdapter | Select-Object Name,ifName,MacAddress | Format-List" }
    
    $container1_mac_win = $res1[4].Split(":")[1].Trim().ToLower(); $container1_mac_win
    $container1_mac = $container1_mac_win.Replace("-", ":"); $container1_mac
    $container2_mac_win = $res2[4].Split(":")[1].Trim().ToLower(); $container2_mac_win
    $container2_mac = $container2_mac_win.Replace("-", ":"); $container2_mac
    
    $container1_iFullName = $res1[2].Split(":")[1].Trim(); $container1_iFullName # vEthernet (Container NIC 674e398e)
    $container1_iName = $container1_iFullName.Split("()")[1].Trim(); $container1_iName # Container NIC 674e398e
    $container2_iFullName = $res2[2].Split(":")[1].Trim(); $container2_iFullName
    $container2_iName = $container2_iFullName.Split("()")[1].Trim(); $container2_iName
    
    Write-Host "Creating vif #1"
    Invoke-Command -Session $sess1 -ScriptBlock { vif --add $Using:vm1_ifName --mac $Using:vm1_mac --vrf 0 --type physical }
    Invoke-Command -Session $sess2 -ScriptBlock { vif --add $Using:vm2_ifName --mac $Using:vm2_mac --vrf 0 --type physical }
    
    Write-Host "Creating vif #2"
    Invoke-Command -Session $sess1 -ScriptBlock { vif --add HNSTransparent --mac $Using:vm1_mac --vrf 0 --type vhost --xconnect $Using:vm1_ifName }
    Invoke-Command -Session $sess2 -ScriptBlock { vif --add HNSTransparent --mac $Using:vm2_mac --vrf 0 --type vhost --xconnect $Using:vm2_ifName }
    
    Write-Host "Creating vif #3"
    Invoke-Command -Session $sess1 -ScriptBlock { vif --add $Using:container1_iName --mac $Using:container1_mac --vrf 1 --type virtual --vif 1 }
    Invoke-Command -Session $sess2 -ScriptBlock { vif --add $Using:container2_iName --mac $Using:container2_mac --vrf 1 --type virtual --vif 1 }
    
    Write-Host "Getting vif id of physical adapter"
    $res1 = Invoke-Command -Session $sess1 -ScriptBlock { vif --list }
    $res2 = Invoke-Command -Session $sess2 -ScriptBlock { vif --list }
    
    $vm1_physical_vif = ($res1 -like "*ethernet_[0-9]*").Trim().Split()[0].Split("/")[1]; $vm1_physical_vif
    $vm2_physical_vif = ($res2 -like "*ethernet_[0-9]*").Trim().Split()[0].Split("/")[1]; $vm2_physical_vif
    
    Write-Host "Creating nh #1"
    Invoke-Command -Session $sess1 -ScriptBlock { nh --create 4 --vrf 0 --type 1 --oif 0 }
    Invoke-Command -Session $sess2 -ScriptBlock { nh --create 4 --vrf 0 --type 1 --oif 0 }
    
    Write-Host "Creating nh #2"
    Invoke-Command -Session $sess1 -ScriptBlock { nh --create 3 --vrf 1 --type 2 --el2 --oif 1 }
    Invoke-Command -Session $sess2 -ScriptBlock { nh --create 3 --vrf 1 --type 2 --el2 --oif 1 }
    
    Write-Host "Creating nh #3"
    Invoke-Command -Session $sess1 -ScriptBlock { nh --create 2 --vrf 0 --type 3 --oif $Using:vm1_physical_vif --dmac $Using:vm2_mac --smac $Using:vm1_mac --dip 192.168.3.102 --sip 192.168.3.101 }
    Invoke-Command -Session $sess2 -ScriptBlock { nh --create 2 --vrf 0 --type 3 --oif $Using:vm2_physical_vif --dmac $Using:vm1_mac --smac $Using:vm2_mac --dip 192.168.3.101 --sip 192.168.3.102 }
    
    Write-Host "Creating mpls"
    Invoke-Command -Session $sess1 -ScriptBlock { mpls --create 10 --nh 3 }
    Invoke-Command -Session $sess2 -ScriptBlock { mpls --create 10 --nh 3 }
    
    Write-Host "Creating rt #1"
    Invoke-Command -Session $sess1 -ScriptBlock { rt.exe -c -v 1 -f 1 -e $Using:container2_mac -n 2 -t 10 -x 0x07 }
    Invoke-Command -Session $sess2 -ScriptBlock { rt.exe -c -v 1 -f 1 -e $Using:container1_mac -n 2 -t 10 -x 0x07 }
    
    Write-Host "Creating rt #2"
    Invoke-Command -Session $sess1 -ScriptBlock { rt.exe -c -v 0 -f 0 -p 192.168.3.101 -l 32 -n 4 -x 0x0f }
    Invoke-Command -Session $sess2 -ScriptBlock { rt.exe -c -v 0 -f 0 -p 192.168.3.102 -l 32 -n 4 -x 0x0f }
    
    Write-Host "Getting containers IPs"
    $res1 = Invoke-Command -Session $sess1 -ScriptBlock { docker exec $Using:container1_id powershell "Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias vEthernet* | Select-Object IPAddress | Format-List" }
    $res2 = Invoke-Command -Session $sess2 -ScriptBlock { docker exec $Using:container2_id powershell "Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias vEthernet* | Select-Object IPAddress | Format-List" }
    
    $container1_ip = $res1[2].Split(":")[1].Trim(); $container1_ip
    $container2_ip = $res2[2].Split(":")[1].Trim(); $container2_ip
    
    Write-Host "Executing netsh"
    Invoke-Command -Session $sess1 -ScriptBlock { 
        docker exec $Using:container1_id netsh interface ipv4 add neighbors "$Using:container1_iFullName" $Using:container2_ip $Using:container2_mac_win
    }
    Invoke-Command -Session $sess2 -ScriptBlock {
        docker exec $Using:container2_id netsh interface ipv4 add neighbors "$Using:container2_iFullName" $Using:container1_ip $Using:container1_mac_win
    }
    
    $res1 = Invoke-Command -Session $sess1 -ScriptBlock { docker exec $Using:container1_id powershell "ping $Using:container2_ip > null 2>&1; $LASTEXITCODE;" }
    $res2 = Invoke-Command -Session $sess2 -ScriptBlock { docker exec $Using:container2_id powershell "ping $Using:container1_ip > null 2>&1; $LASTEXITCODE;" }
    
    if ($res1 -ne 0 -Or $res2 -ne 0) {
        Write-Host "Multi-host ping test failed!"
        exit 1
    }
}