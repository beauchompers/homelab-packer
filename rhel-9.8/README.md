# RHEL 9.8

Proxmox RHEL 9.8 - Cloud Init Enabled, built from the RHEL 9.8 boot ISO.

The boot ISO has no packages, so the install registers with Red Hat using an activation key and
downloads them from the CDN. The template is unregistered before it's converted. Create a vars file
(`*.pkrvars.hcl` is gitignored) with the Proxmox settings plus:

```
rhsm_org            = "<organization id>"
rhsm_activation_key = "<activation key name>"
```

Both are on console.redhat.com > Inventory > System Configuration > Activation Keys. Then build using:

```
packer build -var-file=readylabone.pkrvars.hcl .
```

The kickstart (`ks.pkrtpl.hcl`) is rendered by packer onto a CD labelled `OEMDRV`, which the installer
reads by itself. This needs `xorriso` on the machine running packer (`brew install xorriso`).

The disk matches the Ubuntu templates for Terraform's resize script: `sda1` BIOS boot (or ESP),
`sda2` `/boot`, `sda3` LVM with `rhel-vg/rhel-lv` on `/`, so the script resizes
`/dev/mapper/rhel--vg-rhel--lv`.

## UEFI + Secure Boot template

Set `uefi=true` and a free VM ID to build `<proxmox_template_name>-uefi` instead, with OVMF,
pre-enrolled Secure Boot keys and a q35 machine:

```
packer build -var-file=readylabone.pkrvars.hcl -var uefi=true -var proxmox_vm_id=<free id> .
```

Either build fails before creating the template if the disk layout is wrong, if (UEFI) Secure Boot
isn't enabled, or if the org ID or activation key is left anywhere on the disk.
