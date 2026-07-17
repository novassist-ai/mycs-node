@echo off
setlocal
set "REGISTRY_IMAGE=ghcr.io/novassist-ai/vpn-node-builder"
if not defined VPNB_IMAGE (
  if defined VPN_NODE_BUILDER_IMAGE (
    set "VPNB_IMAGE=%VPN_NODE_BUILDER_IMAGE%"
  ) else (
    set "VPNB_IMAGE=%REGISTRY_IMAGE%:dev"
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
if /I "%~1"=="update" (
  echo Updating %VPNB_IMAGE%...
  docker image inspect %VPNB_IMAGE% >nul 2>&1
  if not errorlevel 1 (
    docker rmi -f %VPNB_IMAGE% >nul 2>&1
  )
  echo Pulling %VPNB_IMAGE%...
  docker pull %VPNB_IMAGE%
  exit /b %ERRORLEVEL%
)
docker image inspect %VPNB_IMAGE% >nul 2>&1
if errorlevel 1 (
  echo Image '%VPNB_IMAGE%' not found locally; pulling...
  docker pull %VPNB_IMAGE%
  if errorlevel 1 exit /b %ERRORLEVEL%
)
if not defined VPNB_WORKSPACE_NAME (
  for %%I in ("%CD%") do set "VPNB_WORKSPACE_NAME=%%~nxI"
)
docker run --privileged --rm -it -p 4495:4495 -p 4495:4495/udp -e VPNB_WORKSPACE_NAME=%VPNB_WORKSPACE_NAME% -v "%CD%:/work" -w /work %VPNB_IMAGE% %*
endlocal
