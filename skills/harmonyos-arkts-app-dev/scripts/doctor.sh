#!/usr/bin/env bash
set -u

# HarmonyOS ArkTS project doctor — read-only checks.
# Usage: ./doctor.sh [project-dir] [device-serial]

PROJECT_DIR="${1:-$(pwd)}"
DEVICE="${2:-}"

cd "$PROJECT_DIR" 2>/dev/null || {
  echo "ERROR: project dir not found: $PROJECT_DIR"
  exit 1
}

echo "== project =="
pwd
echo

echo "== tools =="
command -v devecocli >/dev/null 2>&1 && devecocli --version 2>/dev/null | head -1 || echo "devecocli: MISSING"
if command -v hdc >/dev/null 2>&1; then
  echo "hdc: $(command -v hdc)"
else
  echo "hdc: not in PATH (use devecocli device ...)"
fi
echo

echo "== devices =="
devecocli device list 2>/dev/null | sed -n '1,12p' || true
echo

if [ -n "$DEVICE" ]; then
  echo "== target device =="
  echo "$DEVICE"
  devecocli device status --device "$DEVICE" 2>/dev/null | sed -n '1,6p' || true
  devecocli device app foreground --device "$DEVICE" 2>/dev/null | sed -n '1,6p' || true
  echo
fi

echo "== sdk / version =="
grep -nE "compatibleSdkVersion|targetSdkVersion|versionCode|versionName" build-profile.json5 AppScope/app.json5 2>/dev/null | sed -n '1,20p' || true
echo

echo "== signing config =="
if [ -f build-profile.json5 ]; then
  if grep -q "signingConfigs" build-profile.json5; then
    echo "signingConfigs: present"
    python3 - <<'PY' 2>/dev/null || true
import re
from pathlib import Path
t = Path('build-profile.json5').read_text()
names = sorted(set(re.findall(r'default_[^\"\']+?\.(?:p12|cer|p7b)', t)))
for name in names:
    p = Path.home() / '.ohos' / 'config' / name
    print(('  OK   ' if p.exists() else '  MISS ') + name)
PY
  else
    echo "signingConfigs: MISSING"
  fi
else
  echo "build-profile.json5: MISSING"
fi
echo

echo "== restricted ACL permissions =="
ACL_MATCHES=$(grep -R -n "FILE_ACCESS_PERSIST" --include="module.json5" \
  --exclude-dir=build --exclude-dir=.hvigor --exclude-dir=oh_modules . 2>/dev/null || true)
if [ -n "$ACL_MATCHES" ]; then
  printf '%s\n' "$ACL_MATCHES"
  echo "  ^ remove if not strictly required; it blocks auto signing"
else
  echo "none found"
fi
echo

echo "== sensitive files in git status =="
git status --porcelain 2>/dev/null | grep -Ei "\.(p12|cer|p7b|csr|jks|keystore)|secret|keystore" || echo "none in working tree changes"
echo

echo "== build artifact =="
HAP="entry/build/default/outputs/default/entry-default-signed.hap"
if [ -f "$HAP" ]; then
  ls -lh "$HAP"
  stat -f "mtime: %Sm" "$HAP" 2>/dev/null || true
else
  echo "missing: $HAP (run devecocli build --modules entry --build-mode debug)"
fi
echo

echo "== git =="
git status -sb 2>/dev/null | sed -n '1,10p' || true
git log -1 --oneline 2>/dev/null || true

echo
echo "done. This script is read-only."
