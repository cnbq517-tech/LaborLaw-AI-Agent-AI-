#!/bin/sh
# Writes the built-in model service the app ships with:
# harmony-app/entry/src/main/resources/rawfile/builtin_service.json.
# The file is ignored by Git and must never be committed. Without it the app
# builds and runs with only the user's own model settings.
#
# The key is read without echoing and stored XOR-ed with the mask in
# services/ModelQuota.ets, so it is not a plain string in the package. Anyone
# who unpacks the app can still recover it: use a key made for the app, with a
# small balance and a spending alert, and revoke it when no longer needed.
#
#   ./tools/harmony/builtin-service/set.sh [base-url] [model]
#   ./tools/harmony/builtin-service/set.sh --remove

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
OUT="$ROOT/harmony-app/entry/src/main/resources/rawfile/builtin_service.json"

if [ "${1:-}" = "--remove" ]; then
  rm -f "$OUT"
  echo "Removed $OUT"
  exit 0
fi

BASE_URL=${1:-https://api.deepseek.com}
MODEL=${2:-deepseek-v4-flash}

printf 'API key for %s (%s): ' "$BASE_URL" "$MODEL"
stty -echo 2>/dev/null || true
read -r KEY
stty echo 2>/dev/null || true
printf '\n'
if [ -z "$KEY" ]; then
  echo "No key given; nothing written." >&2
  exit 1
fi

BASE_URL="$BASE_URL" MODEL="$MODEL" KEY="$KEY" OUT="$OUT" python3 -I - <<'PY'
import json, os, re, sys
mask = 'laborlaw-harmony-builtin'
# Drop what a terminal can add around a paste: arrow keys and other escape
# sequences, bracketed-paste markers, spaces and line ends.
key = re.sub(r'\x1b\[[0-9;]*[A-Za-z~]', '', os.environ['KEY'])
key = re.sub(r'\s', '', key)
if not re.fullmatch(r'[A-Za-z0-9_\-.]+', key):
    sys.exit('The key has unexpected characters; nothing written. Paste it again without other keys.')
encoded = ''.join('%02x' % (ord(c) ^ ord(mask[i % len(mask)])) for i, c in enumerate(key))
with open(os.environ['OUT'], 'w') as f:
    json.dump({'baseUrl': os.environ['BASE_URL'], 'model': os.environ['MODEL'], 'key': encoded}, f)
print("Key length %d, starts with %s" % (len(key), key[:3]))
PY
echo "Wrote $OUT"
