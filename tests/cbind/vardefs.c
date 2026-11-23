#include "vars.h"

static struct S other = { 1, 0.5 };
int counter = 41;
const char* const names[4] = { "zero", "one", "two", "three" };
struct S table = { 7, 2.5 };
struct opq* handle = (struct opq*)&other;
int arr[3] = { 10, 20, 30 };
int (*hook)(int) = 0;
unsigned char bytes[3] = { 1, 2, 250 };
int type = 5;
int dup_ptr(void) { return 0; }
int read_counter(void) { return counter * 1000 + table.a * 100 + arr[1] + bytes[0] + type; }
int call_hook(int x) { return hook(x); }
