# Ubuntu 22.04.03 

Proxmox Ubuntu 22.04 - Cloud Init Enabled

Create a vars.json file (or hcl if you want), and build using:

```
packer build -var-file=vars.json .
```

## UEFI + Secure Boot template

Set `uefi=true` and a free VM ID to build `<proxmox_template_name>-uefi` instead. It uses OVMF with
pre-enrolled Secure Boot keys and a q35 machine. Its autoinstall config is read from a `cidata` CD built
from `<http_directory>_uefi` (for example `http_uefi` or `http_homelab_uefi`) instead of over http, which
needs `xorriso` on the machine running packer (`brew install xorriso`):

```
packer build -var-file=readylabone.pkrvars.hcl -var uefi=true -var proxmox_vm_id=<free id> .
```

The build fails before creating the template if Secure Boot isn't enabled, or if the disk isn't
ESP / `/boot` / LVM on `sda1` / `sda2` / `sda3`.
