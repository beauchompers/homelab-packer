# rhel 9.8 kickstart, rendered by packer (templatefile) onto the OEMDRV cd, which anaconda reads automatically
text
eula --agreed
firstboot --disabled
lang en_US.UTF-8
keyboard us
timezone America/Denver --utc

network --bootproto=dhcp --device=link --activate --onboot=yes
# the boot iso has no packages, registering gives the install red hat's cdn repos
rhsm --organization="${rhsm_org}" --activation-key="${rhsm_activation_key}"

rootpw --lock
user --name=${ssh_username} --groups=wheel --password="${ssh_password}" --plaintext
selinux --enforcing
firewall --enabled --ssh
services --enabled=sshd,qemu-guest-agent

# same layout as the ubuntu templates, terraform's resize script grows partition 3 (the pv, last):
# 1 = bios boot or esp, 2 = /boot, 3 = lvm with rhel-vg/rhel-lv on /
ignoredisk --only-use=sda
zerombr
clearpart --all --initlabel --disklabel=gpt --drives=sda
bootloader --boot-drive=sda
%{ if uefi ~}
part /boot/efi --fstype=efi --size=600 --ondisk=sda
%{ else ~}
part biosboot --fstype=biosboot --size=1 --ondisk=sda
%{ endif ~}
part /boot --fstype=xfs --size=1024 --ondisk=sda
part pv.01 --size=1 --grow --ondisk=sda
volgroup rhel-vg pv.01
logvol / --vgname=rhel-vg --name=rhel-lv --fstype=xfs --size=1 --grow

reboot --eject

%packages
@^minimal-environment
qemu-guest-agent
cloud-init
cloud-utils-growpart
# sgdisk and parted are used by terraform's resize script
gdisk
parted
%{ if uefi ~}
shim-x64
grub2-efi-x64
mokutil
%{ endif ~}
%end

%post
echo "${ssh_username} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${ssh_username}
chmod 440 /etc/sudoers.d/${ssh_username}
# keep cloud-init from configuring the vm during the build, packer re-enables it before templating
touch /etc/cloud/cloud-init.disabled
%end
