@echo off
setlocal
set "REGISTRY_IMAGE=ghcr.io/novassist-ai/vpn-node-builder"
if not defined VPNB_IMAGE (
  if defined VPN_NODE_BUILDER_IMAGE (
    set "VPNB_IMAGE=%VPN_NODE_BUILDER_IMAGE%"
  ) else (
    set "VPNB_IMAGE=%REGISTRY_IMAGE%:latest"
  )
)
where docker >nul 2>&1
if errorlevel 1 (
  echo ERROR: Docker is required but was not found on PATH.
  echo Install Docker Desktop: https://docs.docker.com/get-docker/
  exit /b 1
)
if /I "%~1"=="pull" (
  echo Pulling %VPNB_IMAGE%...
  docker pull %VPNB_IMAGE%
  exit /b %ERRORLEVEL%
)
docker run --privileged --rm -it -p 4495:4495 -p 4495:4495/udp -v "%CD%:/work" -w /work %VPNB_IMAGE% %*
endlocal
