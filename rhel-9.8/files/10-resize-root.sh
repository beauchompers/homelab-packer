#!/bin/sh
# Installed by packer at /var/lib/cloud/scripts/per-instance/10-resize-root.sh, so cloud-init runs it
# once, as root, on each clone's first boot. It grows rhel-vg/rhel-lv to fill the disk, which
# cloud-init's growpart skips for an LVM root ("Resizing mapped device ... skipped").
#
# It only acts when /dev/sda3 is the rhel-vg PV and the last partition, otherwise it logs and exits 0.
# A step that really fails exits 1: boot carries on, and cloud-init status reports the error.

disk=/dev/sda
part=/dev/sda3
vg=rhel-vg
lv=/dev/mapper/rhel--vg-rhel--lv

log() { echo "10-resize-root: $*"; }
fail() { log "$*"; exit 1; }

if [ ! -b "$part" ]; then
  log "$part not found, nothing to do"
  exit 0
fi
if [ "$(pvs --noheadings -o vg_name "$part" 2>/dev/null | tr -d ' ')" != "$vg" ]; then
  log "$part is not the $vg PV, nothing to do"
  exit 0
fi
if [ "$(lsblk -nr -o NAME,TYPE "$disk" | awk '$2 == "part" { p = $1 } END { print p }')" != sda3 ]; then
  log "$part is not the last partition on $disk, nothing to do"
  exit 0
fi

# a bigger clone disk leaves the backup gpt header in the middle, move it to the end first
sgdisk --move-second-header "$disk" > /dev/null || fail "sgdisk --move-second-header failed"
# resizepart to the size it already has is a no-op, not an error
parted -s "$disk" 'resizepart 3 100%' || fail "parted resizepart 3 failed"
# make the kernel see the new partition size, so pvresize works without a reboot
partprobe "$disk" || fail "partprobe failed"
pvresize "$part" || fail "pvresize failed"

# lvresize returns an error when there's nothing to add, so only call it with free extents
free=$(vgs --noheadings -o vg_free_count "$vg" | tr -d ' ')
if [ "${free:-0}" -gt 0 ]; then
  lvresize --extents +100%FREE --resizefs "$lv" || fail "lvresize failed"
  log "grew $lv by $free extents"
else
  log "no free extents in $vg, $lv already fills the disk"
fi
df -h /
