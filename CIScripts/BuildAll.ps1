. $PSScriptRoot\InitializeCIScript.ps1
. $PSScriptRoot\BuildFunctions.ps1

$Repos = @(
    [Repo]::new($Env:DRIVER_REPO_URL, $Env:DRIVER_BRANCH, "src/github.com/codilime/contrail-windows-docker", "master"),
    [Repo]::new($Env:TOOLS_REPO_URL, $Env:TOOLS_BRANCH, "tools/build/", "windows"),
    [Repo]::new($Env:SANDESH_REPO_URL, $Env:SANDESH_BRANCH, "tools/sandesh/", "windows"),
    [Repo]::new($Env:GENERATEDS_REPO_URL, $Env:GENERATEDS_BRANCH, "tools/generateDS/", "windows"),
    [Repo]::new($Env:VROUTER_REPO_URL, $Env:VROUTER_BRANCH, "vrouter/", "windows"),
    [Repo]::new($Env:WINDOWSSTUBS_REPO_URL, $Env:WINDOWSSTUBS_BRANCH, "windows/", "windows"),
    [Repo]::new($Env:CONTROLLER_REPO_URL, $Env:CONTROLLER_BRANCH, "controller/", "windows3.1")
)

Copy-Repos -Repos $Repos
Invoke-ContrailCommonActions -ThirdPartyCache $Env:THIRD_PARTY_CACHE_PATH -VSSetupEnvScriptPath $Env:VS_SETUP_ENV_SCRIPT_PATH

Invoke-DockerDriverBuild -DriverSrcPath $Env:DRIVER_SRC_PATH -SigntoolPath $Env:SIGNTOOL_PATH -CertPath $Env:CERT_PATH -CertPasswordFilePath $Env:CERT_PASSWORD_FILE_PATH
Invoke-ExtensionBuild -ThirdPartyCache $Env:THIRD_PARTY_CACHE_PATH -SigntoolPath $Env:SIGNTOOL_PATH -CertPath $Env:CERT_PATH -CertPasswordFilePath $Env:CERT_PASSWORD_FILE_PATH
Invoke-AgentBuild -ThirdPartyCache $Env:THIRD_PARTY_CACHE_PATH

