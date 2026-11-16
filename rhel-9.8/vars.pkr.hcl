variable "proxmox_user" {
  type        = string
  description = "proxmox username"
  default     = "packer@pam!<api-tag>"
}
variable "proxmox_pass" {
  type        = string
  description = "proxmox password"
  default     = "packer"
  sensitive   = true
}
variable "proxmox_iso_file" {
  type        = string
  description = "iso file on local storage, for example local:iso/rhel-9.8-x86_64-boot.iso"
}
variable "proxmox_iso_checksum" {
  type        = string
  description = "check sum of the iso from above"
}
variable "proxmox_host" {
  type        = string
  description = "hostname or ip for the proxmox host"
}
variable "proxmox_node" {
  type        = string
  description = "proxmox node name"
}
variable "proxmox_vm_id" {
  type        = string
  description = "vm id to use when creating the vm and template"
}
variable "proxmox_template_name" {
  type        = string
  description = "name of the vm template at the end of the day"
  default     = "packer-rhel-98"
}
variable "proxmox_template_description" {
  type        = string
  description = "description of the vm template"
  default     = "packer-vm"
}
variable "proxmox_storage_pool" {
  type        = string
  description = "storage pool on the proxmox node"
}
variable "ssh_username" {
  type        = string
  description = "ssh username, created by the kickstart with passwordless sudo"
  default     = "packer"
}
variable "ssh_password" {
  type        = string
  description = "ssh password"
  default     = "packer"
  sensitive   = true
}
variable "rhsm_org" {
  type        = string
  description = "red hat organization id, the boot iso has no packages so the install registers to download them"
  sensitive   = true
}
variable "rhsm_activation_key" {
  type        = string
  description = "red hat activation key name, from console.redhat.com > inventory > system configuration > activation keys"
  sensitive   = true
}
variable "uefi" {
  type        = bool
  description = "build the UEFI (OVMF) + Secure Boot variant, named <proxmox_template_name>-uefi"
  default     = false
}
