#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>
struct sz { size_t n; ssize_t s; ptrdiff_t d; intptr_t ip; uintptr_t up; wchar_t w; bool a; _Bool b; volatile int v; int* volatile vp; volatile unsigned char vb[2]; };
struct bb { bool x; bool y; };
struct bbi { bool x; bool y; int n; };
size_t sizes(size_t n, ssize_t s, ptrdiff_t d, intptr_t ip, uintptr_t up);
wchar_t wnext(wchar_t c);
bool flip(bool b);
_Bool both(_Bool a, bool b);
struct bb mkbb(bool x, bool y);
int bbsum(struct bb v, struct bbi w);
volatile int* vptr(volatile int* p);
int vread(const volatile int* p);
__int128 big128(void);
unsigned __int128 ubig128(void);
struct w128 { __int128 v; };
int take128(__int128 x);
typedef __int128 i128_t;
