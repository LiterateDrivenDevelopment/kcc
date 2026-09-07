#!/bin/bash
# Boot the kcc-built tinyconfig bzImage on a NATIVE x86-64 Linux host (KVM).
# Deterministic and fast, unlike TCG-under-emulation on an ARM Mac.
# Usage: native_boot.sh [bzImage] [timeout_seconds]
set -uo pipefail
IMG="${1:-/w/bzImage.tiny}"
T="${2:-60}"
[ -f "$IMG" ] || { echo "no bzImage at $IMG"; exit 1; }
KVM=""; [ -e /dev/kvm ] && KVM="-enable-kvm -cpu host"
echo "booting $IMG ($(stat -c%s "$IMG") bytes)${KVM:+ with KVM}, ${T}s cap..."
timeout "$T" qemu-system-x86_64 $KVM -M pc -m 512 -kernel "$IMG" -nographic \
  -serial file:/w/boot_native.log -display none -no-reboot \
  -append "console=ttyS0,115200 earlyprintk=ttyS0,115200,keep panic=-1 reboot=t"
echo "qemu exited rc=$? ($(wc -c < /w/boot_native.log 2>/dev/null) bytes captured)"
echo "=================== SERIAL ==================="
sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' /w/boot_native.log 2>/dev/null
echo "============================================="
grep -qiE "Linux version|start_kernel|No working init|Unable to mount root|VFS:" /w/boot_native.log \
  && echo "*** kcc-compiled Linux reached start_kernel/init ***" \
  || echo "(no start_kernel yet — use -d cpu_reset,int to get the crash RIP; see REPRODUCE-native.md)"
