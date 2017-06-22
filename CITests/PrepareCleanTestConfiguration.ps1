function Prepare-CleanTestConfiguration ($sess, $adapter, $testConfiguration) {
    $forwardingExtensionName = $testConfiguration.forwardingExtensionName
    $vmSwitchName = $testConfiguration.vmSwitchName
    $dockerDriverCfg = $testConfiguration.dockerDriverCfg
    
    Write-Host "Stopping Docker Driver"
    Invoke-Command -Session $sess -ScriptBlock {
        $proc = Get-Process contrail-windows-docker -ErrorAction SilentlyContinue
        if ($proc) {
            $proc | Stop-Process -Force
        }
    }
    Start-Sleep -s 3
    
    Write-Host "Restarting Extension"
    Invoke-Command -Session $sess -ScriptBlock {
        Disable-VMSwitchExtension -VMSwitchName $Using:vmSwitchName -Name $Using:forwardingExtensionName | Out-Null
    }
    Start-Sleep -s 1
    
    Invoke-Command -Session $sess -ScriptBlock {
        Enable-VMSwitchExtension -VMSwitchName $Using:vmSwitchName -Name $Using:forwardingExtensionName | Out-Null
    }
    Start-Sleep -s 2
    
    Write-Host "Enabling Docker Driver"
    Invoke-Command -Session $sess -ScriptBlock {
        Stop-Service docker
        Get-NetNat | Remove-NetNat -Confirm:$false
        Get-ContainerNetwork | Remove-ContainerNetwork -force
        Start-Service docker
        
        # Nested ScriptBlock variable passing workaround
        $adapter = $Using:adapter
        $dockerDriverCfg = $Using:dockerDriverCfg
        
        Start-Job -ScriptBlock {
            $dockerDriverCfg = $Using:dockerDriverCfg
            
            $Env:OS_USERNAME = $dockerDriverCfg.os_username
            $Env:OS_PASSWORD = $dockerDriverCfg.os_password
            $Env:OS_AUTH_URL = $dockerDriverCfg.os_auth_url
            $Env:OS_TENANT_NAME = $dockerDriverCfg.os_tenant_name
            
            & "C:\Program Files\Juniper Networks\contrail-windows-docker.exe" -forceAsInteractive -controllerIP $dockerDriverCfg.os_controller_ip -adapter $Using:adapter -vswitchName "Layered <adapter>"
        } | Out-Null
    }
    Start-Sleep -s 30
    
    Write-Host "Checking services"
    $ext = Invoke-Command -Session $sess -ScriptBlock { 
        Get-VMSwitchExtension -VMSwitchName $Using:vmSwitchName -Name $Using:forwardingExtensionName 
    }
    if(($ext.Enabled -ne $true) -Or ($ext.Running -ne $true)) { 
        Write-Host "Extension was not enabled or is not running. Test failed."
        exit 1
    }
    
    $ddrv = Invoke-Command -Session $sess -ScriptBlock {
        Get-Process contrail-windows-docker -ErrorAction SilentlyContinue
    }
    if (-Not $ddrv) {
        Write-Host "Docker driver was not enabled. Test failed."
        exit 1
    }
    
    # Check if Utils are in path
    Invoke-Command -Session $sess -ScriptBlock {
        if ((Get-Command "vif" -ErrorAction SilentlyContinue) -eq $null) {
            $Env:Path += ";C:\Utils"
        }
    }
    
    Write-Host "Creating network"
    Invoke-Command -Session $sess -ScriptBlock {
        $os_tenant_name = ($Using:dockerDriverCfg).os_tenant_name
        docker network create --ipam-driver windows --driver Contrail -o tenant=$os_tenant_name -o network=testnet testnet
    }
}
