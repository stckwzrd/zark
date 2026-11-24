namespace geo {
enum class Kind : unsigned char { A, B };
struct V { float x = 0; float y = 1.5f; };
struct W { int k = 7; bool on = true; double d = 0.25; V v; int* p = nullptr; long q = 1 + 2; Kind kd = Kind::B; int n = k; };
V add(const V& a, V b);
V* first(V* a);
const V& pick(const V& a, const V& b);
V& ref(V& a);
float len2(const V& v);
W make(int k);
void put(V&& v);
struct NT { NT(const NT&); int n; };
NT copy(NT x);
NT back();
int nt(const NT& x);
int ntp(NT* x);
struct Fwd;
Fwd* getfwd();
int usefwd(Fwd f);
}
extern "C" geo::V cmid(geo::V a, geo::V b);
extern "C" int cptr(geo::V* a);
struct Str { char buf[16]; };
const char* cview(const Str& s);
