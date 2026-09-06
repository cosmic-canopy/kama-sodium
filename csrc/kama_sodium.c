#include "kama_sodium.h"
#include <stdatomic.h>
#include <string.h>

static atomic_int kama_sodium_ready = 0;

int32_t kama_sodium_init(void)
{
    if (atomic_load_explicit(&kama_sodium_ready, memory_order_acquire)) return 0;
    if (sodium_init() < 0) return -1;
    atomic_store_explicit(&kama_sodium_ready, 1, memory_order_release);
    return 0;
}

int32_t kama_sodium_aead_encrypt(uint8_t *c, const uint8_t *m, unsigned long long mlen,
                                 const uint8_t *ad, unsigned long long adlen,
                                 const uint8_t *npub, const uint8_t *k)
{
    return crypto_aead_xchacha20poly1305_ietf_encrypt(c, NULL, m, mlen, adlen ? ad : NULL, adlen, NULL, npub, k);
}

int32_t kama_sodium_aead_decrypt(uint8_t *m, const uint8_t *c, unsigned long long clen,
                                 const uint8_t *ad, unsigned long long adlen,
                                 const uint8_t *npub, const uint8_t *k)
{
    return crypto_aead_xchacha20poly1305_ietf_decrypt(m, NULL, NULL, c, clen, adlen ? ad : NULL, adlen, npub, k);
}

int32_t kama_sodium_sign_detached(uint8_t *sig, const uint8_t *m, unsigned long long mlen, const uint8_t *sk)
{
    return crypto_sign_detached(sig, NULL, m, mlen, sk);
}

uint8_t *kama_sodium_copy(uint8_t *dst, const uint8_t *src, size_t n) { return memcpy(dst, src, n); }
size_t   kama_sodium_strlen(const uint8_t *s) { return strlen((const char *)s); }
uint8_t *kama_sodium_version(void) { return (uint8_t *)sodium_version_string(); }

/* Every size the kama modules spell as a literal (an `InlineArray<uint8>#(N)` needs a compile-time N,
   which a C function returning it cannot be), pinned to libsodium's macro. A libsodium upgrade that
   changed one fails here, at compile time, with the name — not at run time with a short buffer. */
_Static_assert(crypto_secretbox_KEYBYTES   == 32, "secretbox::KEYBYTES");
_Static_assert(crypto_secretbox_NONCEBYTES == 24, "secretbox::NONCEBYTES");
_Static_assert(crypto_secretbox_MACBYTES   == 16, "secretbox::MACBYTES");

_Static_assert(crypto_aead_xchacha20poly1305_ietf_KEYBYTES  == 32, "aead::KEYBYTES");
_Static_assert(crypto_aead_xchacha20poly1305_ietf_NPUBBYTES == 24, "aead::NONCEBYTES");
_Static_assert(crypto_aead_xchacha20poly1305_ietf_ABYTES    == 16, "aead::MACBYTES");

_Static_assert(crypto_box_PUBLICKEYBYTES == 32, "box::PUBLICKEYBYTES");
_Static_assert(crypto_box_SECRETKEYBYTES == 32, "box::SECRETKEYBYTES");
_Static_assert(crypto_box_NONCEBYTES     == 24, "box::NONCEBYTES");
_Static_assert(crypto_box_MACBYTES       == 16, "box::MACBYTES");
_Static_assert(crypto_box_SEALBYTES      == 48, "box::SEALBYTES");
_Static_assert(crypto_box_SEEDBYTES      == 32, "box::SEEDBYTES");

_Static_assert(crypto_sign_PUBLICKEYBYTES == 32, "sign::PUBLICKEYBYTES");
_Static_assert(crypto_sign_SECRETKEYBYTES == 64, "sign::SECRETKEYBYTES");
_Static_assert(crypto_sign_BYTES          == 64, "sign::BYTES");
_Static_assert(crypto_sign_SEEDBYTES      == 32, "sign::SEEDBYTES");

_Static_assert(crypto_kx_PUBLICKEYBYTES  == 32, "kx::PUBLICKEYBYTES");
_Static_assert(crypto_kx_SECRETKEYBYTES  == 32, "kx::SECRETKEYBYTES");
_Static_assert(crypto_kx_SESSIONKEYBYTES == 32, "kx::SESSIONKEYBYTES");
_Static_assert(crypto_kx_SEEDBYTES       == 32, "kx::SEEDBYTES");
