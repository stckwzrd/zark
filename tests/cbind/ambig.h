#define PAIR struct { char c; int i; } p; struct { short s; long l; } q
struct E { PAIR; };
struct F { char z; PAIR; };
struct G { struct { char a; } x; struct { int b; } y; };
