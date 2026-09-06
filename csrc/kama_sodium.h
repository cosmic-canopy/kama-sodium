#ifndef KAMA_SODIUM_H
#define KAMA_SODIUM_H
/* The one piece of C this package writes: a once-guard over sodium_init(), and the compile-time proof
   that every size the kama side spells as a literal is the size the vendored libsodium has. The
   cryptography is libsodium's, reached directly by `extern fn` from each kama module. */
#include <stdint.h>
#include <sodium.h>

/* 0 once libsodium is initialized (this call or an earlier one), -1 if it refused. Cheap after the
   first call — an acquire load — so every wrapper calls it and none has to remember whether it did.
   sodium_init() itself is idempotent and thread-safe; the guard only skips its lock on the hot path. */
int32_t kama_sodium_init(void);

/* Glue for the calls whose C signature has a NULL-or-pointer parameter kama has no need to spell:
   the AEAD's optional output-length and unused `nsec`, and detached signing's optional length. Each is
   the libsodium call with those arguments fixed, and nothing else. */
int32_t kama_sodium_aead_encrypt(uint8_t *c, const uint8_t *m, unsigned long long mlen,
                                 const uint8_t *ad, unsigned long long adlen,
                                 const uint8_t *npub, const uint8_t *k);
int32_t kama_sodium_aead_decrypt(uint8_t *m, const uint8_t *c, unsigned long long clen,
                                 const uint8_t *ad, unsigned long long adlen,
                                 const uint8_t *npub, const uint8_t *k);
int32_t kama_sodium_sign_detached(uint8_t *sig, const uint8_t *m, unsigned long long mlen, const uint8_t *sk);
/* memcpy, reachable from kama without a <string.h> extern of its own. */
uint8_t *kama_sodium_copy(uint8_t *dst, const uint8_t *src, size_t n);
/* The version string, as the bytes kama's string constructor takes, and its length. */
uint8_t       *kama_sodium_version(void);
size_t         kama_sodium_strlen(const uint8_t *s);

#endif
