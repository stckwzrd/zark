// C side of tests/abi/main.vibe
typedef struct { float x, y; } Vec2;
typedef struct { unsigned char r, g, b, a; } Color;
typedef struct { float x, y, w, h; } Rect;
typedef struct { long a; double b; } Mixed;
typedef struct { int id; float w, h, d; long tag; } Big;
float vlen2(Vec2 v) { return v.x * v.x + v.y * v.y; }
Vec2 vadd(Vec2 a, Vec2 b) { Vec2 r = { a.x + b.x, a.y + b.y }; return r; }
int csum(Color c) { return c.r + c.g + c.b + c.a; }
Color cmake(int r, int g, int b) { Color c = { r, g, b, 255 }; return c; }
float rarea(Rect r) { return r.w * r.h; }
Rect rgrow(Rect r, float k) { Rect o = { r.x, r.y, r.w * k, r.h * k }; return o; }
double msum(Mixed m) { return m.a + m.b; }
Mixed mmake(long a, double b) { Mixed m = { a, b }; return m; }
long bsum(Big b) { return b.id + (long)b.w + (long)b.h + (long)b.d + b.tag; }
Big bmake(int id) { Big b = { id, 1.5f, 2.5f, 3.5f, 100 }; return b; }
typedef struct { double x; double y; double z; } V3;
typedef struct { float x; float y; float z; } V3f;
typedef struct { int a; int b; int c; } I3;
typedef struct { char c; double d; } CD;
typedef struct { float f; int i; } FI;
V3 v3scale(V3 v, double k) { V3 r = { v.x * k, v.y * k, v.z * k }; return r; }
float v3fsum(V3f v) { return v.x + v.y + v.z; }
V3f v3fmake(float a) { V3f v = { a, a * 2, a * 3 }; return v; }
int i3sum(I3 v) { return v.a + v.b + v.c; }
I3 i3make(int a) { I3 v = { a, a + 1, a + 2 }; return v; }
double cdsum(CD v) { return v.c + v.d; }
CD cdmake(char c, double d) { CD v = { c, d }; return v; }
float fisum(FI v) { return v.f + v.i; }
FI fimake(float f, int i) { FI v = { f, i }; return v; }
// many args: registers run out, structs must spill to the stack correctly
double many(Vec2 a, Vec2 b, Vec2 c, Vec2 d, Vec2 e, Vec2 f, Vec2 g, Vec2 h, Vec2 i, Mixed m, long x, Big big) {
    return a.x + b.x + c.x + d.x + e.x + f.x + g.x + h.x + i.x + i.y + m.a + m.b + x + big.id + big.tag;
}
