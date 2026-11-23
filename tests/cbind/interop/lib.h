#ifndef LIB_H
#define LIB_H

#define LIB_MAGIC 42
#define LIB_NAME "interop"

typedef struct pt { int x; double y; } pt;

struct box { int w; int h; struct pt corner; };

enum color { RED = 1, GREEN = 5, BLUE = 10 };

typedef union num { int i; double d; } num;

typedef int (*binop)(int a, int b);

pt pt_make(int x, double y);
double pt_sum(pt p);
int box_area(const struct box* b);
int apply(binop f, int a, int b);
const char* color_name(enum color c);
int sum_ints(int n, ...);
double num_get(const num* n, int is_double);
int lib_magic(void);

static inline int scaled(int v) { return v * LIB_MAGIC; }

#endif
