#
# App service keys
#
variable "mycs_cloud_public_key_id" {
  default = "NA"
}

variable "mycs_cloud_public_key" {
  default = "NA"
}

variable "mycs_app_private_key" {
  default = "NA"
}

variable "mycs_app_id_key" {
  default = "NA"
}

variable "mycs_space_ca_root" {
  default = "NA"
}

#
# MyCS App Properties
#

variable "mycs_app_version" {
  default = "dev"
}

variable "mycs_root_data_dir" {
  default = "/var/lib/mycs"
}

variable "mycs_app_data_dir" {
  default = "/var/lib/mycs"
}

#
# App network configuration
#

variable "advertised_external_networks" {
  type = list(string)
  default = []
}

variable "advertised_external_domain_names" {
  type = list(string)
  default = []
}

#
# App install
#

# Zip archive of all additional app files. An
# install script can also be provided instead
# of the zip of script files that include the
# install script
variable "app_file_archive" {
  default = "/NA"
}

# Optional app install script if not included
# in the above archive
variable app_install_script {
  default = "/NA"
}

# Name of app install script if within the 
# app_file_archive zip. Otherwise the app 
# install will look for a default script 
# provided via the above app_install_script 
# variable
variable "app_install_script_name" {
  default = "install.sh"
}

#
# App node configuration
#
variable "app_idle_shutdown_time" {
  default = 10
}

variable "app_stop_timeout" {
  default = 0
}

#
# App execution
#

variable "app_work_directory" {
  default = ""
}

variable "app_exec_cmd" {
  default = ""
}

variable "app_cmd_arguments" {
  type = list(string)
  default = []
}

variable "app_env_arguments" {
  type = list(string)
  default = []
}

#
# Other App data
#

variable "app_description" {
  type = string
}

variable "app_domain_name" {
  type = string
}

variable "app_service_ports" {
  default = ""
}

#
# Compress cloud-init data
#
variable "compress_cloudinit" {
  default = true
}
