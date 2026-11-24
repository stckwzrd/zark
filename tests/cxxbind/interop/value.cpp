#include "value.hpp"
#include <cstddef>

#define OFF(o, f) (long)((const char*)&(o).f - (const char*)&(o))

namespace geo {
NP::NP() : n(0), c(0) {}
Shape::~Shape() {}
Circle::~Circle() {}
void M2::f() {}

V add(const V& a, V b) { return V{a.x + b.x, a.y + b.y}; }
V scale(V v, float k) { return V{v.x * k, v.y * k}; }
float len2(const V& v) { return v.x * v.x + v.y * v.y; }

void lay(int which, long* out) {
    static V v;
    static Vec vec;
    static Priv p;
    static TP tp;
    static Circle c;
    static A16 a;
    static MM mm;
    static An an;
    switch (which) {
    case 0: out[0] = sizeof(V); out[1] = alignof(V); out[2] = OFF(v, x); out[3] = OFF(v, y); break;
    case 1: out[0] = sizeof(Vec); out[1] = alignof(Vec); out[2] = OFF(vec, x); out[3] = OFF(vec, y); out[4] = OFF(vec, k); break;
    case 2: out[0] = sizeof(Priv); out[1] = alignof(Priv); out[2] = OFF(p, pub); break;
    case 3: out[0] = sizeof(TP); out[1] = alignof(TP); out[2] = OFF(tp, n); out[3] = OFF(tp, c); out[4] = OFF(tp, t); break;
    case 4: out[0] = sizeof(Circle); out[1] = alignof(Circle); out[2] = OFF(c, id); out[3] = OFF(c, r); break;
    case 5: out[0] = sizeof(A16); out[1] = alignof(A16); out[2] = OFF(a, c); out[3] = OFF(a, v); break;
    case 6: out[0] = sizeof(MM); out[1] = alignof(MM); out[2] = OFF(mm, a); out[3] = OFF(mm, b); out[4] = OFF(mm, c); break;
    case 7: out[0] = sizeof(An); out[1] = alignof(An); out[2] = OFF(an, tag); out[3] = OFF(an, i); out[4] = OFF(an, pr.lo); out[5] = OFF(an, pr.hi); break;
    case 8: out[0] = sizeof(Bits); out[1] = alignof(Bits); break;
    }
}

void fill(MM* m, TP* t, Circle* c, Bits* b, An* an, Priv* p, A16* x) {
    m->a = 11; m->b = 12; m->c = 13;
    t->n = 21; t->c = 'x'; t->t = 'y';
    c->id = 31; c->r = 2.5;
    b->a = 5; b->s = -7; b->b = 100;
    an->tag = 41; an->f = 1.5f; an->pr.lo = -3; an->pr.hi = 4;
    p->pub = 51; p->set(9.5);
    x->c = 'q'; x->v = 61;
}

long check(const MM* m, const TP* t, const Circle* c, const Bits* b, const An* an, const Priv* p, const A16* x) {
    return m->a + m->b * 10 + m->c * 100 + t->n * 1000 + (t->c == 'a') + (t->t == 'b') * 2 + c->id * 10000
        + (c->r == 0.5) * 4 + b->a * 100000 + b->s * 1000000 + b->b * 10000000L + an->tag * 100000000L + an->i
        + an->pr.lo * 10L + an->pr.hi * 1000L + p->pub * 1000000000L + (x->c == 'z') * 8 + x->v * 10000000000L;
}

Circle* newcircle(double r) { Circle* c = new Circle(); c->id = 77; c->r = r; return c; }
void del(Shape* s) { delete s; }
}
