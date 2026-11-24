#include "refalias.hpp"

void M::addtwice(const M& o) { x += o.x; x += o.x; }
int M::peek(const V& a) const { return a.x + x; }
int M::with(const V& a, const V& b) const { return a.x * 10 + b.x + x; }
int M::smul(const V& a, int k) { return a.x * k; }
void Own::poke(const V& a) { w->x += 10; n = a.x; }
int bump(const V& a, S* s) { s->v.x += 10; return a.x; }
int via_h(const V& a, H* h) { h->p->x += 20; return a.x; }
int via_hh(const V& a, V** h) { (*h)->x += 30; return a.x; }
int via_void(const V& a, void* p) { static_cast<V*>(p)->x += 40; return a.x; }
int via_arr(const V& a, V (*arr)[2]) { (*arr)[0].x += 50; return a.x; }
int via_td(const VT& a, VT* b) { b->x += 60; return a.x; }
int via_ref(const V& a, V& b) { b.x += 70; return a.x; }
int via_hv(const V& a, HV* h) { static_cast<V*>(h->p)->x += 80; return a.x; }
int via_int(const V& a, int* p) { *p += 90; return a.x; }
int two(const V& a, const V& b, int* c) { *c += 5; return a.x + b.x; }
int ro(const V& a, const V& b) { return a.x * 100 + b.x; }
int len(const V& a, const char* s, int k) { return a.x + k + (s ? 1 : 0); }
int sq(const int& a) { return a * a; }
V& operator+=(V& a, const V& b) { a.x += b.x; a.x += b.x; return a; }
V operator+(const V& a, const V& b) { return V{a.x * 2 + b.x}; }
