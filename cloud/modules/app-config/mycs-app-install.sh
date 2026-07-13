#!/bin/bash

rm -rf /var/lib/apt/lists/*
echo "waiting 180 seconds for network to become available"
timeout 180 /bin/bash -c \
  "until curl -s --fail $(cat /etc/apt/sources.list | awk '/^deb /{ print $2 }' | head -1) 2>&1 >/dev/null; do echo waiting ...; sleep 1; done"

if [[ $? -ne 0 ]]; then
  echo "Timed out waiting for cloud-init to complete boot phase."
  exit 1
fi

set -xeu

osname=$(uname -s)
osarch=$(uname -m)

case $osarch in
  aarch64)
    binary_arch=arm64
    ;;
  x86_64)
    binary_arch=amd64
    ;;
  *)
    echo "OS architecture '$osarch' not supported."
    exit 1
esac 

export DEBIAN_FRONTEND=noninteractive
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# See https://github.com/jawj/IKEv2-setup/issues/66 and https://bugs.launchpad.net/subiquity/+bug/1783129
# Note: software-properties-common is required for add-apt-repository
apt-get -o Acquire::ForceIPv4=true update
apt-get -o Acquire::ForceIPv4=true install -y software-properties-common
add-apt-repository universe
add-apt-repository restricted
add-apt-repository multiverse

apt-get update
apt-get -o Acquire::ForceIPv4=true install -y whois jq zip

config_dir=/etc/mycs
bin_dir=/usr/local/bin
app_dir=/usr/local/lib/mycs

useradd mycs -p $(mkpasswd "$(openssl rand -base64 32)") -m -d $app_dir -s /bin/bash
chown -R mycs:root $config_dir
chown -R mycs:root $app_dir

if [[ ! -e /etc/mycs/mycs-key-NA.pem ]]; then

  if [[ ! -e /usr/local/bin/mycs-app ]]; then
    # download and install app
    mkdir -p $app_dir
    cd $app_dir
    if [[ ${mycs_app_version} == dev ]]; then
      curl -L https://mycsdev-deploy-artifacts.s3.amazonaws.com/releases/mycs-node_linux_$binary_arch.zip -o mycs-node.zip
    else
      curl -L https://mycsprod-deploy-artifacts.s3.amazonaws.com/releases/mycs-node-${mycs_app_version}_linux_$binary_arch.zip -o mycs-node.zip
    fi
    unzip mycs-node.zip
    rm mycs-node mycs-daemon headscale
    cd -

    ln -s $app_dir/mycs-app $bin_dir/mycs-app
    ln -s $app_dir/tailscale $bin_dir/tailscale
    
    mkdir -p ${mycs_app_data_dir}
    chown -R mycs:root ${mycs_app_data_dir}
    echo "${mycs_app_version}" > /etc/mycs/version
    chown mycs:root /etc/mycs/version
  fi

  if [[ ! -e /etc/systemd/system/mycs-app.service ]]; then
    # configure app service
    cat << ---EOF > /etc/systemd/system/mycs-app.service
[Unit]
Description=MyCloudSpace App Control Service
Wants=network.target
After=network.target NetworkManager.service systemd-resolved.service

After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
StandardOutput=syslog
StandardError=syslog
# Environment=CBS_LOGLEVEL=trace
SyslogIdentifier=mycs-app
ExecStart=/usr/local/bin/mycs-app
Restart=on-failure

[Install]
WantedBy=multi-user.target
---EOF

  fi

  systemctl daemon-reload
fi

cd $app_dir
[[ -n $(file $app_dir/app-scripts.zip | grep 'Zip archive data') ]] \
  && unzip -o $app_dir/app-scripts.zip
[[ -e ${app_install_script} ]] \
  && source ${app_install_script}
cd -

if [[ -e /etc/systemd/system/mycs-app.service ]]; then
  systemctl enable mycs-app
  systemctl start mycs-app
fi

touch $app_dir/.installed
