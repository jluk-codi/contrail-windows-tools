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
git clone -b $Env:VROUTER_BRANCH $Env:VROUTER_REPO_URL vrouter/
git clone -b $Env:SANDESH_BRANCH $Env:SANDESH_REPO_URL tools/sandesh/
git clone -b $Env:TOOLS_BRANCH $Env:TOOLS_REPO_URL tools/build/
git clone -b $Env:CONTROLLER_BRANCH $Env:CONTROLLER_REPO_URL controller/
git clone -b $Env:WINDOWSSTUBS_BRANCH $Env:WINDOWSSTUBS_REPO_URL windows/

Write-Host "Copying third-party dependencies"
New-Item -ItemType Directory .\third_party
Copy-Item -Recurse "$Env:THIRD_PARTY_CACHE_PATH\extension\*" third_party\
Copy-Item -Recurse "$Env:THIRD_PARTY_CACHE_PATH\common\*" third_party\
Copy-Item -Recurse third_party\cmocka vrouter\test\

Copy-Item tools\build\SConstruct .\

Write-Host "Building Extension and Utils"
$cerp = Get-Content $Env:CERT_PASSWORD_FILE_PATH
scons vrouter
if ($LASTEXITCODE -ne 0) {
    throw "Building vRouter solution failed"
}


$vRouterMSI = "build\debug\vrouter\extension\vRouter.msi"
$utilsMSI = "build\debug\vrouter\utils\utils.msi"

Write-Host "Signing MSIs"
& "$Env:SIGNTOOL_PATH" sign /f "$Env:CERT_PATH" /p $cerp $utilsMSI
if ($LASTEXITCODE -ne 0) {
    throw "Signing utilsMSI failed"
}

& "$Env:SIGNTOOL_PATH" sign /f "$Env:CERT_PATH" /p $cerp $vRouterMSI
if ($LASTEXITCODE -ne 0) {
    throw "Signing vRouterMSI failed"
}
