if ($Env:ENABLE_TRACE -eq $true) {
    Set-PSDebug -Trace 1
}

# Refresh Path and PSModulePath
$Env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")
$Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

# Stop script on error
$ErrorActionPreference = "Stop"

Write-Host "Sourcing VS environment variables"
Invoke-BatchFile "$Env:VS_SETUP_ENV_SCRIPT_PATH"

Write-Host "Cloning repositories"
git clone -b $Env:TOOLS_BRANCH $Env:TOOLS_REPO_URL tools/build/
git clone -b $Env:VROUTER_BRANCH $Env:VROUTER_REPO_URL vrouter/
git clone -b $Env:WINDOWSSTUBS_BRANCH $Env:WINDOWSSTUBS_REPO_URL windows/
git clone -b $Env:SANDESH_BRANCH $Env:SANDESH_REPO_URL tools/sandesh/
git clone -b $Env:CONTROLLER_BRANCH $Env:CONTROLLER_REPO_URL controller/
git clone -b $Env:GENERATEDS_BRANCH $Env:GENERATEDS_REPO_URL tools/generateDS/

Write-Host "Copying third-party dependencies"
New-Item -ItemType Directory ./third_party
Copy-Item -Recurse "$Env:THIRD_PARTY_CACHE_PATH\agent\*" third_party/
Copy-Item -Recurse "$Env:THIRD_PARTY_CACHE_PATH\common\*" third_party/

Copy-Item tools/build/SConstruct ./

Write-Host "Building Agent"
scons -Q contrail-vrouter-agent

Write-Host "Building Agent MSI"
scons -Q contrail-vrouter-agent.msi

Write-Host "Building API"
scons -Q controller/src/vnsw/contrail_vrouter_api:sdist
