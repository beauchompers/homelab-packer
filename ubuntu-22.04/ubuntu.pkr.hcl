packer {
  required_plugins {
    proxmox = {
      version = "~>1"
      source  = "github.com/hashicorp/proxmox"
    }
    qemu = {
      version = "=1.0.1"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

# uefi = true builds the UEFI (OVMF) + Secure Boot variant of the template, named <template>-uefi.
# Its autoinstall config comes from a "cidata" cd built from <http_directory>_uefi rather than over http:
# the live installer can't reach packer's http server early in boot on q35, and q35 also renames
# the NIC from ens18 (see http_uefi/user-data)
locals {
  template_name        = var.uefi ? "${var.proxmox_template_name}-uefi" : var.proxmox_template_name
  template_description = var.uefi ? "${var.proxmox_template_description} (UEFI + Secure Boot)" : var.proxmox_template_description
  cidata_directory     = "${var.http_directory}_uefi"
  # cloud-init's nocloud datasource finds the cidata cd by its label, so the uefi build only needs "autoinstall"
  autoinstall_source = var.uefi ? "" : "ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'"
}

source "proxmox-iso" "proxmox-ubuntu-20" {
  proxmox_url = "https://${var.proxmox_host}:8006/api2/json"
  vm_name     = local.template_name
  vm_id       = "${var.proxmox_vm_id}"
  iso_file     = "${var.proxmox_iso_file}"
  iso_checksum = "${var.proxmox_iso_checksum}"
  username         = "${var.proxmox_user}"
  password         = "${var.proxmox_pass}"
  node             = "${var.proxmox_node}"

  ssh_username           = "${var.ssh_username}"
  ssh_password           = "${var.ssh_password}"
  ssh_timeout            = "24h"
  ssh_pty                = true
  ssh_handshake_attempts = 20

  # ovmf tries the empty disk first, so the iso's grub menu shows ~15s after start and boots at ~45s
  boot_wait      = var.uefi ? "25s" : "6s"
  http_directory = "${var.http_directory}"
  boot_command = [
      "c",
      "linux /casper/vmlinuz --- autoinstall ${local.autoinstall_source} ",
      "<enter><wait><wait><wait><wait>",
      "initrd /casper/initrd<enter><wait>",
      "boot<enter>"
    ]
  insecure_skip_tls_verify = true

  template_name        = local.template_name
  template_description = local.template_description
  unmount_iso          = true

  cloud_init = true
  cloud_init_storage_pool = "${var.proxmox_storage_pool}"

  memory     = 8192
  cores      = 2
  sockets    = 1
  scsi_controller = "virtio-scsi-pci"
  os         = "l26"
  qemu_agent = true

  # left unset for the bios build, so proxmox keeps its seabios / i440fx defaults
  bios    = var.uefi ? "ovmf" : null
  machine = var.uefi ? "q35" : null
  dynamic "efi_config" {
    for_each = var.uefi ? [1] : []
    content {
      efi_storage_pool  = var.proxmox_storage_pool
      efi_type          = "4m"
      pre_enrolled_keys = true
    }
  }

  disks {
    type              = "scsi"
    disk_size         = "20G"
    storage_pool      = "${var.proxmox_storage_pool}"
    storage_pool_type = "lvm"
    format            = "raw"
  }
  
  dynamic "additional_iso_files" {
    for_each = var.uefi ? [1] : []
    content {
      type             = "ide"
      index            = 3
      cd_files         = ["${local.cidata_directory}/user-data", "${local.cidata_directory}/meta-data"]
      cd_label         = "cidata"
      iso_storage_pool = "local"
      unmount          = true
    }
  }

  network_adapters {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = false
  }
}

build {
  sources = ["source.proxmox-iso.proxmox-ubuntu-20"]
  # copy the 99_pve.cfg file to /tmp, to be added to /etc/cloud/cloud.cfg.d/99_pve.cfg
  # as per - https://pve.proxmox.com/wiki/Cloud-Init_FAQ#Creating_a_custom_cloud_image
  provisioner "file" {
    source = "files/99_pve.cfg.txt"
    destination = "/tmp/99_pve.cfg"
  }

  # wait for cloud-init to finish, copy above file to /etc/cloud/cloud.cfg.d
  # prepare the vm for being a template as per https://www.learnlinux.tv/proxmox-ve-full-course-class-6-creating-virtual-machine-templates/
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 3; done",
      "echo moving files",
      "sudo mv /tmp/99_pve.cfg /etc/cloud/cloud.cfg.d/99_pve.cfg",
      "echo removing host keys",
      "sudo rm /etc/ssh/ssh_host_*",
      "echo zeroing the machine id",
      "sudo truncate -s 0 /etc/machine-id",
      "echo removing the other machine-id",
      "sudo rm /var/lib/dbus/machine-id",
      "echo creating symlink",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "echo apt clean",
      "sudo apt clean",
      "echo removing packages",
      "sudo apt autoremove" 
    ]
  }

  # uefi build only: fail before the template is created if it won't secure boot, or if the disk
  # isn't esp / boot / lvm on sda1 / sda2 / sda3 (terraform's resize script grows partition 3)
  provisioner "shell" {
    inline = var.uefi ? [
      "echo checking uefi / secure boot",
      "[ -d /sys/firmware/efi ]",
      "sudo mokutil --sb-state | grep -q 'SecureBoot enabled'",
      "dpkg -s shim-signed grub-efi-amd64-signed > /dev/null",
      "echo checking disk layout",
      "[ \"$(lsblk -nr -o NAME,TYPE /dev/sda | awk '$2 == \"part\" { print $1 }' | xargs)\" = 'sda1 sda2 sda3' ]",
      "[ \"$(findmnt -n -o SOURCE /boot/efi)\" = /dev/sda1 ]",
      "[ \"$(findmnt -n -o SOURCE /boot)\" = /dev/sda2 ]",
      "sudo pvs --noheadings -o pv_name,vg_name | grep -Eq '/dev/sda3 +ubuntu-vg'",
      "sudo lvs ubuntu-vg/ubuntu-lv > /dev/null",
      "echo cleaning cloud-init state",
      "sudo cloud-init clean --logs"
    ] : ["echo bios build, skipping uefi checks"]
  }
}