#!/usr/bin/env bash
set -euo pipefail

export PATH="/var/guix/profiles/per-user/root/current-guix/bin:${PATH}"

rm -f /var/guix/daemon-socket/socket
guix-daemon --disable-chroot --build-users-group=guixbuild --max-jobs=4 --cores=4 &
DAEMON_PID=$!
trap 'kill $DAEMON_PID 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
  [ -S /var/guix/daemon-socket/socket ] && break
  sleep 1
done
[ -S /var/guix/daemon-socket/socket ] || { echo "guix-daemon failed to start" >&2; exit 1; }

PULL_OK=0
for attempt in $(seq 1 5); do
  echo "guix pull: attempt ${attempt}/5"
  if guix pull --channels=/workspace/channels.scm; then
    PULL_OK=1
    break
  fi
  echo "guix pull failed; retrying in 5s..."
  sleep 5
done
[ "${PULL_OK}" = "1" ] || { echo "guix pull failed after retries" >&2; exit 1; }
