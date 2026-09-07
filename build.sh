#!/usr/bin/env bash
set -euo pipefail

GUIX_PROFILE="/var/guix/profiles/per-user/root/current-guix"
export PATH="${GUIX_PROFILE}/bin:${PATH}"

# Start the build daemon.
guix-daemon --build-users-group=guixbuild --max-jobs=4 --cores=4 &
DAEMON_PID=$!

# Wait for the daemon socket to appear.
for _ in $(seq 1 30); do
  [ -S /var/guix/daemon-socket/socket ] && break
  sleep 1
done
[ -S /var/guix/daemon-socket/socket ] || { echo "guix-daemon failed to start" >&2; exit 1; }

# Pull the pinned channels (updates ~/.config/guix/current).
guix pull --channels=/workspace/channels.scm

# Switch to the freshly pulled guix.
export PATH="/root/.config/guix/current/bin:${PATH}"

# Build the installation ISO.
image="$(guix system image -t iso9660 gnu/system/install.scm)"
echo "built image: ${image}"

mkdir -p /out
cp "${image}" /out/guix-install-x86_64-linux.iso
ls -lh /out
