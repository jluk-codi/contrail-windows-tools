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

function New-TestbedVMs {
    Param ([Parameter(Mandatory = $true)] [string[]] $VMNames,
           [Parameter(Mandatory = $true)] [bool] $InstallArtifacts,
           [Parameter(Mandatory = $true)] [string] $PowerCLIScriptPath,
           [Parameter(Mandatory = $true)] [VIServerAccessData] $VIServerAccessData,
           [Parameter(Mandatory = $true)] [NewVMCreationSettings] $VMCreationSettings,
           [Parameter(Mandatory = $true)] [System.Management.Automation.PSCredential] $VMCredentials,
           [Parameter(Mandatory = $true)] [string] $ArtifactsDir,
           [Parameter(Mandatory = $true)] [string] $DumpFilesLocation,
           [Parameter(Mandatory = $true)] [string] $DumpFilesBaseName)

    function Initialize-VIServer {
        Param ([Parameter(Mandatory = $true)] [string] $PowerCLIScriptPath,
               [Parameter(Mandatory = $true)] [VIServerAccessData] $VIServerAccessData)

        Push-Location

        & "$PowerCLIScriptPath" | Out-Null
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
        Connect-VIServer -User $VIServerAccessData.Username -Password $VIServerAccessData.Password -Server $VIServerAccessData.Server | Out-Null

        Pop-Location
    }

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

        for ($RetryNum = 0; $VMNamesList.Count -ne 0; ) {
            Write-Host "Retry number $RetryNum"
            ping $VMNamesList[0] | Out-Null

            if ($? -eq $true) {
                $VMNamesList.RemoveAt(0)
                continue
            }

            Start-Sleep -s 30
            $RetryNum++

            if ($RetryNum -gt ($MaxWaitMinutes * 2)) {
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
        Copy-Item -ToSession $Session -Path "docker_driver\installer.msi" -Destination C:\Artifacts\

        Write-Host "Copying Contrail vRouter API"
        Copy-Item -ToSession $Session -Path "agent\contrail-vrouter-api-1.0.tar.gz" -Destination C:\Artifacts\

        Write-Host "Copying vtest scenarios"
        Copy-Item -ToSession $Session -Path "vrouter\utils\vtest" -Destination C:\Artifacts\ -Recurse -Force

        Write-Host "Copying vRouter and Utils MSIs"
        Copy-Item -ToSession $Session -Path "vrouter\vRouter.msi" -Destination C:\Artifacts\
        Copy-Item -ToSession $Session -Path "vrouter\utilsMSI.msi" -Destination C:\Artifacts\
        Copy-Item -ToSession $Session -Path "vrouter\*.cer" -Destination C:\Artifacts\ # TODO: Remove after JW-798

        Invoke-Command -Session $Session -ScriptBlock {
            Write-Host "Installing Contrail vRouter API"
            pip2 install C:\Artifacts\contrail-vrouter-api-1.0.tar.gz | Out-Null

            Write-Host "Installing vRouter Extension"
            Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root\ "C:\Artifacts\vRouter.cer" | Out-Null # TODO: Remove after JW-798
            Import-Certificate -CertStoreLocation Cert:\LocalMachine\TrustedPublisher\ "C:\Artifacts\vRouter.cer" | Out-Null # TODO: Remove after JW-798
            Start-Process msiexec.exe -ArgumentList @("/i", "C:\Artifacts\vRouter.msi", "/quiet") -Wait

            Write-Host "Installing Utils"
            Start-Process msiexec.exe -ArgumentList @("/i", "C:\Artifacts\utilsMSI.msi", "/quiet") -Wait

            Write-Host "Installing Docker driver"
            Start-Process msiexec.exe -ArgumentList @("/i", "C:\Artifacts\installer.msi", "/quiet") -Wait

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
    Wait-VMs -VMNames $VMsList

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
