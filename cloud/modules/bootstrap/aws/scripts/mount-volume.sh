#!/bin/bash

set -x

[[ -n "${attached_device_name}" ]] || exit 0

# Mount and format the data volume if available and unformatted

i=12
while [ $i -gt 0 ]; do
  device="/dev/$(lsblk | grep "$(basename ${attached_device_name})" | head -1 | cut -d" " -f1)"

  if [[ $device == /dev/${attached_device_name} ]]; then
    break
  fi
  echo "Waiting for data volume to be attached..."
  sleep 5
  i=$(($i-1))
done

if [[ $device == /dev/${attached_device_name} ]]; then

  # Un-mount data volume
  umount ${mount_directory} > /dev/null 2>&1
  sed -i 's|^/dev/${attached_device_name}\s*${mount_directory}\s*.*$||' /etc/fstab
  
  tune2fs -l $device > /dev/null 2>&1
  if [[ $? -eq 1 ]]; then
    # Format new volume
    mkfs.ext4 $device
  fi

  # Mount data volume
  mkdir -p ${mount_directory}
  echo -e "\n$device\t${mount_directory}\text4\tdefaults\t0 1" >> /etc/fstab
  mount -a

  [[ ${world_readable} == true ]] && chmod a+rwx ${mount_directory}
else
  echo "WARNING! Timed out waiting for data volume. Proceeding as a new install."
fi
