enum color { RED, GREEN, BLUE };
struct pt { int x; int y; };
union mix { float f; double d; };
typedef unsigned int word;
typedef int myint;
static inline int add(int a, int b) { return a + b; }
static inline double half(double x) { return x / 2; }
static inline int *nextp(int *p) { return p + 1; }
static inline unsigned long slen(const char *s) { unsigned long n = 0; while (s[n]) n++; return n; }
static inline const char *skip(const char *s, int n) { return s + n; }
static inline enum color next_color(enum color c) { return (enum color)((c + 1) % 3); }
static inline _Bool is_even(int x) { return x % 2 == 0; }
static inline word mask(word w, unsigned char bits) { return w & ((1u << bits) - 1); }
static inline void pt_move(struct pt *p, int dx, int dy) { p->x += dx; p->y += dy; }
static inline struct pt pt_make(int x, int y) { struct pt p = { x, y }; return p; }
static inline void noop(void) {}
static inline __attribute__((always_inline)) int forced(int x __attribute__((unused))) { return 7; }
static inline int apply(int (*f)(int), int v) { return f(v); }
static inline int sum4(const int a[4]) { return a[0] + a[1] + a[2] + a[3]; }
static inline int dbl(int x) { return x * 2; }
static inline int quad(int x) { return dbl(dbl(x)); }
static inline int match(int x) { return -x; }
static inline int later(int x);
static inline int later(int x) { return x + 100; }
inline int twice(int x) { return x * 2; }
static inline int sq(int x) { return x * x; }
#define sq(x) (-1)
static inline myint ident(myint v) { return v; }
#define myint long
static inline int vsum(int n, ...) { return n; }
static inline long double ld(long double x) { return x; }
static inline union mix mixit(union mix m) { return m; }
static inline int applyp(int (*f)(struct pt), struct pt p) { return f(p); }
static inline int sumn(int n, int a[n]) { return a[0] + n; }
static inline int kr(a) int a; { return a; }
static int plain_static(int x) { return x; }
int ext(int x);
