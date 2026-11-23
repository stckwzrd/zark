typedef struct jbt { long b[8]; int m; } jb_t[1];

typedef float vec3[3];
typedef int t0;
typedef t0 t1;
typedef t1* t2;
typedef t2 t3[4];
typedef int fn_t(int);
typedef fn_t fn2_t;
struct cbs { fn_t* cb; fn_t** cbp; vec3 v; };
void usev(vec3 v);
int usej(jb_t b);
void tcf(t3 arr, t1 v);
void takefn(fn_t f, fn_t* g, fn2_t* h);
fn_t* retfn(void);
