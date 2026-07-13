@echo off
setlocal
set "REGISTRY_IMAGE=ghcr.io/novassist-ai/node-builder"
if not defined NB_IMAGE (
  if defined NODE_BUILDER_IMAGE (
    set "NB_IMAGE=%NODE_BUILDER_IMAGE%"
  ) else (
    set "NB_IMAGE=%REGISTRY_IMAGE%:latest"
  )
)
where docker >nul 2>&1
if errorlevel 1 (
  echo ERROR: Docker is required but was not found on PATH.
  echo Install Docker Desktop: https://docs.docker.com/get-docker/
  exit /b 1
)
if /I "%~1"=="pull" (
  echo Pulling %NB_IMAGE%...
  docker pull %NB_IMAGE%
  exit /b %ERRORLEVEL%
)
docker run --privileged --rm -it -p 4495:4495 -p 4495:4495/udp -v "%CD%:/work" -w /work %NB_IMAGE% %*
endlocal
