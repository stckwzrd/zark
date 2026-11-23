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
union ud16 mk_ud16(double a, double b) { union ud16 u; u.d[0] = a; u.d[1] = b; return u; }
double sum_ud16(union ud16 u) { return u.d[0] + u.d[1] * 10; }
union umix16 mk_umix16(double x, long n) { union umix16 u; u.s.x = x; u.s.n = n; return u; }
long sum_umix16(union umix16 u) { return (long)(u.s.x * 100) + u.s.n; }
struct od16 mk_od16(int a, int b) { struct od16 o = { a, b }; return o; }
long sum_od16(long a1, long a2, long a3, long a4, long a5, struct od16 o, long a6) { return a1 + a2 + a3 + a4 + a5 + a6 + o.a * 100 + o.b; }
