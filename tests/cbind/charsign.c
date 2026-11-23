#include "charsign.h"

char first(const char* s) { return s[0]; }
char add1(char c) { return c + 1; }
int widen(char c) { return c; }
signed char sneg(signed char x) { return -x; }
unsigned char ubig(unsigned char x) { return x + 100; }
int count_ch(const cht* s, char** rest) { int n = 0; while (s[n]) n++; *rest = (char*)s + 1; return n; }
void fill(struct cs* p, cht c) { p->c = c; p->s = -3; p->u = 250; p->name[0] = c; p->name[1] = 'a'; p->name[2] = 0; p->name[3] = 0; p->text = "hi"; }
