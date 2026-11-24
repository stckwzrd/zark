namespace a { struct b_c { int x; }; }
namespace a_b { struct c { int y; }; }
struct Outer {
    struct Inner { int i; };
    Inner in;
    enum K { K0 };
    K k;
    int f();
    static int g();
    Outer();
    ~Outer();
    operator int();
    static int count;
    static const int N = 3;
    template<class T> void t(T);
private:
    struct Hidden { int h; };
    Hidden hid;
};
int useinner(Outer::Inner* p);
namespace r { struct S; }
struct r::S { int s; enum In { I0 }; };
int user(r::S* s);
namespace u { struct T { int t; }; }
using u::T;
int taket(T* t);
typedef u::T UT;
int takeut(UT* x);
struct Self { Self* next; int v; };
struct type { int match; };
namespace { struct Hid { int h; }; }
int useh(Hid* h);
const int& imax(const int& a, const int& b);
struct st { int a; };
int st(struct st* p);
inline namespace v1 { struct In { int i; }; }
int usein(In* p);
struct VA { virtual void f(); };
struct VB2 : virtual VA { int y; };
