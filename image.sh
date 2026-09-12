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

# Build the installation ISO. Use the -e form: loading install.scm as a file
# trips over module resolution inside the container.
image="$(guix system image --verbosity=3 -t iso9660 -e '(@ (gnu system install) installation-os)')"
echo "built image: ${image}"

mkdir -p /out
cp "${image}" "/out/guix-install-${arch}-linux.iso"
ls -lh /out
