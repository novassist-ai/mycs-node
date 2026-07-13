@echo off
setlocal
if not defined NB_IMAGE if not defined NODE_BUILDER_IMAGE (
  set "NB_IMAGE=novassist/node-builder:latest"
) else if defined NODE_BUILDER_IMAGE (
  set "NB_IMAGE=%NODE_BUILDER_IMAGE%"
)
where docker >nul 2>&1
if errorlevel 1 (
  echo ERROR: Docker is required but was not found on PATH.
  echo Install Docker Desktop: https://docs.docker.com/get-docker/
  exit /b 1
)
docker run --privileged --rm -it -p 4495:4495 -p 4495:4495/udp -v "%CD%:/work" -w /work %NB_IMAGE% %*
endlocal
