#!/usr/bin/env bash
set -euo pipefail

arch="${1:-x86_64}"

export PATH="/root/.config/guix/current/bin:${PATH}"
. /root/.config/guix/current/etc/profile

rm -f /var/guix/daemon-socket/socket
guix-daemon --disable-chroot --max-jobs=2 --cores=2 --max-silent-time=0 --build-users-group=guixbuild &
DAEMON_PID=$!
trap 'kill $DAEMON_PID 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
  [ -S /var/guix/daemon-socket/socket ] && break
  sleep 1
done
[ -S /var/guix/daemon-socket/socket ] || { echo "guix-daemon failed to start" >&2; exit 1; }

# Build the installation image. Use the -e form: loading install.scm as a file
# trips over module resolution inside the container.
# x86_64 boots via BIOS (iso9660, grub-bootloader); aarch64 boots via UEFI
# (efi-raw, grub-efi). The installer hardcodes a BIOS bootloader unless built
# with #:efi-only? #t, so set that for aarch64.
if [ "${arch}" = "aarch64" ]; then
  image_type="efi-raw"
  ext="raw"
  image_expr='((@ (gnu system install) make-installation-os) #:efi-only? #t)'
else
  image_type="iso9660"
  ext="iso"
  image_expr='(@ (gnu system install) installation-os)'
fi

image="$(guix system image --verbosity=3 -t "${image_type}" -e "${image_expr}")"
echo "built image: ${image}"

mkdir -p /out
cp "${image}" "/out/guix-install-${arch}-linux.${ext}"
ls -lh /out
