# Ubuntu 22.04

Builds Proxmox templates from the Ubuntu 22.04 live server ISO (built with 22.04.5):

- `packer-ubuntu-2204`: SeaBIOS (default)
- `packer-ubuntu-2204-uefi`: OVMF + Secure Boot (pre-enrolled keys) on a q35 machine, with `-var uefi=true`

## Vars file

Create a vars file, for example `readylabone.pkrvars.hcl` (`*.pkrvars.hcl` is gitignored), with the
Proxmox settings (`proxmox_host`, `proxmox_node`, `proxmox_user`, `proxmox_pass`, `proxmox_storage_pool`,
`proxmox_iso_file`, `proxmox_iso_checksum`, `proxmox_vm_id`, `proxmox_template_name`) and:

- `ssh_username` / `ssh_password`: the user packer logs in as. It must match the user created in
  `user-data` (`ubuntu` / `ubuntu` in `http/`).
- `http_directory`: the autoinstall config, `http` by default. To use your own user, password or SSH key,
  copy it to a directory named `http_homelab*`, which is gitignored. The UEFI build reads
  `<http_directory>_uefi` instead (`http_uefi`, or your own `http_homelab_uefi`).

## Build

```
packer init .
packer build -var-file=readylabone.pkrvars.hcl .
packer build -var-file=readylabone.pkrvars.hcl -var uefi=true -var proxmox_vm_id=<free id> .
```

Packer won't reuse a VM ID, so delete the old template before rebuilding.

## How the installer gets its config

- **BIOS:** the boot command types the kernel command line in GRUB, and the installer fetches
  `user-data` from packer's http server (`ds=nocloud-net`).
- **UEFI:** packer puts `user-data` on a CD labelled `cidata`, and the boot command only adds
  `autoinstall`. The live installer couldn't reach packer's http server early in boot on q35. This
  needs `xorriso` on the machine running packer (`brew install xorriso`). The UEFI `user-data` matches
  the NIC as `en*`, as q35 names it `enp6s18` rather than `ens18`.

## What the template gets

- GPT on `/dev/sda`: `sda1` BIOS boot (ESP on UEFI), `sda2` `/boot`, `sda3` LVM with `ubuntu-vg/ubuntu-lv`
  filling it (`sizing-policy: all`).
- `files/10-resize-root.sh` at `/var/lib/cloud/scripts/per-instance/`, which grows partition 3, the PV and
  `ubuntu-lv` to fill a bigger clone disk on its first boot.
- `console=tty0 console=ttyS0,115200` instead of the installer's `autoinstall` on the kernel command line,
  and a `serial0` socket.
- cloud-init limited to the Proxmox drive (`files/99_pve.cfg.txt`) and cleaned, with
  `/var/log/installer`, SSH host keys and machine-id removed, so each clone starts fresh.
- The installer ISO is unmounted.

The build fails before the template is created if `ubuntu-lv` doesn't fill the disk, if `autoinstall`
is still in `grub.cfg`, or (UEFI) if Secure Boot isn't enabled or the disk isn't ESP / `/boot` / LVM on
`sda1` / `sda2` / `sda3`.
