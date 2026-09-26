# Gaps found in kama, from building @kama/sodium

Found while making the first external kama package production-ready. Each one is reduced to the
smallest program that shows it, and each was **run** on the version named — none is inferred from
reading the spec.

**Current compiler:** `kama 0.9.451+g4bcfc264` (a dev build at `../cstar/out/Darwin-arm64/kama`), and
the public release `0.9.440`. `tools/test.sh` is green on both; `tools/test-wasm.sh` on `0.9.451`.
**Reporter:** the `@kama/sodium` repo — every item is something this package hit naturally while
trying to write the code the obvious way, not something contrived to break the compiler.

---

## OPEN

Nothing. Every gap this package has filed is fixed upstream.

---

## FIXED — kept for the record

### 4. The embedded agent guidance contradicted the compiler — FIXED in 0.9.237

Fixed by `7f232b57`, which rewrote all three bullets and took the root-cause suggestion too: the
"the compiler rejects this" sentences in `agents/AGENTS.md` now each name the fixture that proves
them, under the same claim guard `SPEC.md` has, so a new one without a fixture fails the gate.
Confirmed here on `0.9.451`: `kama agents install --force` writes none of the three, and the warning
that `AGENTS.sodium.md` carried against them is gone. The original report follows.

`kama agents install` writes `AGENTS.md` from the copy embedded in the binary (`agents/` in the cstar
tree). On `0.9.233` that file still carries **three claims that the compiler stopped honouring up to
thirty versions ago**, and one of them is the specific misconception that cost this package a whole
release cycle. It is the worst kind of stale doc: it is *generated*, so it reinstalls itself into every
new kama project, and an agent reading it has been told explicitly to trust it.

The three, quoted verbatim from the `0.9.233`-generated `AGENTS.md`:

> - **A buffer reaches C through `ref`, never `const ref`.** There is no const raw pointer, and
>   `addr(of:)` on a const receiver is refused ("const is deep"). An FFI wrapper that only reads still
>   takes `ref`.

**False since 0.9.204/0.9.205.** `UnsafeConstPtr<T>` exists, `dataPtr()` is a `const fn` returning it,
and `addr(of:)` on a const root hands one back — which is what commit `4436966` says it does. Verified:

```kama
type value Holder {
    public InlineArray<uint8>#(4) bytes;
    public ctor zeroed() { this.bytes = [0; 4]; }
    public unsafe const fn UnsafeConstPtr<uint8> raw() { return this.bytes.dataPtr(); }
}
extern fn usize strlen(UnsafeConstPtr<uint8> s);
unsafe fn usize readsThroughConstRef(const ref Holder h) { return strlen(s: h.raw()); }
unsafe fn usize addrOnConstRoot(const ref Holder h) {
    UnsafeConstPtr<uint8> p = addr(of: h.bytes[0]);   // "refused" per the guidance
    return strlen(s: p);
}
fn int32 main() { Holder h = Holder.zeroed(); return cast<int32>(readsThroughConstRef(h: h) + addrOnConstRoot(h: h)); }
```

Builds clean. This whole package now passes keys and nonces by `const ref` and reaches C from them.

> - **Member visibility is per TYPE.** A non-`public` ctor or method is invisible even to a free function
>   in the same file; a helper ctor a free function fills has to be `public`.

The first sentence is right; **"has to be `public`" is wrong** — that is what `friend` is for, and it is
granular enough to name one member for one accessor. This package has **37 grants** and, as of this
commit, not one public raw accessor. The generated `AGENTS.package.md` contradicts this bullet directly
in its own § *Private helpers across modules*, so the two halves of the shipped guidance disagree with
each other.

This is the exact claim that made this package expose `zeroed()`, `raw()`, `rawMut()` and the session-key
copy as public API for two releases.

> - **A `ref`-returning method call cannot feed a `ref` parameter** — a call result is a temporary and
>   its mutation would be lost. Pass the owner by `ref` instead …

True as far as it goes, and the reasoning is right, but it omits the fix that makes it a non-issue: a
**`const ref` parameter takes a temporary fine.** As written it pushes an author toward passing whole
owners by mutable `ref` — which is what this package did, and why its API was `ref KeyPair` until 0.2.0.

**Suggested fix:** delete the first bullet, change the second to point at `friend`, and add the `const
ref` half to the third. More generally these bullets have no test holding them to the compiler, unlike
`SPEC.md`, whose claims carry `<!-- test: -->` / `<!-- xfail: -->` markers — that asymmetry is probably
the root cause.

### 1. `friend` did not resolve a qualified path for a type — FIXED in 0.9.227

`friend fmod::user::Holder[n]`, `::Holder::build`, `::Holder::read` all failed with *"unknown `friend`
accessor"* while the free-function form resolved; the workaround was importing the type and naming it
bare. Fixed by `4534568`. This package now writes `friend sodium::aead::Key::fromSession[copyInto];`
directly, and `kx.kama` no longer imports two `Key` types (`as`-renamed to dodge a collision) purely to
name them in grants.

### 2. A grant into a module absent from the program was a hard error — FIXED in 0.9.227

`kama build tests/kama.json` succeeded and `kama build examples/udp_channel/kama.json` failed on the
same source, because the example never imports `sodium::box` so two `box` grants dangled. Grants into an
absent module are now **inert**, which was the suggested fix. The payoff here is direct: `Nonce.raw()`
was this package's last public accessor, kept public only because `Nonce` lives in the root module that
every consumer imports. It is now private with six grants, and the example — which never compiles `box`
— builds with the two `box` grants inert.

### 3. `addr(of:)` on a temporary reported a clang error — FIXED in 0.9.229

`addr(of: f.view()[0])` escaped as clang's *"cannot take the address of an rvalue"*. Now a kama
diagnostic (`dfe05b6`).

---

## Checked and NOT a gap

Recorded so nobody re-opens them.

- **A non-const `ref` parameter refusing a temporary.** Correct by design, and the message says why —
  *"its mutation would be lost; bind it to a local first"*. A `const ref` accepts a temporary, so the
  fix is the right signature, not a language change.
- **Member visibility being type-scoped.** Deliberate; `friend` is the mechanism, and it is more
  granular than C++'s since it names individual members. (See gap #4 — the shipped guidance still says
  otherwise.)
- **An under-const `extern fn` input being silent.** Spelling a read-only C input `UnsafePtr<uint8>` is
  caught by neither compiler, since kama emits no prototype for an extern and `uint8_t *` → `const
  uint8_t *` is a legal C widening. Deliberate, and now documented in the generated `AGENTS.package.md`
  § *The C seam is spelled from the header*.
- **`cchar` does not apply to this package.** Every libsodium pointer at this seam is genuinely
  `unsigned char *`, not `char *`, so `UnsafeConstPtr<uint8>` stays correct. The one conversion in
  `csrc/kama_sodium.c` — `sodium_version_string()`'s `const char *` to `const uint8_t *` — is a real
  boundary cast, because kama builds a `string` from bytes via `kama_string_from_raw`, which takes
  `UnsafeConstPtr<uint8>`.
