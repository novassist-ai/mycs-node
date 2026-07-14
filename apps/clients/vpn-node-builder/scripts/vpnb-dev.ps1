#Requires -Version 5.1
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$NbArgs
)

$RegistryImage = if ($env:VPNB_REGISTRY_IMAGE) { $env:VPNB_REGISTRY_IMAGE }
                 else { "ghcr.io/novassist-ai/vpn-node-builder" }

$DefaultTag = "dev"

$Image = if ($env:VPNB_IMAGE) { $env:VPNB_IMAGE }
         elseif ($env:VPN_NODE_BUILDER_IMAGE) { $env:VPN_NODE_BUILDER_IMAGE }
         else { "${RegistryImage}:${DefaultTag}" }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is required but was not found on PATH. Install Docker Desktop."
    exit 1
}

if ($NbArgs.Count -ge 1 -and $NbArgs[0] -eq "pull") {
    Write-Host "Pulling ${Image}..."
    & docker pull $Image
    exit $LASTEXITCODE
}

$dockerArgs = @(
    "run", "--privileged", "--rm", "-it",
    "-p", "4495:4495", "-p", "4495:4495/udp",
    "-v", "${PWD}:/work",
    "-w", "/work",
    $Image
) + $NbArgs

& docker @dockerArgs
exit $LASTEXITCODE
