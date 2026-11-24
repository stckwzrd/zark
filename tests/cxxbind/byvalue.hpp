struct V { int x; };
struct S { V v; int y; };
struct Own { int n; V v; void poke(const V& a); };
inline int bump(const V& a, S* s) { s->y += a.x; return s->y; }
inline int store(const V& a, void* p) { return a.x + (p != 0); }
inline int ro(const V& a, const V& b) { return a.x + b.x; }
namespace g {
struct Q { int x; };
struct R { Q q; };
inline int fill(const Q& a, R* r) { r->q.x = a.x; return r->q.x; }
}
