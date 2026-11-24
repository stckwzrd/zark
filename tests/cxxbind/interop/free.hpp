#include <cstddef>
namespace geo {
int area(int w, int h);
namespace deep {
const char* name();
}
}
int bump(int& x);
int sum_ref(const int& a, const double& b);
int sink(int&& x);
int& cell(std::size_t i);
inline int twice(int x) { return x * 2; }
static int hidden(int x) { return x + 100; }
int apply(int (*f)(int), int x);
int (*pick(int which))(int);
