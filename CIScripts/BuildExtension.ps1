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

Write-Host "Copying third-party dependencies"
mkdir third_party/
Copy-Item -Recurse "$Env:THIRD_PARTY_CACHE_PATH\extension\*" third_party\
Copy-Item -Recurse "$Env:THIRD_PARTY_CACHE_PATH\common\*" third_party\
Copy-Item -Recurse third_party\cmocka vrouter\test\

Write-Host "Building Extension and Utils"
$cerp = Get-Content $Env:CERT_PASSWORD_FILE_PATH
devenv.com /Build "Debug|x64" vrouter\vRouter.sln

$vRouterMSI = "vrouter\windows\installer\vrouterMSI\Debug\vRouter.msi"
$utilMSI = "vrouter\windows\installer\utilsMSI\Debug\utilsMSI.msi"

Write-Host "Signing MSIs"
& "$Env:SIGNTOOL_PATH" sign /f "$Env:CERT_PATH" /p $cerp $utilMSI
& "$Env:SIGNTOOL_PATH" sign /f "$Env:CERT_PATH" /p $cerp $vRouterMSI
