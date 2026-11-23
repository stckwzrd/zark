#include "fnptr.h"

static struct pt origin = { 7, 8 };
static int twice(union im* m) { return m->i * 2; }
static struct pt* where(void) { return &origin; }
struct ptrfp mkp(void) { struct ptrfp h = { twice, where }; return h; }
int callp(int (*cb)(union im*), int x) { union im m; m.i = x; return cb(&m) + 1; }
