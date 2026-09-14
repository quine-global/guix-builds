#!/usr/bin/env bash
set -euo pipefail

# Clone the pinned Guix commit, verify its authenticity, apply local debugging
# patches, sign the result with our own key, and write a channels file that
# Guix will accept (the channel is named 'guix' with a valid introduction).
# Called from pull.sh before 'guix pull'.

SRC=/tmp/guix-src
CHANNELS=/workspace/channels.scm
FINGERPRINT="E17D867D37C0603143EFE9437EFF749EC5D6018C"
FINGERPRINT_SPACED="E17D 867D 37C0 6031 43EF E943 7EFF 749E C5D6 018C"

# Pinned Guix commit from channels.scm.
COMMIT="$(grep -oE '\(commit "[0-9a-f]{40}"\)' "$CHANNELS" | grep -oE '[0-9a-f]{40}')"
[ -n "$COMMIT" ] || { echo "error: no pinned commit in channels.scm" >&2; exit 1; }
echo "pinned Guix commit: $COMMIT"

# Shallow-clone the pinned commit. The keyring branch is fetched only as a
# remote-tracking ref (for the local integrity check below), NOT as a local
# branch, so that guix pull's own clone of this repo only sees the 'patched'
# branch and never trips over the keyring tip.
rm -rf "$SRC"
git init -q "$SRC"
git -C "$SRC" remote add origin https://codeberg.org/guix/guix.git
git -C "$SRC" fetch -q --depth 1 origin "$COMMIT"
git -C "$SRC" fetch -q --depth 1 origin refs/heads/keyring:refs/remotes/origin/keyring
git -C "$SRC" checkout -q -b patched "$COMMIT"

# Import the official signing keys and verify the pinned commit's signature,
# so we patch a known-authentic base.
export GNUPGHOME=/tmp/gnupg
rm -rf "$GNUPGHOME"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
echo "trust-model always" > "$GNUPGHOME/gpg.conf"
mkdir -p /tmp/keyring
git -C "$SRC" archive origin/keyring | tar -x -C /tmp/keyring
for k in /tmp/keyring/*.key; do
  gpg --batch --import "$k" >/dev/null 2>&1 || true
done
VERIFY_OUTPUT="$(git -C "$SRC" verify-commit "$COMMIT" 2>&1 || true)"
echo "$VERIFY_OUTPUT"
if ! grep -q "Good signature" <<< "$VERIFY_OUTPUT"; then
  echo "error: pinned commit $COMMIT failed signature verification" >&2
  exit 1
fi
echo "verified pinned commit signature"

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

# Point the channel's keyring-reference at the main branch. The keyring is
# loaded (unconditionally) but never used for verification, because
# first-signed-commit equals the channel commit (an empty commit range). So an
# empty keyring off the 'patched' branch is fine and avoids needing a separate
# keyring branch that libgit2 refuses to fetch.
python3 - "$SRC" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]) / ".guix-channel"
s = p.read_text()
old = '''(keyring-reference "keyring")'''
new = '''(keyring-reference "patched")'''
assert old in s, "keyring-reference not found in .guix-channel"
p.write_text(s.replace(old, new, 1))
print("patched .guix-channel keyring-reference")
PY

# Sign the patched commit with our key.
gpg --batch --import /workspace/keys/private.key >/dev/null 2>&1
git -C "$SRC" add -A
git -C "$SRC" \
  -c user.email=debug@guix-iso.invalid \
  -c user.name="guix-iso debug" \
  -c user.signingkey="$FINGERPRINT" \
  commit -q -S -m "debug: console shepherd log + verbose kernel"
NEW_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
echo "patched commit: $NEW_COMMIT"

cat > /tmp/channels-local.scm <<EOF
(list (channel
        (name 'guix)
        (url "file://$SRC")
        (commit "$NEW_COMMIT")
        (introduction
         (make-channel-introduction
          "$NEW_COMMIT"
          (openpgp-fingerprint
           "$FINGERPRINT_SPACED")))))
EOF
echo "wrote /tmp/channels-local.scm"
