#!/bin/sh
# Runs the tests for the app's pure logic (prompts, history, cases) with Node
# 22.7+ (models use enums, so types are transformed rather than stripped). The ets tree is copied as
# .ts files with relative imports pointing at them; only files without @kit
# imports are loaded by the tests.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SRC="$ROOT/harmony-app/entry/src/main/ets"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for dir in models services contract; do
  mkdir -p "$WORK/$dir"
  for f in "$SRC/$dir"/*.ets; do
    sed -E "s#from '(\.\.?/[A-Za-z/]+)'#from '\1.ts'#" "$f" > "$WORK/$dir/$(basename "$f" .ets).ts"
  done
done
mkdir -p "$WORK/tests"
cp "$SCRIPT_DIR/cases.ts" "$WORK/tests/cases.ts"

# Some Node builds reject --experimental-transform-types; fall back to the
# Node bundled with DevEco Studio.
NODE=${NODE:-node}
if ! "$NODE" --experimental-transform-types --no-warnings -e '' >/dev/null 2>&1; then
  for candidate in /Applications/DevEco-26/DevEco-Studio-26.app/Contents/tools/node/bin/node \
    /Applications/DevEco-Studio.app/Contents/tools/node/bin/node; do
    if [ -x "$candidate" ]; then
      NODE=$candidate
      break
    fi
  done
fi
"$NODE" --experimental-transform-types --no-warnings "$WORK/tests/cases.ts"
