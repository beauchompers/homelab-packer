packer {
  required_plugins {
    proxmox = {
      version = "~>1"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# uefi = true builds the UEFI (OVMF) + Secure Boot variant of the template, named <template>-uefi
locals {
  template_name        = var.uefi ? "${var.proxmox_template_name}-uefi" : var.proxmox_template_name
  template_description = var.uefi ? "${var.proxmox_template_description} (UEFI + Secure Boot)" : var.proxmox_template_description
}

source "proxmox-iso" "rhel" {
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
  # a kickstart error or failed registration leaves anaconda waiting, so don't wait a day for ssh
  ssh_timeout            = "1h"
  ssh_pty                = true
  ssh_handshake_attempts = 20

  # ovmf tries the empty disk first, so its grub menu shows later than under seabios
  boot_wait = var.uefi ? "25s" : "10s"
  # the iso's grub menu defaults to "test this media & install", up selects "install red hat enterprise linux 9.8".
  # the kickstart comes from the OEMDRV cd below, so nothing else needs typing
  boot_command = ["<up><enter>"]
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
    format            = "raw"
  }

  # anaconda loads ks.cfg from a cd labelled OEMDRV by itself, no inst.ks or http server needed
  additional_iso_files {
    type             = "ide"
    index            = 3
    cd_label         = "OEMDRV"
    cd_content = {
      "ks.cfg" = templatefile("ks.pkrtpl.hcl", {
        uefi                = var.uefi
        rhsm_org            = var.rhsm_org
        rhsm_activation_key = var.rhsm_activation_key
        ssh_username        = var.ssh_username
        ssh_password        = var.ssh_password
      })
    }
    iso_storage_pool = "local"
    unmount          = true
  }

  network_adapters {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = false
  }
}

build {
  sources = ["source.proxmox-iso.rhel"]

  # as per - https://pve.proxmox.com/wiki/Cloud-Init_FAQ#Creating_a_custom_cloud_image
  provisioner "file" {
    source      = "files/99_pve.cfg.txt"
    destination = "/tmp/99_pve.cfg"
  }

  # fail before the template is created if the disk isn't what terraform's resize script expects
  # (bios boot or esp / boot / lvm on sda1 / sda2 / sda3, rhel-vg/rhel-lv), or uefi won't secure boot
  provisioner "shell" {
    inline = concat([
      "echo checking disk layout",
      "[ \"$(lsblk -nr -o NAME,TYPE /dev/sda | awk '$2 == \"part\" { print $1 }' | xargs)\" = 'sda1 sda2 sda3' ]",
      "[ \"$(findmnt -n -o SOURCE /boot)\" = /dev/sda2 ]",
      "sudo pvs --noheadings -o pv_name,vg_name | grep -Eq '/dev/sda3 +rhel-vg'",
      "sudo lvs rhel-vg/rhel-lv > /dev/null",
      "[ \"$(findmnt -n -o SOURCE /)\" = /dev/mapper/rhel--vg-rhel--lv ]",
      "command -v sgdisk parted > /dev/null",
      "systemctl is-enabled qemu-guest-agent",
      ], var.uefi ? [
      "echo checking uefi / secure boot",
      "[ -d /sys/firmware/efi ]",
      "[ \"$(findmnt -n -o SOURCE /boot/efi)\" = /dev/sda1 ]",
      "sudo mokutil --sb-state | grep -q 'SecureBoot enabled'",
      "rpm -q shim-x64 grub2-efi-x64 > /dev/null",
      ] : [
      "[ ! -d /sys/firmware/efi ]",
    ])
  }

  # unregister so clones don't share one red hat identity, remove everything that holds the org id or
  # activation key, then prepare the vm for being a template
  provisioner "shell" {
    inline = [
      "echo unregistering",
      "sudo subscription-manager unregister",
      "sudo subscription-manager clean",
      "sudo dnf clean all",
      "echo removing kickstart copies and install logs",
      "sudo rm -rf /root/anaconda-ks.cfg /root/original-ks.cfg /var/log/anaconda /var/log/rhsm/*",
      "sudo journalctl --rotate && sudo journalctl --vacuum-time=1s",
      "! sudo grep -rIlq -e '${var.rhsm_org}' -e '${var.rhsm_activation_key}' /root /etc /var/log",
      "echo moving files",
      # install + restorecon, as mv from /tmp keeps its tmp_t selinux label and cloud-init couldn't read it
      "sudo install -o root -g root -m 644 /tmp/99_pve.cfg /etc/cloud/cloud.cfg.d/99_pve.cfg",
      "sudo restorecon /etc/cloud/cloud.cfg.d/99_pve.cfg",
      "rm -f /tmp/99_pve.cfg",
      "echo removing host keys",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "echo zeroing the machine id",
      "sudo truncate -s 0 /etc/machine-id",
      "echo re-enabling cloud-init for clones",
      "sudo rm -f /etc/cloud/cloud-init.disabled",
      "sudo cloud-init clean --logs"
    ]
  }
}
