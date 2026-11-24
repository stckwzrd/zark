struct U { union { int i; float f; }; struct { char p, q; } pq; struct { short s1, s2; }; int tail; };
union Num { int i; double d; unsigned bits : 4; };
typedef struct { int a; int b; } P;
typedef struct Named { int z; } NamedT, *NamedP;
struct S2 { union { int x; struct { short lo, hi; } h; } w; };
struct NTm { NTm(const NTm&); int z; };
union NTU { NTm m; int i; NTU(); NTU(const NTU&); ~NTU(); };
int takep(P p);
int taken(NamedP p);
