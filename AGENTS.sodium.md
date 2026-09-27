# @kama/sodium — what is true in THIS repo

The two generated files carry the general rules: `AGENTS.md` is the language, `AGENTS.package.md` is
the half a publishable library needs. Both are written by `kama agents install` and are **not**
hand-edited — a re-install rewrites them. This file is the project-specific third, and it is the one
to edit.

**Read [docs/ROADMAP.md](docs/ROADMAP.md) first.** It is the order of work and what this repo is still
waiting on from the compiler, and [KAMA_GAPS.md](KAMA_GAPS.md) for the compiler gaps it has hit.
The package needs **kama ≥ 0.9.457**, declared as `"kama"` in the manifest — not for its source, which
still builds on 0.9.227, but for the manifest itself: `publish.exclude` (new in kama 0.9.453, first
released in 0.9.457) is a key an older compiler refuses outright. `tests/` and the example declare the
same, since they path-depend on the root manifest.

What is true here and nowhere else, learned building it (the first external kama package):

- **Publishing ships what git tracks, as committed, minus `publish.exclude`** in `kama.json` (the agent
  files, CI, `tools/`, `docs/`). Commit first — publish refuses a dirty tree — and read
  `kama publish kama.json --dry-run` before a real one: a version is permanent. The official registry
  is `registry.kama-lang.org`, published through `../kama-registry` (`./ops publish
  ../kama-sodium/kama.json`, which checks the package first); a consumer needs no registry config.
- **Run `tools/test.sh`** (`KAMA=/path/to/kama` if `kama` is not on the PATH). It builds `tests/`
  debug and release and then the example; a failing case prints its name. Test vectors come from
  `third_party/libsodium/../test/default` in the upstream tarball — never type one from memory; the
  first attempt at the aead vector was wrong.
- **`tools/test-wasm.sh` is the other half of the gate** — the same two programs on `--target WASM`
  under node, in a container with emcc. A change to `src/` or `csrc/` is not proven until both pass.
- **`tools/vendor-libsodium.sh` owns `third_party/libsodium/` and the `csources` block of kama.json.**
  Do not hand-edit either; change `VERSION`/`SHA256` in the script and run it.
- **Every size is spelled twice on purpose:** a `comptime isize` in the module and a `_Static_assert`
  in `csrc/kama_sodium.c`. Add both when binding a new primitive.
- **Keys go by `const ref`, pairs go whole.** Every byte-holder has a private `unsafe const fn
  UnsafeConstPtr<uint8> raw()`, `friend`-granted to the operations that read it; the eight whose bytes
  are filled from OUTSIDE the type (a `KeyPair` ctor cannot reach `this.pk.bytes` — a field is private
  to its own type) also have a granted non-const `rawMut()`. A `resource`'s fields are always private,
  so operations take `const ref KeyPair` and `publicKey()` answers a `PublicKey` by value.
- **A non-const `ref` parameter refuses a temporary** — "its mutation would be lost; bind it to a local
  first". A `const ref` takes one fine. That is a deliberate rule, not a gap: the fix is `const ref`,
  never a local bound only to get past it.
- **The extern side of the C seam is spelled from the C header, not guessed.** An input libsodium
  declares `const unsigned char *` is an `UnsafeConstPtr<uint8>`; an output stays `UnsafePtr<uint8>`.
  Getting this wrong in the read-only direction is SILENT — kama emits no prototype for an extern, and
  `uint8_t *` into a `const uint8_t *` parameter is legal C — so a green build proves nothing here.
  Read `csrc/kama_sodium.h` or `third_party/libsodium/.../sodium/*.h` for every one. The extern-agreement
  rule does catch a symbol declared two ways across files (`crypto_scalarmult_base` is in two).
- **Visibility is type-scoped, and `friend` is how you widen it — not `public`.** A grant is
  `friend <accessor>[members];` where the accessor is a type, a free function, or a `Type::method`
  (a constructor included), and it names individual members. So a helper that fills another type's
  private bytes gets a grant; it does not make the member public. An accessor in another module is
  named by its qualified path with no import (`friend sodium::aead::Key::fromSession[copyInto];`), and a
  grant into a module the program being built does not contain is inert — so `Nonce` grants to `box`
  even in the example, which never compiles `box`. Both were gaps until 0.9.227 (KAMA_GAPS.md #1, #2).
- **A read-only window is `ConstView<uint8>`, a writable one is `View<uint8>`.** `view()` and
  `slice()` mint the read-only pair, `viewMut()`/`sliceMut()` the writable one, and a `View` narrows to
  a `ConstView` implicitly at every sink. `addr(of: cv[0])` gives an `UnsafeConstPtr<uint8>`, so a
  caller's window types straight through to libsodium's `const` input. Declare a parameter by what the
  callee DOES, and the compiler names `viewMut()` at any site that actually writes.
- **A non-exported name is private to its FILE**, not to its module (kama ≥ 0.9.207), so the four
  `*_test.kama` files each keep their own private `knownAnswer`.
- **Unwrapping a `Result`:** a value payload is copied out of a borrowing `match (r)`; a resource
  payload leaves a consuming `match (give r)` by `give x`. A `Result` over a dtor-less resource needed
  a compiler fix (kama 0.9.200) to be move-tracked at all.
- **Reserved words that bit:** `out`, `short` (every C keyword is reserved). `println(s:)` is named and,
  since kama 0.9.427, imported (`import { core::println };`) like any other function; an interpolation
  hole takes an identifier with accessors, not a call.
- **One `import { … };` per file**, and a module is imported by symbol (`std::encoding::hex::decode
  as hexDecode`), never as a namespace.
