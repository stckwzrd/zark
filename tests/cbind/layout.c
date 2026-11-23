#include "layout.h"

int takebits(struct bits b) { return b.a + b.b * 10 + b.c * 100 + b.d * 1000 + (int)b.e * 10000; }
int takebitsp(struct bits* b) { return takebits(*b); }
int takeald(struct ald a) { return a.c; }
