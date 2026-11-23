#include "unions.h"

union U pass(union U u) { u.i += 1; return u; }
union U* pick(union U* a, int n) { return &a[n]; }
void setd(union U* u, double d) { u->d = d; }
double mixsum(union mix m) { return m.d; }
int hsum(handle_t h) { return h.a; }
double vsum(var_t v) { return v.tag + v.v.d; }
struct holder make_holder(int k) {
    struct holder h = { k, { 0 }, { 'a', 'b' } };
    h.u.y = k * 0.5f;
    return h;
}
union fwd* get_fwd(void) { return 0; }
struct bind mkbind(int k) {
    struct bind b = { k };
    b.v.p.x = k + 1;
    b.v.p.y = k + 2;
    return b;
}
long csize(int which) {
    switch (which) {
    case 0: return sizeof(union U);
    case 1: return sizeof(union small);
    case 2: return sizeof(union bytes);
    case 3: return sizeof(struct holder);
    case 4: return sizeof(struct ev);
    case 5: return sizeof(handle_t);
    case 6: return sizeof(var_t);
    case 7: return sizeof(struct list);
    case 8: return sizeof(union cbu);
    case 9: return sizeof(union part);
    }
    return _Alignof(struct list);
}
