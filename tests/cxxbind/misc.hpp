extern "C" constexpr int cx(int x) { return x + 1; }
extern "C" consteval int cv(int x) { return x; }
extern "C" int other(int);
int g(int);
namespace a { extern "C" long g(long); }
void pa(int a1, int);
void pb(int, int a0, int a0_);
int&& rref();
int (&&rarr())[4];
