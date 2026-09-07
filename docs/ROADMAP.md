# @kama/sodium — roadmap

**The order of work for this repo, and what it is waiting on from the compiler.** Read this first, then
`AGENTS.md` § *This package*. The compiler lives at `../cstar`; a development build is
`../cstar/out/<os>-<arch>/kama` (`../cstar/out/Darwin-arm64/kama` on this machine), and `tools/test.sh`
takes it as `KAMA=<path>`. Check `kama --version` before assuming any row below — every row names the
compiler version it needs.

## Where this is (2026-09-06)

`0.2.0`, built and tested on kama **0.9.209**, with a declared floor of `>=0.9.208`. Six modules,
libsodium 1.0.20 vendored, every primitive proven against libsodium's own vectors.

kama `0.9.204`…`0.9.208` shipped four things this package asked for while it was being written, and
**rows 1–5 below consumed all four**:

| kama | what | what it meant here |
|---|---|---|
| 0.9.204 | **`UnsafeConstPtr<T>`** — the read-only raw pointer, C's `const T*` | the type libsodium's `const unsigned char*` inputs always wanted |
| 0.9.205 | **`dataPtr()` is `const fn` returning `UnsafeConstPtr<T>`; `dataPtrMut()` is the writable half** | a `const ref Key` can hand its bytes to C |
| 0.9.206 | the **`"kama"` manifest key** — the compiler range a package needs | this package declares `>=0.9.208` |
| 0.9.207 | **file-private names are keyed per file** | the four `knownAnswer` helpers in `tests/src/` |
| 0.9.208 | the `-Wl,-dead_strip` warning per translation unit is gone from `--release` | confirmed: a consumer's release build is quiet |

## DONE — the 0.2.0 arc

1. **The const-pointer split.** 41 externs re-spelled from the C prototypes; every write through
   `dataPtr()` moved to `dataPtrMut()`; each byte-holder's `raw()` is a `const fn` answering
   `UnsafeConstPtr<uint8>`, and eight of the eleven gained a non-const `rawMut()`.
2. **`const ref` on every parameter that only reads a key, nonce, public key or pair**, plus `const fn`
   on every `exportTo`, `copyInto` and `copyRawInto`. `publicKey()` answers a `PublicKey` by value.
3. **`"kama": ">=0.9.208"` and `"version": "0.2.0"`** in the manifest; the dead `"native"` module entry
   dropped.
4. **The per-file test prefixes dropped** — four private `knownAnswer` helpers, one per file.
5. The gate: `tools/test.sh` debug + release + `examples/udp_channel`, and the wasm leg.

### What the arc corrected in its own plan

- Row 1 originally claimed **no `rawMut()` would be needed**. It was needed for 8 of the 11 accessors: a
  `KeyPair` constructor has to hand libsodium a buffer to FILL, and a field is private to its own type,
  so `KeyPair` cannot reach `this.pk.bytes` and must go through an accessor. `kx::SessionKey` is the
  mirror case — write-only, so it has `rawMut()` and no `raw()` at all.
- `crypto_scalarmult_base` is declared in **two** files (`box`, `kx`) and both had to change together.
  The extern-agreement rule catches this one; nothing catches an under-const extern (see below).

## WAITING ON kama — do not work around these, check `kama --version`

| this package's shape | what it is waiting for | where |
|---|---|---|
| every `View<uint8>` parameter is a MUTABLE view taken by value (`seal(View<uint8> message, …)`), only so `addr(of: message[0])` is legal; a `const ref DynamicArray<uint8>` caller cannot even produce one | **`ConstView<T>` + `view()`/`viewMut()`** — the read-only view; those parameters become `ConstView<uint8>` | `../cstar/docs/ROADMAP.md` NOW row 2, *A read-only `View`* (sized L) |
| `zeroed()` constructors and every `rawMut()` are `public` because a non-public member is private to its TYPE, and the code that fills a zeroed key lives outside it | **member visibility per file** — an open design question | `../cstar/docs/ROADMAP_DETAIL.md` §3 *Member visibility: per type, or per file?* |
| `kama pkg add … --path ../kama-sodium` is how a consumer gets it; `kama publish --registry file:///…` is as far as publishing goes | the **hosted registry** for the `@kama` scope | `../cstar/docs/ROADMAP.md` LATER row 21, *Registry — hosted deployment* |

### Closed by this arc, and why they are NOT compiler rows

- ~~`pair.publicKey()` must be copied to a local before it is passed by `ref`.~~ **Not a gap.** Probed on
  0.9.208: a *non-const* `ref` parameter refuses a temporary — *"its mutation would be lost; bind it to a
  local first"* — which is correct, since the mutation would go nowhere. A **`const ref` takes a temporary
  fine.** Row 2's `const ref` parameters plus a by-value `publicKey()` removed every place it bit. Nothing
  to raise in `../cstar`.
- ~~Keys must go by `ref` because there is no const raw pointer.~~ Shipped in 0.9.204/0.9.205.
- ~~Two files of one module cannot both declare a private helper.~~ Shipped in 0.9.207.

### An asymmetry worth knowing, not a row

Spelling a read-only extern input `UnsafePtr<uint8>` is caught by **neither** compiler: kama emits no
prototype for an extern, and passing `uint8_t *` where C wants `const uint8_t *` is a silent, legal
widening. The reverse (const where C wants writable) *is* a hard C error. So the C header is the only
authority for the read-only direction, and a green build proves nothing about it. This is a documentation
fact for package authors — recorded in `AGENTS.md` — rather than something the compiler could fix without
emitting prototypes it deliberately does not emit.

## Before this can really be published

Publishing works today only against a `file://` registry, which is what the round trip in `tools/` proves.
A real release needs, from `../cstar`:

- **LATER row 21 — hosted registry deployment (M3.3), mandatory verification, and the trust model.** The
  `@kama` scope needs a hosted index; `kama publish --key` signing and `kama pkg install --verify` need to
  be the default rather than opt-in.
- **A resolution-time compiler check.** The registry index does not carry a package's `"kama"` requirement
  yet, so resolution picks the highest satisfying *package* version and the compiler range is only checked
  at install. A consumer on an older compiler gets a refusal rather than an older-but-working version.
- **LATER row 22 — scope registration**, once the repo is public.

## LATER — this package

- More of libsodium behind the same rules (`generichash`/BLAKE2b, `pwhash`/Argon2id, `shorthash`,
  `stream`, `secretstream`, `kdf`, `auth`, and `box`'s precomputed `beforenm`); each is a module, a
  `comptime isize` per size, a `_Static_assert` in `csrc/kama_sodium.c`, and a vector from the tarball's
  `test/default` — never one typed from memory.
- `tools/vendor-libsodium.sh` to the next libsodium stable when it exists (bump `VERSION`/`SHA256`,
  run it; it owns `third_party/` and the `csources` block).
- `.github/workflows/ci.yml` has never run — there is no git remote on this repo and no public kama to
  install. It is written as the template the next kama package copies; wire it up when both exist.
