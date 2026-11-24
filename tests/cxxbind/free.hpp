#include <cstddef>
namespace geo {
int area(int w, int h);
double scale(double x, float f);
const char* label(int id);
namespace deep {
long depth();
}
}
namespace geo {
int perimeter(int w, int h);
}
int add_ref(const int& a, int& out);
int take_rv(int&& x);
const char*& name_ref();
int& slot(std::size_t i);
inline int twice(int x) { return x * 2; }
static int hidden(int x) { return x + 1; }
int apply(int (*f)(int), int x);
int (*pick(int which))(int);
void reset(int* p) noexcept;
bool flag(bool b);
unsigned long long big(long long x, unsigned short s);
int later(int x = 3);
void gone(int) = delete;
int over(int);
int over(double);
int say(const char* fmt, ...);
int twice_decl(int x);
int twice_decl(int x);
namespace a_b { int f(int x); }
namespace a { namespace b { int f(int x); } }
