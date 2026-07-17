#Requires -Version 5.1
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$NbArgs
)

$RegistryImage = if ($env:VPNB_REGISTRY_IMAGE) { $env:VPNB_REGISTRY_IMAGE }
                 else { "ghcr.io/novassist-ai/vpn-node-builder" }

# Prod launcher (vpnb.ps1). Use vpnb-dev.ps1 for the :dev channel.
$DefaultTag = "latest"

$Image = if ($env:VPNB_IMAGE) { $env:VPNB_IMAGE }
         elseif ($env:VPN_NODE_BUILDER_IMAGE) { $env:VPN_NODE_BUILDER_IMAGE }
         else { "${RegistryImage}:${DefaultTag}" }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is required but was not found on PATH. Install Docker Desktop."
    exit 1
}

function Ensure-Image {
    & docker image inspect $Image 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return }
    Write-Host "Image '${Image}' not found locally; pulling..."
    & docker pull $Image
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($NbArgs.Count -ge 1 -and $NbArgs[0] -eq "pull") {
    Write-Host "Pulling ${Image}..."
    & docker pull $Image
    exit $LASTEXITCODE
}

if ($NbArgs.Count -ge 1 -and $NbArgs[0] -eq "update") {
    Write-Host "Updating ${Image}..."
    & docker image inspect $Image 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        & docker rmi -f $Image | Out-Null
    }
    Write-Host "Pulling ${Image}..."
    & docker pull $Image
    exit $LASTEXITCODE
}

Ensure-Image

# Host directory name so the in-container CLI can derive a stable workspace name.
$WorkspaceName = if ($env:VPNB_WORKSPACE_NAME) { $env:VPNB_WORKSPACE_NAME }
                 else { Split-Path -Leaf (Get-Location).Path }

$dockerArgs = @(
    "run", "--privileged", "--rm", "-it",
    "-p", "4495:4495", "-p", "4495:4495/udp",
    "-e", "VPNB_WORKSPACE_NAME=${WorkspaceName}",
    "-v", "${PWD}:/work",
    "-w", "/work",
    $Image
) + $NbArgs

& docker @dockerArgs
exit $LASTEXITCODE
