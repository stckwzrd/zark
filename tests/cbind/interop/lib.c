#include <stdarg.h>
#include "lib.h"

pt pt_make(int x, double y) { pt p = { x, y }; return p; }
double pt_sum(pt p) { return p.x + p.y; }
int box_area(const struct box* b) { return b->w * b->h + b->corner.x; }
int apply(binop f, int a, int b) { return f(a, b) + 1; }
const char* color_name(enum color c) {
    switch (c) {
    case RED: return "red";
    case GREEN: return "green";
    case BLUE: return "blue";
    }
    return "?";
}
int sum_ints(int n, ...) {
    va_list ap;
    va_start(ap, n);
    int s = 0;
    for (int i = 0; i < n; i++) s += va_arg(ap, int);
    va_end(ap);
    return s;
}
double num_get(const num* n, int is_double) { return is_double ? n->d : n->i; }
int lib_magic(void) { return LIB_MAGIC; }
