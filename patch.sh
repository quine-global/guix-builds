#!/usr/bin/env bash
set -euo pipefail

# Clone the pinned Guix commit, apply local debugging patches, and write a
# channels.scm pointing at the patched checkout. Called from pull.sh before
# 'guix pull', so the changes flow into both the installer image and the
# system the installer produces.

SRC=/tmp/guix-src
CHANNELS=/workspace/channels.scm

# Pinned Guix commit from channels.scm.
COMMIT="$(grep -oE '\(commit "[0-9a-f]{40}"\)' "$CHANNELS" | grep -oE '[0-9a-f]{40}')"
[ -n "$COMMIT" ] || { echo "error: no pinned commit in channels.scm" >&2; exit 1; }
echo "pinned Guix commit: $COMMIT"

# Shallow-clone just that commit.
rm -rf "$SRC"
git init -q "$SRC"
git -C "$SRC" remote add origin https://codeberg.org/guix/guix.git
git -C "$SRC" fetch -q --depth 1 origin "$COMMIT"
git -C "$SRC" checkout -q FETCH_HEAD

# Route shepherd's log to the console, so boot failures are visible on screen
# instead of only in /var/log/messages.
python3 - "$SRC" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]) / "gnu/services/shepherd.scm"
s = p.read_text()
old = '''      ;; Start shepherd.
      (execl #$(file-append shepherd "/bin/shepherd")
             "shepherd" "--config"
             #$(shepherd-configuration-file services shepherd)))))'''
new = '''      ;; Start shepherd.  Log to the console so boot failures are visible.
      (execl #$(file-append shepherd "/bin/shepherd")
             "shepherd" "--config"
             #$(shepherd-configuration-file services shepherd)
             "--logfile" "/dev/console"))))'''
assert old in s, "shepherd-boot-gexp execl not found"
p.write_text(s.replace(old, new, 1))
print("patched shepherd-boot-gexp")
PY

# Make the kernel verbose by default (drop 'quiet').
python3 - "$SRC" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]) / "gnu/system.scm"
s = p.read_text()
old = '''        "quiet"))'''
new = '''        "verbose"))'''
assert s.count(old) == 1, f"expected one 'quiet' kernel arg, found {s.count(old)}"
p.write_text(s.replace(old, new, 1))
print("patched %default-kernel-arguments")
PY

# Commit deterministically (fixed dates => stable hash => cacheable across runs).
git -C "$SRC" add -A
export GIT_AUTHOR_DATE="2020-01-01T00:00:00 +0000"
export GIT_COMMITTER_DATE="2020-01-01T00:00:00 +0000"
git -C "$SRC" -c user.email=debug@invalid -c user.name=debug commit -q --no-gpg-sign \
  -m "debug: console shepherd log + verbose kernel"
NEW_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
echo "patched commit: $NEW_COMMIT"

cat > /tmp/channels-local.scm <<EOF
(list (channel
        (name 'guix)
        (url "file://$SRC")
        (commit "$NEW_COMMIT")))
EOF
echo "wrote /tmp/channels-local.scm"
