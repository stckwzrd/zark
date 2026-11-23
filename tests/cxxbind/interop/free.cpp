#include "free.hpp"
namespace geo {
int area(int w, int h) { return w * h; }
namespace deep {
const char* name() { return "deep"; }
}
}
int bump(int& x) { x += 1; return x; }
int sum_ref(const int& a, const double& b) { return a + (int)b; }
int sink(int&& x) { int y = x; x = 0; return y * 3; }
static int cells[4] = {1, 2, 3, 4};
int& cell(std::size_t i) { return cells[i]; }
static int neg(int x) { return -x; }
static int sq(int x) { return x * x; }
int apply(int (*f)(int), int x) { return f(x); }
int (*pick(int which))(int) { return which ? sq : neg; }
