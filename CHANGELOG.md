# Changelog

All notable changes to `@kama/sodium`. The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-09-06

The const-pointer release. kama 0.9.204 and 0.9.205 gave the language a read-only raw pointer
(`UnsafeConstPtr<T>`) and split `dataPtr()` from `dataPtrMut()`. This package was written before both and
had shaped its whole API around their absence, so this release is that API arriving rather than a port.

### Changed — BREAKING

- **Every parameter that only reads a key, nonce, public key or key pair is now `const ref`**, where it
  was `ref`: `seal`, `open`, `sealInto`, `openInto`, `sealAnonymous`, `openAnonymous`, `sign`, `verify`,
  `clientSessionKeys`, `serverSessionKeys` and `Key.fromSession`. Callers passing a mutable local need no
  change; callers holding a `const` no longer have to drop it.
- **`raw()` on every key, nonce and signature type is a `const fn` answering `UnsafeConstPtr<uint8>`**,
  where it answered `UnsafePtr<uint8>`. Code that wrote through it wants the new non-const `rawMut()`,
  which exists on the eight types whose bytes are filled from outside the type. `kx::SessionKey` is
  write-only: it has `rawMut()` and no `raw()`.
- **`KeyPair.publicKey()` answers a `PublicKey` by value**, not `ref PublicKey`. Callers that bound the
  result to a local can now inline it.
- **`exportTo`, `exportSecretKeyTo`, `SessionKeys.copyInto` and `SessionKey.copyRawInto` are `const fn`s.**
- **Minimum compiler is kama 0.9.208**, declared as `"kama": ">=0.9.208"` in the manifest. An older
  compiler is refused by name at `kama pkg install` and `kama build`.

### Fixed

- Every `extern fn` now spells the read-only half of the libsodium seam as libsodium's own prototypes do.
  41 declarations, read from `csrc/kama_sodium.h` and the vendored `sodium/*.h` rather than inferred.
- `csrc/kama_sodium.c` no longer casts away `const` from `sodium_version_string()`;
  `kama_sodium_version()` returns `const uint8_t *`.
- A comment in `kx` named `aead::Key.fromSessionKey`, a constructor that does not exist. It is
  `fromSession`.

### Removed

- The `"native"` entry in the manifest's `modules` map, which named a directory that never existed.

## [0.1.0] — 2026-09-05

First release, and the first external kama package.

- Six modules: `secretbox` (XSalsa20-Poly1305), `aead` (XChaCha20-Poly1305-IETF), `box` (X25519 +
  XSalsa20-Poly1305, with sealed boxes), `sign` (Ed25519), `kx` (X25519 into directional session keys),
  `random` (libsodium's CSPRNG), plus `Nonce`, `SodiumError`, `memzero`, `equalsConstantTime` and
  `version` at the root.
- libsodium 1.0.20-stable vendored under `third_party/`, pinned by sha256 and compiled through kama's
  `csources`/`cincludes`, so a consumer needs nothing installed on any target.
- Every primitive proven against a known-answer vector from libsodium's own `test/default`.
- Native, wasm-under-node, and a `file://` publish→install round trip all proven.
