# Homelab Proxmox / Packer Builds

Repo for the Packer built vms for my home lab. Each directory builds Proxmox VM templates that
Terraform full-clones.

## Templates

| Directory | Template | Firmware | VM ID (readylabone) |
|---|---|---|---|
| `ubuntu-22.04` | `packer-ubuntu-2204` | SeaBIOS | 300 |
| `ubuntu-22.04` | `packer-ubuntu-2204-uefi` | OVMF + Secure Boot | 301 |
| `ubuntu-24.04` | `packer-ubuntu-2404` | SeaBIOS | 400 |
| `ubuntu-24.04` | `packer-ubuntu-2404-uefi` | OVMF + Secure Boot | 401 |
| `rhel-9.8` | `packer-rhel-98` | SeaBIOS | 500 |
| `rhel-9.8` | `packer-rhel-98-uefi` | OVMF + Secure Boot | 501 |
| `ubuntu-20.04` | Ubuntu 20.04.3 LTS (older build, not updated with the changes below) | SeaBIOS | |

Each directory builds the BIOS template by default, and the UEFI + Secure Boot one (OVMF, q35,
pre-enrolled keys) with `-var uefi=true`. See the README in each directory for details.

## What every clone gets

- **Disk:** GPT on `/dev/sda`. `sda1` is the BIOS boot partition (or the ESP on UEFI), `sda2` is
  `/boot`, `sda3` is the LVM PV with the root LV filling it: `ubuntu-vg/ubuntu-lv` on Ubuntu,
  `rhel-vg/rhel-lv` on RHEL.
- **Root resize on first boot:** `/var/lib/cloud/scripts/per-instance/10-resize-root.sh` grows the
  partition, PV and root LV to fill a bigger clone disk, once per clone. No SSH provisioning is
  needed.
- **cloud-init** with a Proxmox cloud-init drive (`ciuser`, `cipassword`, `sshkeys`, `ipconfig0`),
  cleaned before the template is created, so each clone gets its own machine-id and SSH host keys.
- **qemu-guest-agent**, so Proxmox reports the clone's IP.
- **Serial console:** a `serial0` socket and `console=tty0 console=ttyS0,115200` on the kernel command
  line.
- No installer ISO or install logs left behind.

## Requirements

- Packer, with the `hashicorp/proxmox` plugin 1.2.3 or later (`packer init .` in each directory).
- `xorriso` on the machine running Packer (`brew install xorriso`). The UEFI Ubuntu builds and both
  RHEL builds put their autoinstall / kickstart config on a CD.
- A vars file per directory with the Proxmox host, node, storage, ISO and VM ID, for example
  `readylabone.pkrvars.hcl`. `*.pkrvars.hcl` and `http_homelab*` are gitignored, so passwords, SSH keys
  and Red Hat credentials stay local.
- RHEL also needs a Red Hat organization ID and activation key (`rhsm_org`, `rhsm_activation_key`), as
  it installs from the boot ISO. The template is unregistered before it's created.

## Building

From the template's directory:

```
packer build -var-file=readylabone.pkrvars.hcl .
packer build -var-file=readylabone.pkrvars.hcl -var uefi=true -var proxmox_vm_id=<free id> .
```

A build fails if the VM ID is already in use, so delete the old template first when rebuilding. Each
build checks the disk layout (and Secure Boot on UEFI) before the template is created.

## Notes for Terraform clones

- RHEL clones need a CPU type of x86-64-v2 or newer (for example `x86-64-v2-AES` or `host`); with
  `kvm64` they kernel panic at boot.
- RHEL clones aren't registered, so set `ciupgrade = false` (or register them), otherwise cloud-init's
  first-boot `dnf upgrade` fails.
- On Ubuntu 22.04, the first-boot upgrade also refreshes snaps and can time out when the snap store is
  slow. `ciupgrade = false` avoids that too.
