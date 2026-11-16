# RHEL 9.8

Builds Proxmox templates from the RHEL 9.8 boot ISO (`rhel-9.8-x86_64-boot.iso`):

- `packer-rhel-98`: SeaBIOS (default)
- `packer-rhel-98-uefi`: OVMF + Secure Boot (pre-enrolled keys) on a q35 machine, with `-var uefi=true`

## Vars file

Create a vars file, for example `readylabone.pkrvars.hcl` (`*.pkrvars.hcl` is gitignored), with the
Proxmox settings (`proxmox_host`, `proxmox_node`, `proxmox_user`, `proxmox_pass`, `proxmox_storage_pool`,
`proxmox_iso_file`, `proxmox_iso_checksum`, `proxmox_vm_id`, `proxmox_template_name`) and:

- `ssh_username` / `ssh_password`: the kickstart creates this user, with passwordless sudo, and packer
  logs in as it.
- `rhsm_org` / `rhsm_activation_key`: the boot ISO has no packages, so the install registers with Red
  Hat and downloads them from the CDN. Both are on console.redhat.com > Inventory > System Configuration
  > Activation Keys. Avoid `"` in these and in `ssh_password`, as they go into the kickstart as-is.

## Build

```
packer init .
packer build -var-file=readylabone.pkrvars.hcl .
packer build -var-file=readylabone.pkrvars.hcl -var uefi=true -var proxmox_vm_id=<free id> .
```

Packer won't reuse a VM ID, so delete the old template before rebuilding. The build needs the proxmox
plugin 1.2.3 or later (1.2.2 doesn't pass `cpu_type` to the VM), and `xorriso` on the machine running
packer (`brew install xorriso`).

## How the installer gets its config

Packer renders `ks.pkrtpl.hcl` with the vars above and puts it on a CD labelled `OEMDRV` as `ks.cfg`,
which the installer reads by itself. The boot command only picks "Install Red Hat Enterprise Linux 9.8"
in the ISO's GRUB menu (the default is "Test this media & install").

## What the template gets

- GPT on `/dev/sda`: `sda1` BIOS boot (ESP on UEFI), `sda2` `/boot`, `sda3` LVM with `rhel-vg/rhel-lv`
  filling it, all XFS, no swap.
- `cpu_type = "x86-64-v2-AES"`. RHEL 9 needs x86-64-v2 and kernel panics on `kvm64`, so clones need a v2
  or newer CPU type too.
- `files/10-resize-root.sh` at `/var/lib/cloud/scripts/per-instance/`, which grows partition 3, the PV and
  `rhel-lv` to fill a bigger clone disk on its first boot.
- `console=tty0 console=ttyS0,115200` in the default kernel arguments, and a `serial0` socket.
- cloud-init limited to the Proxmox drive, with password SSH allowed (`files/99_pve.cfg.txt`; RHEL's
  default turns it off), and cleaned, with SSH host keys and machine-id removed, so each clone starts
  fresh. qemu-guest-agent is enabled (RHEL's default blocks `guest-exec`, which is left as is).
- Unregistered from Red Hat, with the kickstart copies and install logs removed. Clones aren't
  registered, so a first-boot `dnf upgrade` (Proxmox `ciupgrade`) fails unless they're registered.

The build fails before the template is created if the disk layout is wrong, `rhel-lv` doesn't fill the
disk, the serial console isn't on the kernel command line, (UEFI) Secure Boot isn't enabled, or the org
ID or activation key is left anywhere on the disk.
