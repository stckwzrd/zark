namespace esc {
struct V { int x = 1; int y = 2; };
typedef const int* IP;
inline IP firstip(const V& v) { return &v.x; }
using IR = const int&;
inline IR firstr(const V& v) { return v.x; }
inline const int* firstp(const V& v) { return &v.x; }
inline int sum(const V& v) { return v.x + v.y; }
class Iter {
    const int* p;
public:
    Iter(const int* q) : p(q) {}
    const int* at() const { return p; }
    int n = 2;
};
inline Iter mkit(const V& v) { return Iter(&v.x); }
struct RR {
    const int& r;
    int n;
    const int* at() const { return &r; }
};
inline RR mkrr(const V& v) { return RR{v.x, 1}; }
struct Inh : private Iter {
    Inh(const int* q) : Iter(q) {}
    const int* where() const { return at(); }
    int m = 3;
};
inline Inh mkinh(const V& v) { return Inh(&v.x); }
struct Plain {
    int a;
    int b;
};
inline Plain mkplain(const V& v) { return Plain{v.x, v.y}; }
}
