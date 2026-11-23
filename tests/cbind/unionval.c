#include "unionval.h"

union ud put_ud(union ud u) { u.d += 1; return u; }
union udi put_udi(union udi u) { u.i += 1; return u; }
union uff put_uff(union uff u) { u.a += 1; return u; }
union ufd put_ufd(union ufd u) { u.d += 1; return u; }
union fi3 put_fi3(union fi3 u) { u.f[0] += 1; u.f[1] += 2; u.f[2] += 3; return u; }
union dd put_dd(union dd u) { u.d[0] += 1; u.d[1] += 2; return u; }
struct sud put_sud(struct sud s) { s.k += 1; s.u.d += 1; return s; }
float take_pf(union pf u) { return u.f; }
double mix(union uff a, double x, union udi b, union fi3 c, union ud d, int y) {
    return a.a + x + b.i + c.f[0] + c.f[1] + c.f[2] + d.d + y;
}
