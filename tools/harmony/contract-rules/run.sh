#!/bin/sh
# Runs the contract review rule cases with Node (22.6+, which runs TypeScript
# by stripping types). The engine sources under ets/contract are pure logic, so
# they are copied as .ts files and run unchanged.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SRC="$ROOT/harmony-app/entry/src/main/ets/contract"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for f in "$SRC"/*.ets; do
  name=$(basename "$f" .ets)
  sed -E "s#from '\./([A-Za-z]+)'#from './\1.ts'#" "$f" > "$WORK/$name.ts"
done
cp "$SCRIPT_DIR/cases.ts" "$WORK/cases.ts"

NODE=${NODE:-node}
if ! command -v "$NODE" >/dev/null 2>&1; then
  NODE=/Applications/DevEco-Studio.app/Contents/tools/node/bin/node
fi
LAW_INDEX="$ROOT/harmony-app/entry/src/main/resources/rawfile/law_index.json" "$NODE" "$WORK/cases.ts" "$@"
