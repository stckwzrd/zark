#include <stdint.h>
#include <stdio.h>

typedef struct { int64_t a, b, c; } B;

extern B makeb(int64_t x);

int64_t run_export_big(void) {
    B b = makeb(10);
    printf("C sees: %lld %lld %lld\n", (long long)b.a, (long long)b.b, (long long)b.c);
    return b.a + b.b + b.c;
}
