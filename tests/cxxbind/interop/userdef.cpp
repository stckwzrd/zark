#include "userdef.hpp"

B::B() { y = 9; }
Own::~Own() {}
Many::Many(int v) { m = v; }
int cpp_d() { D d; return d.y * 100 + d.z; }
int cpp_e() { E2 e; return e.b.y * 100 + e.w; }
int cpp_f() { F f; return f.y * 10000 + f.z * 100 + f.q; }
int cpp_g() { G g; return g.b.y * 10000 + g.w * 100 + g.g; }
int cpp_own() { Own o; return o.y * 100 + o.k; }
