#include <cstring>
#include "kernel/hashlib.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

using namespace hashlib;

namespace hashlib {
HasherDJB32::hash_t HasherDJB32::fudge = 0;
}

template<typename F>
static double ns_per_op(int ops, F &&f) {
    auto start = std::chrono::steady_clock::now();
    f();
    auto stop = std::chrono::steady_clock::now();
    return std::chrono::duration<double, std::nano>(stop - start).count() / ops;
}

int main() {
    const int keys = 200000;
    const int probes = 2000000;

    dict<int, int> db;
    db.reserve(keys);
    for (int i = 0; i < keys; ++i)
        db[i] = i * 3;
    volatile int sink = 0;
    double dict_lookup = ns_per_op(probes, [&] {
        for (int i = 0; i < probes; ++i)
            sink += db.at((unsigned(i) * 2654435761u) % keys);
    });

    pool<int> p;
    p.reserve(keys);
    double pool_insert = ns_per_op(keys, [&] {
        for (int i = 0; i < keys; ++i)
            p.insert(i);
    });
    double pool_count = ns_per_op(keys, [&] {
        for (int i = 0; i < keys; ++i)
            sink += p.count((unsigned(i) * 2654435761u) % keys);
    });
    double pool_erase = ns_per_op(keys, [&] {
        for (int i = 0; i < keys; ++i)
            p.erase(i);
    });

    std::printf("{\n");
    std::printf("  \"keys\": %d,\n", keys);
    std::printf("  \"probes\": %d,\n", probes);
    std::printf("  \"dict_int_lookup_ns_per_op\": %.6f,\n", dict_lookup);
    std::printf("  \"pool_int_insert_ns_per_op\": %.6f,\n", pool_insert);
    std::printf("  \"pool_int_count_ns_per_op\": %.6f,\n", pool_count);
    std::printf("  \"pool_int_erase_ns_per_op\": %.6f,\n", pool_erase);
    std::printf("  \"sink\": %d\n", int(sink));
    std::printf("}\n");
    return 0;
}
