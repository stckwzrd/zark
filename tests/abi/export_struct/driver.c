#include <stdio.h>

typedef struct { int x, y; } P;

extern P addp(P a, P b);

int run_export_addp(void) {
    P a = { 1, 2 };
    P b = { 3, 4 };
    P r = addp(a, b);
    printf("C sees: %d %d\n", r.x, r.y);
    return r.x * 10 + r.y;
}
