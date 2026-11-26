// The C twin of examples/bench.zk, for a like-for-like runtime comparison.
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

static long fib(long n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

static long sieve(unsigned char* flags, long n) {
    long count = 0;
    for (long i = 2; i <= n; i++) {
        if (!flags[i]) {
            count++;
            for (long j = i * i; j <= n; j += i) flags[j] = 1;
        }
    }
    return count;
}

static double ms(clock_t a, clock_t b) {
    return (double)(b - a) * 1000.0 / (double)CLOCKS_PER_SEC;
}

int main(void) {
    const long n = 50000000;
    unsigned char* flags = calloc((size_t)n + 1, 1);
    if (flags == NULL) return 1;
    const clock_t t0 = clock();
    const long f = fib(38);
    const clock_t t1 = clock();
    const long p = sieve(flags, n);
    const clock_t t2 = clock();
    printf("fib(38) = %ld  in %.1f ms\n", f, ms(t0, t1));
    printf("primes < 50M = %ld  in %.1f ms\n", p, ms(t1, t2));
    free(flags);
    return 0;
}
