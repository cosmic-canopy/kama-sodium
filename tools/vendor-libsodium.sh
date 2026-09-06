#!/bin/sh
# vendor-libsodium.sh — pin one libsodium release into third_party/libsodium/ and regenerate the
# `csources` list in kama.json from what landed.
#
# Vendored on purpose. A consumer of @kama/sodium gets a working build with nothing to install, on
# every target kama has (a system `-lsodium` cannot exist for wasm, and a dependency cannot add
# `-I/opt/homebrew/include` for a consumer), and a shipped binary links one known libsodium rather than
# whichever one a machine had. Upgrading is running this script with a new VERSION and SHA256, reading
# the diff, and bumping this package's version.
#
# What lands:
#   third_party/libsodium/src/libsodium/      the C sources and private headers, pristine
#   third_party/libsodium/src/libsodium/include/sodium/version.h   the release's prebuilt one (upstream
#                                             generates it from version.h.in at configure time; the
#                                             MSVC build ships the answer, and it is what build.zig uses)
#   third_party/libsodium/LICENSE             ISC — kept beside the code it covers
# What does NOT: the configure machinery, tests, dist-build scripts, and the seven x86 `.S` files'
# assembly paths are simply never selected (kama's `csources` compiles `.c`; libsodium's C fallbacks for
# those paths are what compile, and they runtime-dispatch to the SIMD C paths on their own).
#
# The `csources` block in kama.json is GENERATED here — 119 entries at 1.0.20 — between two marker
# comments, so an upgrade that adds or removes a file cannot drift from the tree. Everything else in the
# manifest is hand-written and untouched.
set -eu

VERSION=1.0.20
SHA256=b6b1d2a8802cd8bfa611638c0e9ce31d14ef324e16062c39a76854091cba6d7f
URL="https://download.libsodium.org/libsodium/releases/libsodium-${VERSION}-stable.tar.gz"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEST="$ROOT/third_party/libsodium"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# A local tarball (already verified by the same hash) skips the download — the way CI mirrors it.
tarball="${LIBSODIUM_TARBALL:-}"
if [ -z "$tarball" ]; then
    tarball="$tmp/libsodium.tar.gz"
    echo "vendor-libsodium: fetching $URL"
    curl -sSL -o "$tarball" "$URL"
fi
got=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
if [ "$got" != "$SHA256" ]; then
    echo "vendor-libsodium: sha256 mismatch for libsodium-$VERSION: got $got, want $SHA256" >&2
    exit 1
fi

tar -xzf "$tarball" -C "$tmp"
src="$tmp/libsodium-stable"
[ -d "$src/src/libsodium" ] || { echo "vendor-libsodium: unexpected tarball layout" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST/src"
cp -R "$src/src/libsodium" "$DEST/src/libsodium"
cp "$src/LICENSE" "$DEST/LICENSE"
cp "$src/builds/msvc/version.h" "$DEST/src/libsodium/include/sodium/version.h"
# The template it was generated from would otherwise sit beside the answer, inviting a regeneration.
rm -f "$DEST/src/libsodium/include/sodium/version.h.in"
# Autotools inputs are build machinery this package does not run; the `.S` files stay because they are
# source, and the tree diffs cleanly against upstream on an upgrade.
rm -f "$DEST/src/libsodium/Makefile.am" "$DEST/src/libsodium/Makefile.in"
printf 'libsodium %s\n%s\nsha256 %s\n' "$VERSION" "$URL" "$SHA256" > "$DEST/VENDORED"

# Regenerate the csources block: every .c under the vendored tree, sorted, as manifest-relative paths.
list=$(cd "$ROOT" && find third_party/libsodium/src/libsodium -name '*.c' | LC_ALL=C sort)
count=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
{
    echo '    "csrc/kama_sodium.c",'
    printf '%s\n' "$list" | awk -v n="$count" '{ printf "    \"%s\"%s\n", $0, (NR < n ? "," : "") }'
} > "$tmp/block"

manifest="$ROOT/kama.json"
awk -v block="$tmp/block" '
    /"csources": \[/ { print; while ((getline line < block) > 0) print line; skipping = 1; next }
    skipping && /^  \]/ { skipping = 0 }
    !skipping { print }
' "$manifest" > "$tmp/kama.json"
mv "$tmp/kama.json" "$manifest"

echo "vendor-libsodium: libsodium $VERSION in third_party/libsodium ($count C files); kama.json csources regenerated"
