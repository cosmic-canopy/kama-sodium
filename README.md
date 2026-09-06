# @kama/sodium

[libsodium](https://libsodium.org) for [kama](https://kama-lang.org) — the first official kama package,
and the worked example of what one looks like. A binding, not a cryptography library: every primitive
is libsodium's, and what this package adds is the types that make misuse a compile error.

```sh
kama pkg add kama.json @kama/sodium --path ../kama-sodium     # today: a path dependency
```

```kama
import { sodium::Nonce, sodium::aead::Key, sodium::aead::seal, sodium::aead::open,
         std::collections::FixedArray };

unsafe fn void demo(View<uint8> packetHeader, View<uint8> payload) {
    Key key = Key.random();                         // move-only; zeroed when dropped
    Nonce nonce = Nonce.random();                   // 24 bytes: random per message is safe
    FixedArray<uint8> sealed = seal(message: payload, ad: packetHeader, nonce: nonce, key: key);
    match (open(ciphertext: sealed.view(), ad: packetHeader, nonce: nonce, key: key)) {
        case Ok(value: plain): { /* the payload, verified together with the header */ }
        case Err(error: e):    { /* Forged: altered, or another key or nonce */ }
    };
}
```

## Modules

| module | primitive | for |
|---|---|---|
| `sodium::secretbox` | XSalsa20-Poly1305 | one shared key, a blob |
| `sodium::aead` | XChaCha20-Poly1305-IETF | one shared key, a **protocol**: a header authenticated in the clear |
| `sodium::box` | X25519 + XSalsa20-Poly1305 | two key pairs; and **sealed boxes** for an anonymous sender |
| `sodium::sign` | Ed25519 | detached signatures |
| `sodium::kx` | X25519 | a key exchange into **directional** session keys (rx/tx) |
| `sodium::random` | the CSPRNG | tokens, salts, challenges |
| `sodium` (root) | — | `Nonce`, `SodiumError`, `memzero`, `equalsConstantTime`, `version` |

A client/server channel is `kx` for the session keys, then `aead` per packet with the header as
associated data — `examples/udp_channel/` is that shape end to end.

## The rules every module holds

- **Secret material is a `type resource`** over an inline byte array, zeroed by `sodium_memzero` in its
  destructor. It moves, is never copied by accident, and is gone when dropped. Public keys, nonces and
  signatures are `type value` and copy freely.
- **Sizes are types.** A `secretbox::Key` is 32 bytes by construction. Bytes off the wire enter through
  `fromBytes(bytes:)`, which answers `Result` — `BadLength(expected, got)` when they are not the size.
- **A data error is a `Result`; a contract violation panics.** `open` of a forged box is `Err(Forged)`
  (libsodium reports altered / wrong key / wrong nonce as one outcome, and so does this). An `into`
  buffer of the wrong size panics, exactly like an index out of range.
- **Two forms per operation.** `sealInto(into:, …)` writes a caller's buffer and allocates nothing —
  the per-packet form — and `seal(…)` allocates a `FixedArray<uint8>` on top of it.
- **Keys are passed by `ref`, not `const ref`.** kama has no const raw pointer and refuses `addr(of:)` on
  a const receiver ("const is deep"), so a buffer can only reach C through a mutable borrow.
- **A key pair is taken whole.** A field of a `resource` is always private, and a `ref`-returning
  accessor cannot feed a `ref` parameter, so `box`/`sign`/`kx` take `ref KeyPair`; the public half is
  read out as a value (`PublicKey pk = pair.publicKey();`), which is what goes on the wire.
- **`kx` → channel with no plaintext copy:** `aead::Key.fromSession(keys:, direction:)`.

## What is vendored, and why

`third_party/libsodium/` is libsodium **1.0.20-stable**, pinned by sha256 in
`tools/vendor-libsodium.sh`, copied pristine, and compiled by every consumer through kama's
`csources` (119 files) and `cincludes`. Measured on an M-series Mac: the whole library compiles in
about 2 s of wall time at `-O2` and under 1 s in debug, warning-free under kama's own flag prefix, on
arm64 and x86_64 alike.

Vendored rather than a system `-lsodium` because a consumer then needs nothing installed on any target
(macOS, Linux, Windows, wasm — a system libsodium cannot exist for wasm), a dependency cannot add a
machine path like `-I/opt/homebrew/include` for its consumer, and a shipped binary links one known
libsodium rather than whichever a machine had. Upgrading is changing `VERSION`/`SHA256` in the script,
running it, reading the diff, and bumping this package's version.

The seven x86 assembly files (`.S`) are never selected — `csources` compiles `.c` — so libsodium's C
paths are what compile; they runtime-dispatch to the SIMD C implementations on their own. The
configuration is a `-D` list in `kama.json`'s `cflags` (the set that libsodium's own `build.zig` uses,
minus the assembly). ⚠️ A dependency's `cflags` reach every translation unit of the consumer's build —
kama's design — so the list is only autoconf-style `HAVE_*` names with no plausible collision.

`csrc/kama_sodium.c` is the package's only C: a once-guard over `sodium_init()`, NULL-passing glue for
the two calls whose signatures have optional pointers, and a `_Static_assert` per size the kama side
spells as a literal, so a libsodium upgrade that changed one fails at compile time with the name.

## Tests

`tools/test.sh` builds `tests/` (one program over all six modules) in debug and release and runs it.
Round trips; a flipped byte, the wrong key, the wrong nonce and altered associated data are `Forged`;
short inputs are `BadLength`; the `into` forms match the allocating ones; empty messages; seeded pairs
are deterministic; and a known-answer vector per primitive from libsodium's own `test/default/` (RFC
8032 for Ed25519), extracted from the vendored tarball by script.

## Not here yet

`generichash` (BLAKE2b), `pwhash` (Argon2id), `secretstream`, `kdf`, `auth` (HMAC-SHA512-256), and
`box`'s precomputed shared key (`beforenm`). Each is the same shape as a module here.

## License

MIT (this package). libsodium is ISC; its notice is at `third_party/libsodium/LICENSE`.
