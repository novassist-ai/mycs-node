#Requires -Version 5.1
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$Image = if ($env:NB_IMAGE) { $env:NB_IMAGE }
         elseif ($env:NODE_BUILDER_IMAGE) { $env:NODE_BUILDER_IMAGE }
         else { "novassist/node-builder:latest" }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is required but was not found on PATH. Install Docker Desktop."
    exit 1
}

$dockerArgs = @(
    "run", "--privileged", "--rm", "-it",
    "-p", "4495:4495", "-p", "4495:4495/udp",
    "-v", "${PWD}:/work",
    "-w", "/work",
    $Image
) + $Args

& docker @dockerArgs
exit $LASTEXITCODE
