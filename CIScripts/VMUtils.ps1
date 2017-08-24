class NewVMCreationSettings {
    [string] $ResourcePoolName;
    [string] $TemplateName;
    [string] $CustomizationSpecName;
    [string[]] $DatastoresList;
    [string] $NewVMLocation;
}

class VIServerAccessData {
    [string] $Username;
    [string] $Password;
    [string] $Server;
}

function Initialize-VIServer {
    Param ([Parameter(Mandatory = $true)] [string] $PowerCLIScriptPath,
           [Parameter(Mandatory = $true)] [VIServerAccessData] $VIServerAccessData)

    Push-Location

    # Global named mutex needed here because all PowerCLI commnads are running in global context and modify common configuration files.
    # Without this mutex, PowerCLI commands may throw an exception in case of configuration file being blocked by another job.
    $Mutex = [System.Threading.Mutex]::new($false, "WinContrailCIPowerCLIMutex")
    [void] $Mutex.WaitOne()

    try {
        $Res = Get-Command -Name Connect-VIServer -CommandType Cmdlet -ErrorAction SilentlyContinue
        if (-Not $Res) {
            & "$PowerCLIScriptPath" | Out-Null
        }

        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
        Set-PowerCLIConfiguration -DefaultVIServerMode Single -Confirm:$false | Out-Null

        Connect-VIServer -User $VIServerAccessData.Username -Password $VIServerAccessData.Password -Server $VIServerAccessData.Server | Out-Null
    }
    finally {
        [void] $Mutex.ReleaseMutex()
    }

    Pop-Location
}

