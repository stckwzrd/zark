struct el { char c; } __attribute__((aligned(8)));
typedef struct el el_t;
struct f1 { int n; struct el e[]; };
struct f1b { int n; el_t e[]; };
struct f1c { int n; struct el e[0]; };
struct o1 { char c; struct f1 f; };
struct o1c { char c; struct f1c f; };
struct f2 { long n; struct el e[]; };
