typedef int a1;
static inline __attribute__((always_inline, target("avx2"))) int avx(int x) { return x; }
static inline int unav(int x) __attribute__((unavailable("no")));
static inline int unav(int x) { return x; }
static inline int errf(int x) __attribute__((error("no")));
static inline int errf(int x) { return x; }
static inline int warnf(int x) __attribute__((warning("careful")));
static inline int warnf(int x) { return x; }
static inline int diag(int x) __attribute__((diagnose_if(x < 0, "negative", "error")));
static inline int diag(int x) { return x; }
static inline int a0(int x) { return x; }
static inline int zark_inl_foo(int x) { return x; }
static inline int foo(int x) { return x + 5; }
static inline int usea1(int x, int y, a1 z) { return x + y + z; }
static inline int type(int x) { return x; }
static inline int i32(int x) { return x; }
static inline int type_(int x) { return x + 1; }
static int g(int);
static inline int g(int x) { return x + 2; }
static inline const char *const cc(const char *const x) { return x + 1; }
static inline int volatile vq(int x) { return x * 3; }
static inline int old(int x) __attribute__((deprecated));
static inline int old(int x) { return x * 10; }
