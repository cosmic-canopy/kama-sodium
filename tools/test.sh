#!/bin/sh
# test.sh — build and run the package's tests, debug then release, and the example. `kama` is taken
# from $KAMA or the PATH.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KAMA=${KAMA:-kama}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

"$KAMA" pkg install "$ROOT/tests/kama.json" >/dev/null
for mode in --debug --release; do
    "$KAMA" build "$ROOT/tests/kama.json" $mode -o "$tmp/tests$mode"
    "$tmp/tests$mode"
done
# The example is a test too: the channel shape the package exists for, exit 0 end to end.
"$KAMA" pkg install "$ROOT/examples/udp_channel/kama.json" >/dev/null
"$KAMA" build "$ROOT/examples/udp_channel/kama.json" --release -o "$tmp/udp_channel"
"$tmp/udp_channel"
echo "test.sh: OK"
