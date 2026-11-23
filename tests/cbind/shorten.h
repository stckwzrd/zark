enum E { A, B };
enum N { NA = -1, NB = 1 };
enum W { W1 = 70000 };
enum F : int { F1 };
enum L { L1 = 0x100000000 };
struct S { char c; enum E e; char d; };
struct T { enum N n; enum W w; enum F f; enum L l; };
int f(enum E e);
