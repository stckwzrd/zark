#include "bits.h"

long long flags_sum(struct flags f) { return f.a + f.s * 10LL + f.on * 1000LL + f.h * 10000LL + (long long)f.wide * 1000000LL; }
long long flags_sump(const struct flags* f) { return flags_sum(*f); }
void flags_set(struct flags* f) { f->a = 6; f->s = -16; f->on = 0; f->wide = 0x1FFFFFFFFULL; f->h = 63; f->tag = 'x'; }
struct flags flags_make(void) { struct flags f = { 0 }; f.a = 3; f.s = 15; f.on = 1; f.wide = 1; f.h = -64; return f; }
int nib_val(nib_t n) { return n.hi * 16 + n.lo; }
