namespace esc {
struct V { int x = 1; int y = 2; };
typedef const int* IP;
IP firstip(const V& v);
using IR = const int&;
IR firstr(const V& v);
const int* firstp(const V& v);
int sum(const V& v);
class Iter {
    const int* p;
public:
    Iter(const int* q);
    int n;
};
Iter mkit(const V& v);
struct RR {
    const int& r;
    int n;
};
RR mkrr(const V& v);
struct Pub {
    const int* p;
    int n;
};
Pub mkpub(const V& v);
struct Inh : private Iter {
    int m;
};
Inh mkinh(const V& v);
struct Plain {
    int a;
    int b;
};
Plain mkplain(const V& v);
}
