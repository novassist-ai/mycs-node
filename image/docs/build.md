# Packer configuration to build an bastion or inception VM for cloud deployment automation.

It installs the following packages to an Ubuntu cloud image.

* OpenVPN
* SquidProxy
* SMTP
* Concourse
* Docker

Each of the above tools will be configured on first boot. 

## Building

The images are built using [packer](http://packer.io/): 

### Building an AWS AMI

Build the image by executing the following script. If a region is not provided then the image will be build for all regions.

```
$ build/build-aws-image.sh us-west-1
```

> If region is not provided an AMI will be built for each region.

### Building an GCP IMAGE

Build the image by executing the following script.

```
$ build/build-gcp-image.sh us-west-1
```

## Configuring Services

Packages are configured by placing a YAML file named `config.yml` within the root users home folder with the configuration parameters for the respective package. If packages have not been configured by explicitly calling the `<ROOT USER HOME>/bin/configure_*` script they will configured on boot if `config.yml` is present and the package configuration variables are provided.

The `config.yml` configuration may be passed during instance creation using one of the following methods.

1. As user data user data for IaaS's that support retrieval via an AWS compatible "metadata" service.
2. As a file that is created at `<ROOT USER HOME>/config.yml` via a cloud-init configuration.

The base configuration values are:

```
---
server:
  host: <PUBLIC IP OR DNS NAME - can also be an Elastic or Floating IP>
  ip: <IP OF INTERFACE FOR EXTERNAL INGRESS TRAFFIC - if empty host IP is assumed to be IP on the interface>
  lan_interfaces: <COMMA SEPARATED LIST OF 'interface|ip|netmask|route_cidr|route_netmask|gateway|'>
```

The `server.host` configuration value should be the externally accessible IP of the inception instance. The server network interface configuration should be provided as a comma separated list of `ip|subnet_cidr|lan_cidr|gateway|dhcp_lease_start|dhcp_lease_end` in the order of the interfaces configured for the instance.

* `ip` - IPv4 address of network interface
* `subnet_cidr` - CIDR of subnet to which this interface is attached
* `lan_cidr` - CIDR of LAN to which a static route will be created via this interface
* `gateway` - Gateway to configure for the interface's subnet
* `dhcp_lease_start` - 0 DHCPd lease start (if providing DHCP leases on LAN segment)
* `dhcp_lease_end` - DHCPd lease end (if providing DHCP leases on LAN segment)

If the `ip` is empty then it will be assumed that the NIC is auto configured and this configuration will only be used when configuring OpenVPN. It is important that the first interface is the external interface via which VPN connections will be made. 

The bastion will behave as a gateway and provide routing for subnets each interface is attached to. The first interface will be assumed to be attached to the DMZ and will also be the NAT interface. If the DHCP lease ranges are provided then the bastion will provide DHCP leases on that interface.

### OpenVPN

OpenVPN is configured via the `bin\configure_openvpn` script. It will execute if the `port` configuration value is present.

```
openvpn:
  port: <THE PORT OPENVPN WILL LISTEN ON>
  protocol: [tcp|udp]
  subnet: <VPN SUBNET i.e. 192.168.111.0/24>
  netmask: <VPN SUBNET NETMASK i.e. 255.255.255.0>
  server_domain: <VPN SERVER DOMAIN>
  server_description: <VPN SERVER DECRIPTION>
  tunnel_all_traffic: [yes|no]
  vpn_cert:
    name: <IDENTIFYING NAME>
    org: <COMPANY NAME>
    email: <ADMIN EMAIL>
    city: <CITY>
    province: <STATE/PROVINCE>
    country: <ISO COUNTRY CODE>
    ou: <ORGANIZATION UNIT>
    cn: <COMMON NAME for VPN server>
  users: <COMMA SEPARATED LIST OF 'user|passwd'>
```

> Providing the `admin_passwd` creates a "admin" user with VPN credentials and disables the default os user.

> For the VPN certificate, fields `country`,`org`,`cn`,`ou`,`email` and name are mandatory.

If you are deploying to AWS manually and would like to provide the `config.yml` as user data, then pre-allocate an elastic IP and associate it with the instance once it has launched. An example config.yml would be:

```
---
server:
  host: <Your Elastic IP>
  lan_interfaces: 'eth0|172.31.0.0/16|255.255.0.0|172.31.0.254'

openvpn:
  port: 1194
  protocol: udp
  subnet: 192.168.111.0/24
  netmask: 255.255.255.0
  server_domain: acme.io
  server_description: Acme-VPN
  tunnel_all_traffic: yes
  vpn_cert:
    name: acme-vpn
    org: Acme, Inc.
    email: admin@acme.org
    city: New York
    province: NY
    country: UD
    ou: Dev
    cn: acme.org
  users: 'user1|passw0rd1,user2|passw0rd2'

squidproxy:
  port: 0.0.0.0:8888
  networks: '172.31.0.0/16'
  custom_headers_allowed: 'X-Auth-Token'
```

You can also configure OpenVPN after the instance has been launched by creating the `config.yml` under the root home directory and rebooting the instance. Additional users can be added by running the following script.

```
create_vpn_user <USER> <PASSWORD>
```

### SquidProxy

SquidProxy is configured via the `bin\configure_squidproxy` script. It will execute if the `port` configuration value is present.

```
squidproxy:
  port: <INTERFACE IP AND PORT TO LISTEN ON i.e. 0.0.0.0:8888>
  networks: <COMMA SEPARATED CIDR OF SUBNETS THAT THE PROXY WILL ACCEPT CONNECTIONS FROM>
  custom_headers_allowed: <COMMA SEPARATED LIST OF CUSTOM HEADERS THAT WILL BE PASSED THROUGH>
```

### Concourse

Concourse is configured via the `bin\configure_concourse` script. As with the other scripts it will execute only if the `port` configuration value is present. It is recommended to configure Concourse to listen on port 127.0.0.1 and access concourse via a tunnel or VPN for security reasons, especially if you plan to use Concourse to automate infrastructure and software configuration.

```
concourse:
  port: <IP:PORT TO LISTEN ON - if IP is not provided concourse will listen on all interfaces>
  password: <PASSWORD FOR BASIC AUTH TO DEFAULT TEAM>
```

Follow the steps below to set-up a bootstrap pipeline once concourse has been installed.

1. Upload the bootstrap pipeline YAML to `/root/bootstrap.yml`.
2. Upload the external configuration for the pipeline to `/root/bootstrap-vars.yml`

The `bin\configure_concourse` script will look for the existance of these files within the `/root` folder and set the pipeline in local Concourse and unpause it. In addition to the the variables you provide the following will be added as pipeline variables.

* `environment` - The name of the VPC.
* `concourse_url` - The Concourse URL to access the installed Concourse instance from within a job.
* `concourse_user` - The Concourse user name for the `main` team.
* `concourse_password` -  The password for the user.