function New-TestbedVMs {
    Param ([Parameter(Mandatory = $true, HelpMessage = "List of names of created VMs")] [string[]] $VMNames,
           [Parameter(Mandatory = $true, HelpMessage = "Flag indicating if we should install all artifacts on spawned VMs")] [bool] $InstallArtifacts,
           [Parameter(Mandatory = $true, HelpMessage = "Path to VMWare PowerCLI initialization script")] [string] $PowerCLIScriptPath,
           [Parameter(Mandatory = $true, HelpMessage = "Access data for VIServer")] [VIServerAccessData] $VIServerAccessData,
           [Parameter(Mandatory = $true, HelpMessage = "Settings required for creating new VM")] [NewVMCreationSettings] $VMCreationSettings,
           [Parameter(Mandatory = $true, HelpMessage = "Credentials required to access created VMs")] [System.Management.Automation.PSCredential] $VMCredentials,
           [Parameter(Mandatory = $true, HelpMessage = "Directory with artifacts collected from other jobs")] [string] $ArtifactsDir,
           [Parameter(Mandatory = $true, HelpMessage = "Location of crash dump files")] [string] $DumpFilesLocation,
           [Parameter(Mandatory = $true, HelpMessage = "Crash dump files base name (prefix)")] [string] $DumpFilesBaseName,
           [Parameter(Mandatory = $true, HelpMessage = "Max time to wait for VMs")] [int] $MaxWaitVMMinutes)

    function New-StartedVM {
        Param ([Parameter(Mandatory = $true)] [string] $VMName,
               [Parameter(Mandatory = $true)] [NewVMCreationSettings] $VMCreationSettings)

        Write-Host "Creating and starting $VMName"
        $ResourcePool = Get-ResourcePool -Name $VMCreationSettings.ResourcePoolName
        $Template = Get-Template -Name $VMCreationSettings.TemplateName
        $CustomizationSpec = Get-OSCustomizationSpec -Name $VMCreationSettings.CustomizationSpecName

        $AllDatastores = Get-Datastore -Name $VMCreationSettings.DatastoresList
        $EmptiestDatastore = ($AllDatastores | Sort-Object -Property FreeSpaceGB -Descending)[0]

        New-VM -Name $VMName -Template $Template -Datastore $EmptiestDatastore -ResourcePool $ResourcePool -Location $VMCreationSettings.NewVMLocation `
            -OSCustomizationSpec $CustomizationSpec -ErrorAction Stop -Verbose | Out-Null
        #New-HardDisk -VM $vm -CapacityGB 2 -Datastore DUMP -StorageFormat thin -Controller (Get-ScsiController -VM $vm) -Persistence IndependentPersistent -Verbose # TODO: Fix after JW-796
        Start-VM -VM $VMName -Confirm:$false -ErrorAction Stop -Verbose | Out-Null
    }

    function Wait-VMs {
        Param ([Parameter(Mandatory = $true)] [Collections.Generic.List[String]] $VMNamesList,
               [Parameter(Mandatory = $false)] [int] $MaxWaitMinutes = 15)

        $DelaySec = 30
        $MaxRetries = [math]::Ceiling($MaxWaitMinutes * 60 / $DelaySec)

        for ($RetryNum = 0; $VMNamesList.Count -ne 0; ) {
            Write-Host "Retry number $RetryNum / $MaxRetries"
            ping $VMNamesList[0] | Out-Null

            if ($? -eq $true) {
                $VMNamesList.RemoveAt(0)
                continue
            }

            Start-Sleep -s $DelaySec
            $RetryNum++

            if ($RetryNum -gt $MaxRetries) {
                throw "Waited for too long. The VMs did not respond in maximum expected time."
            }
        }
    }

    function New-RemoteSessions {
        Param ([Parameter(Mandatory = $true)] [string[]] $VMNames,
               [Parameter(Mandatory = $true)] [System.Management.Automation.PSCredential] $Credentials)

        $Sessions = [System.Collections.ArrayList] @()
        $VMNames.ForEach({
            $Sess = New-PSSession -ComputerName $_ -Credential $Credentials

            Invoke-Command -Session $Sess -ScriptBlock {
                $ErrorActionPreference = "Stop"
            }

            $Sessions += $Sess
        })

        return $Sessions
    }

    function Enable-NBLDebugging {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session)

        Invoke-Command -Session $Session -ScriptBlock {
            # Enable tracing of NBL owner, so that !ndiskd.pendingnbls debugger extension can search and identify lost NBLs.
            New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\NDIS\Parameters" -Name TrackNblOwner -Value 1 -PropertyType DWORD -Force | Out-Null
        }
    }

    function Initialize-CrashDumpSaving {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $DumpFilesLocation,
               [Parameter(Mandatory = $true)] [string] $DumpFilesBaseName)

        $DumpFilename = $DumpFilesLocation + "\" + $DumpFilesBaseName + "_" + $Session.ComputerName + ".dmp"

        Invoke-Command -Session $Session -ScriptBlock {
            # TODO: Fix after JW-796
            <#Get-Disk | Where-Object PartitionStyle -eq 'raw' |
                Initialize-Disk -PartitionStyle MBR -PassThru |
                New-Partition -AssignDriveLetter -UseMaximumSize |
                Format-Volume -FileSystem NTFS -NewFileSystemLabel "DUMP_HD" -Confirm:$false | Out-Null#>

            New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name DumpFile -PropertyType ExpandString -Value $Using:DumpFilename -Force | Out-Null
        }
    }

    function Install-Artifacts {
        Param ([Parameter(Mandatory = $true)] [System.Management.Automation.Runspaces.PSSession] $Session,
               [Parameter(Mandatory = $true)] [string] $ArtifactsDir)

        Push-Location $ArtifactsDir

        Invoke-Command -Session $Session -ScriptBlock {
            New-Item -ItemType Directory -Force C:\Artifacts | Out-Null
        }

        Write-Host "Copying Docker driver installer"
        Copy-Item -ToSession $Session -Path "docker_driver\docker-driver.msi" -Destination C:\Artifacts\

        Write-Host "Copying Agent and Contrail vRouter API"
        Copy-Item -ToSession $Session -Path "agent\contrail-vrouter-agent.msi" -Destination C:\Artifacts\
        Copy-Item -ToSession $Session -Path "agent\contrail-vrouter-api-1.0.tar.gz" -Destination C:\Artifacts\

        Write-Host "Copying Agent test executables"
        $AgentTextExecutables = Get-ChildItem .\agent | Where-Object {$_.Name -match '^[\W\w]*test[\W\w]*.exe$'}
        Foreach ($TestExecutable in $AgentTextExecutables) {
            Write-Host "    Copying $TestExecutable"
            Copy-Item -ToSession $Session -Path "agent\$TestExecutable" -Destination C:\Artifacts\
        }

        Write-Host "Copying vtest scenarios"
        Copy-Item -ToSession $Session -Path "vrouter\utils\vtest" -Destination C:\Artifacts\ -Recurse -Force

        Write-Host "Copying vRouter and Utils MSIs"
        Copy-Item -ToSession $Session -Path "vrouter\vRouter.msi" -Destination C:\Artifacts\
        Copy-Item -ToSession $Session -Path "vrouter\utils.msi" -Destination C:\Artifacts\
        Copy-Item -ToSession $Session -Path "vrouter\*.cer" -Destination C:\Artifacts\ # TODO: Remove after JW-798

        Invoke-Command -Session $Session -ScriptBlock {
            Write-Host "Installing Contrail vRouter API"
            pip2 install C:\Artifacts\contrail-vrouter-api-1.0.tar.gz | Out-Null

            Write-Host "Installing vRouter Extension"
            Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root\ "C:\Artifacts\vRouter.cer" | Out-Null # TODO: Remove after JW-798
            Import-Certificate -CertStoreLocation Cert:\LocalMachine\TrustedPublisher\ "C:\Artifacts\vRouter.cer" | Out-Null # TODO: Remove after JW-798
            Start-Process msiexec.exe -ArgumentList @("/i", "C:\Artifacts\vRouter.msi", "/quiet") -Wait

            Write-Host "Installing Utils"
            Start-Process msiexec.exe -ArgumentList @("/i", "C:\Artifacts\utils.msi", "/quiet") -Wait

            Write-Host "Installing Docker driver"
            Start-Process msiexec.exe -ArgumentList @("/i", "C:\Artifacts\docker-driver.msi", "/quiet") -Wait

            Write-Host "Installing Agent"
            Start-Process msiexec.exe -ArgumentList @("/i", "C:\Artifacts\contrail-vrouter-agent.msi", "/quiet") -Wait

            # Refresh Path
            $Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        }

        Write-Host "Copying Docker driver tests"
        $TestFiles = @("controller", "hns", "hnsManager", "driver")
        $TestFiles.ForEach( { Copy-Item -ToSession $Session -Path "docker_driver\$_.test" -Destination "C:\Program Files\Juniper Networks\$_.test.exe" })

        Pop-Location
    }

    Write-Host "Connecting to VIServer"
    Initialize-VIServer -PowerCLIScriptPath $PowerCLIScriptPath -VIServerAccessData $VIServerAccessData

    Write-Host "Starting VMs"
    $VMNames.ForEach({ New-StartedVM -VMName $_ -VMCreationSettings $VMCreationSettings })

    Write-Host "Waiting for VMs to start..."
    $VMsList = [Collections.Generic.List[String]] $VMNames
    Wait-VMs -VMNames $VMsList -MaxWaitMinutes $MaxWaitVMMinutes

    $Sessions = New-RemoteSessions -VMNames $VMNames -Credentials $VMCredentials

    Write-Host "Initializing Crash dump saving and configuring NBL debugging"
    $Sessions.ForEach({
        Initialize-CrashDumpSaving -Session $_ -DumpFilesLocation $DumpFilesLocation -DumpFilesBaseName $DumpFilesBaseName
        Enable-NBLDebugging -Session $_
    })

    if ($InstallArtifacts -eq $true) {
        Write-Host "Installing artifacts"
        $Sessions.ForEach({ Install-Artifacts -Session $_ -ArtifactsDir $ArtifactsDir })
    }

    return $Sessions
}

function Remove-TestbedVMs {
    Param ([Parameter(Mandatory = $true, HelpMessage = "List of names of VMs")] [string[]] $VMNames,
           [Parameter(Mandatory = $true, HelpMessage = "Path to VMWare PowerCLI initialization script")] [string] $PowerCLIScriptPath,
           [Parameter(Mandatory = $true, HelpMessage = "Access data for VIServer")] [VIServerAccessData] $VIServerAccessData)

    Initialize-VIServer -PowerCLIScriptPath $PowerCLIScriptPath -VIServerAccessData $VIServerAccessData

    $VMNames.ForEach({
        Write-Host "Removing $_ from datastore"
        Stop-VM -VM $_ -Kill -Confirm:$false | Out-Null
        Remove-VM -VM $_ -DeletePermanently -Confirm:$false | Out-Null
    })
}

function Get-SanitizedOrGeneratedVMName {
    Param ([Parameter(Mandatory = $true, HelpMessage = "Name to check. It will be regenerated if needed.")] [string] $VMName,
           [Parameter(Mandatory = $true, HelpMessage = "Prefix added to randomly generated name")] [string] $RandomNamePrefix)

    $VMName = $VMName.Replace("_", "-")
    $VMName = [Regex]::Replace($VMName, "[^0-9a-zA-Z-]", [string]::Empty)

    if (($VMName -eq "Auto") -or ($VMName.Length -eq 0)) {
        return $RandomNamePrefix + [string]([guid]::NewGuid().Guid).Replace("-", "").ToUpper().Substring(0, 6)
    }

    return $VMName
}
