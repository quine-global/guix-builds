#!/usr/bin/env bash
set -euo pipefail

FW_DIR="/Applications/UTM.app/Contents/Resources/qemu"
DIR="$(cd "$(dirname "$0")" && pwd)"

# Create the 64 MiB NVRAM vars flash from the EDK2 template on first run.
if [ ! -s "$DIR/blank-vars.fd" ]; then
  cp "$FW_DIR/edk2-arm-vars.fd" "$DIR/blank-vars.fd"
  truncate -s 64M "$DIR/blank-vars.fd"
fi

exec qemu-system-aarch64 \
  -machine virt \
  -accel hvf -cpu host -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file="$FW_DIR/edk2-aarch64-code.fd" \
  -drive if=pflash,format=raw,file="$DIR/blank-vars.fd" \
  -drive if=virtio,format=qcow2,file=/Users/morkswork/Downloads/guix-install-aarch64-linux.qcow2 \
  -drive if=virtio,format=qcow2,file="$DIR/blank-32g.qcow2" \
  -nic user,model=virtio-net-pci \
  -display none -serial stdio -monitor none \
  "$@"
