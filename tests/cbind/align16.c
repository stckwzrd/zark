#include "align16.h"

struct pair16 mk_pair(long a, long b) { struct pair16 p = { a, b }; return p; }
long sum_pair(struct pair16 p) { return p.a * 10 + p.b; }
double sum_dbl(struct dbl16 d) { return d.x + d.y * 2; }
struct dbl16 mk_dbl(double x, double y) { struct dbl16 d = { x, y }; return d; }
long sum_mix(struct mix16 m) { return (long)m.d + m.n; }
int get_a16(struct a16 a) { return a.c; }
long sum_has(struct has16 h) { return h.k + h.p.a + h.p.b; }
long sum_big(struct big16* b) { return b->a + b->b + b->c; }
int a32_x(struct a32* p) { return ((unsigned long)p % 32 == 0) * 1000 + p->x; }
long sum_has_p(struct has16* h) { return ((unsigned long)h % 16 == 0) * 1000 + h->k + h->p.a + h->p.b; }
int read_un16(union un16* u) { return (int)u->l; }
