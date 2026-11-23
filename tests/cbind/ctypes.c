#include "ctypes.h"

size_t sizes(size_t n, ssize_t s, ptrdiff_t d, intptr_t ip, uintptr_t up) { return n + s + d + ip + up; }
wchar_t wnext(wchar_t c) { return c + 1; }
bool flip(bool b) { return !b; }
_Bool both(_Bool a, bool b) { return a && b; }
struct bb mkbb(bool x, bool y) { struct bb r = { x, y }; return r; }
int bbsum(struct bb v, struct bbi w) { return v.x + v.y * 2 + w.x * 4 + w.y * 8 + w.n * 16; }
volatile int* vptr(volatile int* p) { return p + 1; }
int vread(const volatile int* p) { return *p; }
