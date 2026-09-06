# @kama/sodium — roadmap

**The order of work for this repo, and what it is waiting on from the compiler.** Read this first, then
`AGENTS.md` § *This package*. The compiler lives at `../cstar`; a development build is
`../cstar/out/<os>-<arch>/kama` (`../cstar/out/Darwin-arm64/kama` on this machine), and `tools/test.sh`
takes it as `KAMA=<path>`. Check `kama --version` before assuming any row below — every row names the
compiler version it needs.

## Context (2026-09-06)

kama `0.9.204`…`0.9.208` shipped four things this package asked for while it was being written:

| kama | what | what it means here |
|---|---|---|
| 0.9.204 | **`UnsafeConstPtr<T>`** — the read-only raw pointer, C's `const T*`. Storing through it, and converting it to `UnsafePtr<T>`, are compile errors; `UnsafePtr<T>` → `UnsafeConstPtr<T>` is implicit, as in C | the type libsodium's `const unsigned char*` inputs always wanted |
| 0.9.205 | **`dataPtr()` is `const fn` and returns `UnsafeConstPtr<T>`; `dataPtrMut()` is the writable half** (FixedArray, DynamicArray, InlineArray); `cstr()` is read-only | `this.bytes.dataPtr()` as a WRITE target no longer compiles; a `const ref Key` can now hand its bytes to C |
| 0.9.206 | the **`"kama"` manifest key** — the compiler range a package needs, checked at install and at build | this package uses `cincludes` and `UnsafeConstPtr`; it must say so |
| 0.9.207 | **file-private names are keyed per file** — two files of one module may each keep a private `helper` | the per-file `knownAnswer` prefixes in `tests/src/` are no longer needed |
| 0.9.208 | the `-Wl,-dead_strip` warning per translation unit is gone from `--release` builds | the 121 warning lines a consumer saw first are gone; nothing to do but confirm |

The package **does not build on 0.9.208 yet** — 26 errors, every one expected, listed under row 1. It is
`0.1.0` on kama `0.9.203`: six modules, libsodium 1.0.20 vendored, every primitive proven against
libsodium's own vectors, native + wasm + publish→install round trip proven. Rows 1–5 make it `0.2.0`.

## NOW — in order

### 1. Build on kama ≥ 0.9.208 — the const-pointer split (needs 0.9.205+)

Every error is one of five shapes. Measured with `kama build tests/kama.json` on 0.9.208:

**(a) An extern's read-only input spelled writable.** libsodium takes `const unsigned char*` for
`m`, `ad`, `npub`, `k`, `pk`, `sk`, `n`, `b1`/`b2`, `s`… — spell those `UnsafeConstPtr<uint8>` in every
`extern fn` in `src/` (41 declarations). Outputs (`c`, `m` on decrypt, `k` on keygen, `buf` on
`randombytes_buf`, `pnt` on `sodium_memzero`, `n` on `sodium_increment`) stay `UnsafePtr<uint8>`.
Read each libsodium prototype from `third_party/libsodium/src/libsodium/include/sodium/*.h` — the C side
is the authority, and the compiler's C backstop (`-Werror=incompatible-pointer-types`) refuses a
mismatch the kama side missed. The extern-agreement rule holds every file's re-declaration to one spelling.

**(b) A write target reached through `dataPtr()`** — becomes `this.bytes.dataPtrMut()`:
`src/aead/aead.kama:39` (`keygen k:`), `:56` (`copyInto dst:`); `src/secretbox/secretbox.kama:38`, `:54`;
`src/sodium.kama:75` (`randombytes_buf buf:`), `:90` (`sodium_increment n:`); `src/kx/kx.kama:147`
(`src:` — check: a *source* is read-only, so this one is shape (a) on the extern, not `dataPtrMut()`).

**(c) `sodium_memzero(pnt: this.bytes.dataPtr(), …)` in every destructor** — `dataPtrMut()`:
`aead.kama:67`, `box.kama:87`, `kx.kama:84`, `:150`, `secretbox.kama:71`, `sign.kama:79`.

**(d) The `raw()` accessors — `public unsafe fn UnsafePtr<uint8> raw() { return this.bytes.dataPtr(); }`**
at `aead.kama:65`, `box.kama:58`, `:85`, `kx.kama:55`, `:82`, `:142`, `secretbox.kama:69`, `sign.kama:49`,
`:77`, `:149`, `sodium.kama:101`. This is the row's whole point, so do not just make them `dataPtrMut()`:
they become **`public unsafe const fn UnsafeConstPtr<uint8> raw()`** — a `const ref Key` can then reach C.
Where libsodium genuinely writes into the buffer the accessor is not the path anyway (keygen, randombytes,
memzero, increment all live inside the type and use `dataPtrMut()` directly), so no `rawMut()` should be
needed; if one is, name it that and keep it non-const.

