#include <cstdio>
#include <cstdint>
#include <random>

static inline uint32_t fastmod_u32(uint32_t a, uint64_t M, uint32_t d) {
    __uint128_t lowbits = (__uint128_t)M * a;
    return (uint32_t)(((__uint128_t)(uint64_t)lowbits * d) >> 64);
}

int main() {
    // Test against ground-truth %, for the prime sizes used in hashlib_size().
    static const uint32_t primes[] = {
        23, 29, 37, 47, 59, 79, 101, 127, 163, 211, 269, 337, 431, 541, 677,
        853, 1069, 1361, 1709, 2137, 2677, 3347, 4201, 5261, 6577, 8231, 10289,
        12889, 16127, 20161, 25219, 31531, 39419, 49277, 61603, 77017, 96281,
        120371, 150473, 188107, 235159, 293957, 367453, 459317, 574157, 717697,
        897133, 1121423, 1401791, 1752239, 2190299, 2737937, 3422429, 4278037,
        5347553, 6684443, 8355563, 10444457, 13055587, 16319519, 20399411,
        25499291, 31874149, 39842687, 49803361, 62254207, 77817767, 97272239,
        121590311, 151987889, 189984863, 237481091, 296851369, 371064217,
        463830313, 579787991, 724735009, 905918777, 1132398479, 1415498113,
        1769372713, 2211715897u, 2764644887u, 3455806139u
    };

    int errors = 0;
    std::mt19937 rng(42);

    for (uint32_t d : primes) {
        uint64_t M = ~uint64_t(0) / d + 1;
        // Edge cases
        uint32_t test_inputs[] = {0, 1, 2, d - 1, d, d + 1, 2*d, 2*d + 1, 0xFFFFFFFFu, 0xFFFFFFFEu, 0x80000000u, 0x7FFFFFFFu};
        for (uint32_t a : test_inputs) {
            uint32_t expected = a % d;
            uint32_t got = fastmod_u32(a, M, d);
            if (expected != got) {
                printf("FAIL: a=%u d=%u expected=%u got=%u\n", a, d, expected, got);
                if (++errors > 20) return 1;
            }
        }
        // Random tests
        for (int i = 0; i < 1000; ++i) {
            uint32_t a = rng();
            uint32_t expected = a % d;
            uint32_t got = fastmod_u32(a, M, d);
            if (expected != got) {
                printf("FAIL: a=%u d=%u expected=%u got=%u\n", a, d, expected, got);
                if (++errors > 20) return 1;
            }
        }
    }
    printf("Tested %zu primes, errors=%d\n", sizeof(primes)/sizeof(primes[0]), errors);
    return errors == 0 ? 0 : 1;
}
