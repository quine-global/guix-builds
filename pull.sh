#!/usr/bin/env bash
set -euo pipefail

export PATH="/var/guix/profiles/per-user/root/current-guix/bin:${PATH}"

DAEMON_PID=""
start_daemon() {
  rm -f /var/guix/daemon-socket/socket
  guix-daemon --disable-chroot --max-jobs=2 --cores=2 --max-silent-time=0 --build-users-group=guixbuild &
  DAEMON_PID=$!
  for _ in $(seq 1 30); do
    [ -S /var/guix/daemon-socket/socket ] && return 0
    sleep 1
  done
  return 1
}

stop_daemon() {
  if [ -n "${DAEMON_PID}" ]; then
    kill "${DAEMON_PID}" 2>/dev/null || true
    DAEMON_PID=""
  fi
}
trap stop_daemon EXIT

PULL_OK=0
for attempt in $(seq 1 5); do
  echo "guix pull: attempt ${attempt}/5"
  stop_daemon
  start_daemon || { echo "guix-daemon failed to start" >&2; exit 1; }
  if guix pull --verbosity=3 --channels=/workspace/channels.scm; then
    PULL_OK=1
    break
  fi
  echo "guix pull failed; retrying in 5s..."
  sleep 5
done
[ "${PULL_OK}" = "1" ] || { echo "guix pull failed after retries" >&2; exit 1; }
