# Gaps found in kama, from building @kama/sodium

Found while making the first external kama package production-ready. Each one is reduced to the
smallest program that shows it, and each was **run** on the version named — none is inferred from
reading the spec.

**Compiler:** `kama 0.9.214+gdc83d7e` (a dev build at `../cstar/out/Darwin-arm64/kama`).
**Reporter:** the `@kama/sodium` repo — every item below is something this package hit naturally while
trying to write the code the obvious way, not something contrived to break the compiler.

Priority is this package's view of impact, not a schedule.

---

## 1. `friend` resolves a qualified path for a free function, but not for a type — HIGH

`friend <accessor>[members];` takes a type, a free function, or a `Type::method`. Across a module
boundary **only the free-function form resolves from a qualified path.** A type — and therefore
`Type::method` and `Type::ctor` — must be `import`ed and named **bare**.

The error does not say so; it says the accessor is unknown, which reads as "you named something that
does not exist" rather than "qualify it differently / import it".

### Reproducer

Two modules, `owner` and `user`:

```kama
// src/owner/owner.kama
export { Secret };
type value Secret {
    int64 n;
    public ctor make(int64 n) { this.n = n; }
    friend fmod::user::Holder::build[n];   // ❌ error: unknown `friend` accessor 'build'
    friend fmod::user::Holder::read[n];    // ❌ error: unknown `friend` accessor 'read'
    friend fmod::user::Holder[n];          // ❌ error: unknown `friend` accessor 'Holder'
    friend fmod::user::freeRead[n];        // ✅ resolves, and genuinely grants
}
```

```kama
// src/user/user.kama
import { fmod::owner::Secret };
export { Holder, freeRead };
type value Holder {
    int64 copied;
    public ctor build(ref Secret s) { this.copied = s.n; }
    public fn int64 read(ref Secret s)  { return s.n; }
}
fn int64 freeRead(ref Secret s) { return s.n; }
```

Adding `import { fmod::user::Holder };` to `owner.kama` and writing the grants **unqualified** —
`friend Holder[n];`, `friend Holder::build[n];`, `friend Holder::read[n];` — compiles and works,
constructor included. So the mechanism is complete; only qualified-path resolution for a type is
missing.

### Why it matters here

`sodium::kx::SessionKeys.copyInto` should be reachable by exactly two constructors,
`aead::Key.fromSession` and `secretbox::Key.fromSession`. Writing that required importing both `Key`
types into `kx.kama` purely to name them, and `as`-renaming them (`AeadKey`, `SecretboxKey`) because
they collide. The import exists for no other reason — it reads as a dependency and is not one.

### Suggested fix

Resolve a qualified path in a `friend` accessor the same way for a type as for a free function. Failing
that, make the diagnostic name the actual problem: *"a type accessor must be imported and named
unqualified"*.

---

## 2. A `friend` grant to a module absent from the program is a hard error — HIGH

A grant naming a symbol in a sibling module fails to compile whenever that module is **not part of the
program being built**. The owner of the private member cannot say "these are my friends" without
forcing every one of those modules into every consumer's build.

This makes owner-declared grants unusable from any widely-imported module, which is exactly where the
shared private members live.

### Reproducer

In this repository, at the commit that introduced it:

```kama
// src/sodium.kama — the ROOT module; every consumer imports it for `Nonce`
type value Nonce {
    friend sodium::aead::sealInto[raw];
    friend sodium::aead::openInto[raw];
    friend sodium::secretbox::sealInto[raw];
    friend sodium::secretbox::openInto[raw];
    friend sodium::box::sealInto[raw];       // ❌ when `box` is not in this program
    friend sodium::box::openInto[raw];       // ❌
    unsafe const fn UnsafeConstPtr<uint8> raw() { … }
}
```

`kama build tests/kama.json` **succeeds** — the test program imports all six modules.
`kama build examples/udp_channel/kama.json` **fails**:

```
:110:0: error: unknown `friend` accessor 'sealInto' in 'sodium::Nonce'
:111:0: error: unknown `friend` accessor 'openInto' in 'sodium::Nonce'
```

The example imports `sodium::aead` and `sodium::kx` and never `sodium::box`, so the two `box` grants
dangle. Same library, same source, different program — one builds and one does not.

### Why it matters here

`Nonce.raw()` is the single accessor in this package that is still `public`, and only for this reason.
It is used by six functions across three modules; granting to them from the root module would drag
`aead` + `secretbox` + `box` into *every* build that touches a nonce — the whole package, for everyone,
to encapsulate one method. The `public` is marked "under protest" in the source with a pointer here.

Note this also collides with the *Modular / opt-in stdlib* row (cstar NOW list): a grant is a hard
dependency edge today, so any stdlib type granting to its siblings pins them all in.

### Suggested fix

Treat a grant whose accessor lives in a module not present in the program as **inert** rather than an
error — it can grant nothing, since the code it names is not being compiled. A typo'd accessor inside a
module that *is* present should stay a hard error, which keeps the `friend_typo` / `friend_unknown`
fixtures meaningful.

---

## 3. `addr(of:)` on a temporary reports a clang error, not a kama one — LOW

Taking the address of an index into a temporary view escapes the front end and surfaces as raw C:

```kama
FixedArray<uint8> f = FixedArray::<uint8>.make(size: 4);
UnsafeConstPtr<uint8> cp = addr(of: f.view()[0]);
```

```
error: cannot take the address of an rvalue of type 'std__collections__ConstView_uint8'
   11 |     uint8_t const* cp = (&((*std__collections__ConstView_uint8__op_index(&(…
```

The emitted C is correct to refuse it. But kama has a good diagnostic for the neighbouring case — a
non-const `ref` taking a temporary says *"its mutation would be lost; bind it to a local first"* — and
this one wants the same sentence. Binding the view to a local is the fix, and nothing says so.

Low priority: the shape is unusual, and the workaround is obvious once the C is read. It is here only
because a package author who does not read C would be stuck.

---

## Checked and NOT a gap

Recorded so nobody re-opens them.

- **A non-const `ref` parameter refusing a temporary.** Correct by design, and the message says why —
  *"its mutation would be lost; bind it to a local first"*. A `const ref` accepts a temporary, so the
  fix is the right signature, not a language change. This package's `publicKey()` workaround was a
  missing `const ref`, not a compiler limitation.
- **Member visibility being per type rather than per file.** This package's `AGENTS.md` used to call
  this an open question and made several members `public` because of it. That was wrong: visibility on
  a type is type-scoped by design, and `friend` is the mechanism — which is more granular than C++'s,
  since it names individual members. Every one of those `public` markers is now a grant, except the one
  blocked by #2 above.
- **An under-const `extern fn` input being silent.** Spelling a read-only C input `UnsafePtr<uint8>` is
  caught by neither compiler, since kama emits no prototype for an extern and `uint8_t *` → `const
  uint8_t *` is a legal C widening. Deliberate, and the consequence of not emitting prototypes. It is a
  documentation duty for package authors — recorded in this repo's `AGENTS.md` — not a compiler bug.