**(e) Two extern-agreement lines** — `src/sodium.kama:35` re-declares `kama_string_from_raw` as
`UnsafePtr<uint8> src`; the prelude and `std::encoding::hex` now say `UnsafeConstPtr<uint8> src`. Match it.

Then `KAMA=../cstar/out/Darwin-arm64/kama tools/test.sh` — debug and release, and the release build
must print **no** `'linker' input unused` lines now (row 3 of the compiler's list; if it does, that is a
compiler bug to report there).

### 2. `const ref` on every parameter that only reads a key or a nonce (needs 0.9.205+)

The signature the package wanted from the start: `seal(message, ad, const ref Nonce nonce, const ref
Key key)`, `open(… const ref …)`, `sign`/`verify`, `kx` — every operation that reads a key, nonce, public
key or key pair takes `const ref`, so callers holding one `const` stop dropping it. `raw()` being
`const fn` (row 1d) is what makes this compile. What stays `ref`: anything that mutates
(`Nonce.increment()`, `SessionKeys.copyInto` on its source if it consumes). Then rewrite the two
paragraphs in `README.md` § *The rules every module holds* and `AGENTS.md` § *This package* ("Keys go by
`ref`") that documented the workaround — they are now false.

Still true, and still a workaround: **a `ref`-returning call cannot feed a `ref` parameter** (a
temporary), so `pair.publicKey()` is copied to a local first. That one is not rowed in the compiler's
roadmap — if it still bites after this row, raise it there (`../cstar/docs/ROADMAP.md`, the audit row's
seed list is where it belongs).

### 3. Declare the floor, and version honestly (needs 0.9.206+)

- `kama.json`: `"kama": ">=0.9.208"` — the range of compilers this source needs (`cincludes`,
  `UnsafeConstPtr`, per-file private names). `kama pkg install` and `kama build` both check it; an older
  compiler reports `unknown key \`kama\`` — a refusal without the reason, which is still a refusal.
- `"version": "0.2.0"` — row 2 changes public signatures (`ref` → `const ref`); that is an API change for
  consumers, not a patch.

### 4. Drop the per-file test prefixes (needs 0.9.207+, optional)

`tests/src/*_test.kama` prefix their private helpers per file because two files of one module could not
both declare a private `knownAnswer`. They can now. Plain names, one per file; remove the `AGENTS.md`
bullet that explained the prefix.

### 5. The gate, then publish

- `tools/test.sh` debug + release + `examples/udp_channel` (it builds the example too).
- The wasm leg in the container, as `README.md` § *Tests* describes (podman, `-v /Users/matt/Documents:/host`,
  the Linux kama at `../cstar/out/Linux-aarch64/kama`) — `csources` compile as `gnu11` there since 0.9.201.
- The publish→install round trip through `file:///tmp/kreg` (`kama publish kama.json --registry
  file:///tmp/kreg`, then a consumer with `"@kama/sodium": { "version": "^0.2.0", "registry": … }`).
- Tag `v0.2.0`.

## WAITING ON kama — do not work around these, check `kama --version`

| this package's shape | what it is waiting for | where |
|---|---|---|
| every `View<uint8>` parameter is a MUTABLE view taken by value (`seal(View<uint8> message, …)`), only so `addr(of: message[0])` is legal; a `const ref DynamicArray<uint8>` caller cannot even produce one | **`ConstView<T>` + `view()`/`viewMut()`** — the read-only view; those parameters become `ConstView<uint8>` | `../cstar/docs/ROADMAP.md` row *A read-only `View`* (row 2 as of 2026-09-06) |
| `zeroed()` constructors are `public` because a non-public member is private to its TYPE, and the free functions that fill a zeroed key live outside it | **member visibility per file** — an open design question | `../cstar/docs/ROADMAP_DETAIL.md` §3 *Member visibility: per type, or per file?* |
| `pair.publicKey()` copied to a local before it is passed by `ref` | a `ref`-returning temporary feeding a `ref` parameter — **not rowed**; raise it | `../cstar/docs/ROADMAP.md` row *Audit every "waiting on a consumer" deferral* |
| `kama pkg add … --path ../kama-sodium` is how a consumer gets it | the **hosted registry** for the `@kama` scope | `../cstar/docs/ROADMAP.md` LATER, *Registry — hosted deployment* |

## LATER — this package

- More of libsodium behind the same rules (`generichash`/BLAKE2b, `pwhash`/Argon2id, `shorthash`,
  `stream`); each is a module, a `comptime isize` per size, a `_Static_assert` in `csrc/kama_sodium.c`,
  and a vector from the tarball's `test/default` — never one typed from memory.
- `tools/vendor-libsodium.sh` to the next libsodium stable when it exists (bump `VERSION`/`SHA256`,
  run it; it owns `third_party/` and the `csources` block).
