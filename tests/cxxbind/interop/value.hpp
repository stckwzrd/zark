namespace geo {
struct V { float x = 0; float y = 0; };
struct Vec { double x, y; int k; };
class Priv { double d; public: int pub; void set(double v) { d = v; } };
struct NP { NP(); int n; char c; };
struct TP : NP { char t; };
struct Shape { virtual ~Shape(); int id; };
struct Circle : Shape { ~Circle(); double r; };
struct alignas(16) A16 { char c; int v; };
struct M1 { int a; };
struct M2 { virtual void f(); int b; };
struct MM : M1, M2 { int c; };
struct Bits { unsigned a : 3; int s : 5; unsigned b : 7; };
struct An { int tag; union { int i; float f; }; struct { short lo, hi; } pr; };
V add(const V& a, V b);
V scale(V v, float k);
float len2(const V& v);
void lay(int which, long* out);
void fill(MM* m, TP* t, Circle* c, Bits* b, An* an, Priv* p, A16* x);
long check(const MM* m, const TP* t, const Circle* c, const Bits* b, const An* an, const Priv* p, const A16* x);
Circle* newcircle(double r);
void del(Shape* s);
}
