# @kama/sodium — roadmap

**The order of work for this repo, and what it is waiting on from the compiler.** Read this first, then
`AGENTS.md` § *This package*. The compiler lives at `../cstar`; a development build is
`../cstar/out/<os>-<arch>/kama` (`../cstar/out/Darwin-arm64/kama` on this machine), and `tools/test.sh`
takes it as `KAMA=<path>`. Check `kama --version` before assuming any row below — every row names the
compiler version it needs.

## Where this is (2026-10-02)

`0.5.1` is **on the official registry** (`registry.kama-lang.org` — a consumer writes
`"@kama/sodium": { "version": "^0.5.0" }` and nothing else): the MIT OR Apache-2.0 license and a README
sample that compiles, over the same library as `0.5.0`. Built and tested on kama **0.9.519** (dev;
native and wasm) and **0.9.486**, the latest release (native), and published with `0.9.486`. The
declared floor is `>=0.9.457` — raised for the manifest's `publish.exclude`, which an older compiler
refuses, not for the source, which has not changed since 0.4.0 and still builds on 0.9.227 (row 13).
Six modules, libsodium 1.0.20 vendored, every primitive proven against libsodium's own vectors.

**Nothing is blocked, and no gap is open.** Every gap this package filed has been fixed upstream — the
`friend` pair in 0.9.227, the `addr(of:)` diagnostic in 0.9.229, and the stale agent guidance
([KAMA_GAPS.md](../KAMA_GAPS.md) #4) in 0.9.237 — so there is no public pointer into key material
left anywhere in the API, and no correction to the generated guidance left in this repo.

kama `0.9.204`…`0.9.208` shipped four things this package asked for while it was being written, and
**rows 1–5 below consumed all four**:

| kama | what | what it meant here |
|---|---|---|
| 0.9.204 | **`UnsafeConstPtr<T>`** — the read-only raw pointer, C's `const T*` | the type libsodium's `const unsigned char*` inputs always wanted |
| 0.9.205 | **`dataPtr()` is `const fn` returning `UnsafeConstPtr<T>`; `dataPtrMut()` is the writable half** | a `const ref Key` can hand its bytes to C |
| 0.9.206 | the **`"kama"` manifest key** — the compiler range a package needs | this package declares `>=0.9.227` |
| 0.9.207 | **file-private names are keyed per file** | the four `knownAnswer` helpers in `tests/src/` |
| 0.9.208 | the `-Wl,-dead_strip` warning per translation unit is gone from `--release` | confirmed: a consumer's release build is quiet |

## DONE — 0.5.0: onto the launched compiler and the official registry (the library source is unchanged)

10. **`println` is imported from `core`** in `tests/` and `examples/udp_channel` — a bare `println` is
    an error since kama 0.9.427 (KR-87).
11. **`AGENTS.md`, `AGENTS.package.md` and the kama skill regenerated on 0.9.457.** The three stale
    bullets are gone upstream (KAMA_GAPS.md #4, fixed in 0.9.237), so the warning `AGENTS.sodium.md`
    carried against them is deleted, along with two of its own bullets that had gone stale in 0.3.0/0.4.0.
    The skill had not been regenerated since 0.1.0 and taught `kama build src/app.kama`, a loose build.
12. **CI pins the public release**, `KAMA_VERSION: v0.9.457`, which the installer resolves.
13. **`publish.exclude` keeps the repository out of the package** — the agent files, CI, `tools/` and
    `docs/` — since kama 0.9.452 publishes exactly the files git tracks. The key is new in 0.9.453 and an
    older compiler refuses it (measured: 0.9.440 says `unknown key \`publish\``), so every manifest here
    declares `>=0.9.457`, the first release carrying it — the rule in `../cstar/docs/packages.md`
    § *What compiler a package needs*: a package that starts using a manifest key raises its floor to the
    release that introduced it.
14. **Published**: `@kama/sodium@0.5.0` through `../kama-registry` (`./ops publish`), the first package
    on the official registry.

## DONE — the 0.4.0 arc

8. **`Nonce.raw()` made private**, the last public pointer into key material — unblocked by the
   `friend` fix this repo asked for (0.9.227).
9. **Adopted `AGENTS.package.md`** (0.9.231), whose content this package's own guidance seeded; the
   repo's specifics moved to `AGENTS.sodium.md`.

## DONE — the 0.3.0 arc

6. **`ConstView<uint8>` at every parameter that only reads**, `viewMut()` at every writer.
7. **Every internal accessor made private and `friend`-granted** to the operations that need it, by
   name — 31 grants, two of which cross a module boundary.

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

Nothing. The last row — a consumer could only take this package by `--path`, because there was no
hosted registry — closed with 0.5.0 on `registry.kama-lang.org`.

### Closed, and why they are NOT compiler rows

- ~~`pair.publicKey()` must be copied to a local before it is passed by `ref`.~~ **Not a gap.** Probed on
  0.9.208: a *non-const* `ref` parameter refuses a temporary — *"its mutation would be lost; bind it to a
  local first"* — which is correct, since the mutation would go nowhere. A **`const ref` takes a temporary
  fine.** Row 2's `const ref` parameters plus a by-value `publicKey()` removed every place it bit. Nothing
  to raise in `../cstar`.
- ~~Keys must go by `ref` because there is no const raw pointer.~~ Shipped in 0.9.204/0.9.205.
- ~~Two files of one module cannot both declare a private helper.~~ Shipped in 0.9.207.
- ~~Every `View<uint8>` parameter must be mutable.~~ Shipped in 0.9.213/0.9.214.
- ~~`zeroed()` and `rawMut()` must be `public`, because member visibility is per type and the code that
  fills a zeroed key lives outside it.~~ **Wrong premise, and the correction came from the language's
  author.** Visibility being type-scoped is deliberate, and `friend` is the mechanism — more granular
  than C++'s, since it names individual members. Every one of those `public` markers is now a grant.
  The lesson for this repo: a workaround that gets written into the docs as "an open design question"
  stops anyone from looking for the feature that already exists. Check `SPEC.md` before recording a
  limitation.

### An asymmetry worth knowing, not a row

Spelling a read-only extern input `UnsafePtr<uint8>` is caught by **neither** compiler: kama emits no
prototype for an extern, and passing `uint8_t *` where C wants `const uint8_t *` is a silent, legal
widening. The reverse (const where C wants writable) *is* a hard C error. So the C header is the only
authority for the read-only direction, and a green build proves nothing about it. This is a documentation
fact for package authors — recorded in `AGENTS.md` — rather than something the compiler could fix without
emitting prototypes it deliberately does not emit.

## Publishing

`kama publish` ships the files git tracks, as committed, minus `publish.exclude`; commit first, and read
`kama publish kama.json --dry-run` before a real one — a version is permanent. The official registry is
published through `../kama-registry`: `./ops publish ../kama-sodium/kama.json` runs `kama check`, publishes
into its `registry/` tree, runs the registry's own checks (integrity, write-once, `@kama/*` only,
secret-shaped names) and commits; the push deploys it. What is still host-side, in `../cstar`:

- **The trust model, in two steps and already decided** (KR-27, following where Go, PyPI, npm and
  crates.io landed rather than per-developer PGP): first an **allowed-signers set** — real `ssh-keygen -Y
  verify` against a configured trust set, plus closing the warm-store and git-dependency gaps; then
  **CI/OIDC provenance in a transparency log**, at which point `--verify` stops being opt-in.
- **A resolution-time compiler check.** The registry index does not carry a package's `"kama"` requirement
  yet, so resolution picks the highest satisfying *package* version and the compiler range is only checked
  at install. A consumer on an older compiler gets a refusal rather than an older-but-working version.
- **LATER KR-28 — the registrations** (editor and registry listings). The public repo half is done:
  kama is released from `github.com/cosmic-canopy/kama`.

What this repo owed back is paid: the package half of the agent guidance shipped upstream as
`AGENTS.package.md` in 0.9.231, seeded from this package's notes (row 9). Anything learned here that
generalises still belongs upstream, in language a package that is not a libsodium binding can use.

## LATER — this package

- More of libsodium behind the same rules (`generichash`/BLAKE2b, `pwhash`/Argon2id, `shorthash`,
  `stream`, `secretstream`, `kdf`, `auth`, and `box`'s precomputed `beforenm`); each is a module, a
  `comptime isize` per size, a `_Static_assert` in `csrc/kama_sodium.c`, and a vector from the tarball's
  `test/default` — never one typed from memory.
- `tools/vendor-libsodium.sh` to the next libsodium stable when it exists (bump `VERSION`/`SHA256`,
  run it; it owns `third_party/` and the `csources` block).
- **See `.github/workflows/ci.yml` go green.** Both of its prerequisites exist now — this repo has a
  GitHub remote, and kama is a public release the installer resolves — and its pin names one
  (`v0.9.457`). Until 2026-09-26 it pinned `v0.9.208`, which was never released, so no run before then can
  have passed. It is the template the next kama package copies. A `windows-x64` release exists too; this
  package has not been built on Windows, so the matrix does not claim it.
- **`tools/test-wasm.sh` on the public release.** Its default `KAMA` is still the peer dev build
  (`/host/cstar/out/Linux-aarch64/kama`); its own header says the honest default, once kama is public,
  is installing a release in the container. That condition has been met.
