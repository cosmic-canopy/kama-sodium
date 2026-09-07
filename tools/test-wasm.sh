#!/bin/sh
# test-wasm.sh — the same tests and the same example, built for wasm and run under node.
#
# This is the leg that proves the vendoring was worth it: there is no system libsodium for wasm, so a
# package that shelled out to `-lsodium` could not run here at all. The source is identical to the
# native run — same define list, same csources — and the entropy underneath comes from the web crypto
# API rather than getrandom.
#
# wasm needs emcc and node, which is why this runs in a container while tools/test.sh runs on the host.
#   CONTAINER  the image with emcc + node          (default: localhost/kama-dev:latest)
#   HOSTDIR    the directory bind-mounted at /host (default: the parent of this repository)
#   KAMA       the LINUX kama binary, as a path INSIDE the container
#              (default: /host/cstar/out/Linux-aarch64/kama — a peer checkout's dev build)
#
# The default KAMA is a development build of the compiler sitting next to this repo. Once kama has a
# public release, the honest default becomes installing it in the container instead; see
# .github/workflows/ci.yml for that shape.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HOSTDIR=${HOSTDIR:-$(dirname -- "$ROOT")}
REPO=$(basename -- "$ROOT")
CONTAINER=${CONTAINER:-localhost/kama-dev:latest}
KAMA=${KAMA:-/host/cstar/out/Linux-aarch64/kama}

command -v podman >/dev/null 2>&1 || { echo "test-wasm.sh: podman not found" >&2; exit 1; }

podman run --rm -v "$HOSTDIR:/host" -w "/host/$REPO" "$CONTAINER" sh -c '
set -eu
K=$1
[ -x "$K" ] || { echo "test-wasm.sh: no kama at $K inside the container" >&2; exit 1; }
tmp=$(mktemp -d); trap "rm -rf \"$tmp\"" EXIT

"$K" pkg install tests/kama.json >/dev/null
"$K" build tests/kama.json --target WASM -o "$tmp/tests.js"
node "$tmp/tests.js"

# The example is a test here too, exactly as it is in tools/test.sh.
"$K" pkg install examples/udp_channel/kama.json >/dev/null
"$K" build examples/udp_channel/kama.json --target WASM -o "$tmp/udp_channel.js"
node "$tmp/udp_channel.js"
' sh "$KAMA"

echo "test-wasm.sh: OK"
