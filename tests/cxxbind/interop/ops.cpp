#include "ops.hpp"
namespace op {
V operator+(V a, V b) { return V(a.x + b.x, a.y + b.y); }
V operator-(V a, V b) { return V(a.x - b.x, a.y - b.y); }
bool operator==(V a, V b) { return a.x == b.x && a.y == b.y; }
bool operator!=(V a, V b) { return !(a == b); }
bool operator<(V a, V b) { return a.x < b.x; }
V operator-(V a) { return V(-a.x, -a.y); }
Box::Box(int k) : n(k) {}
Box::Box(const Box& o) : n(o.n) {}
Box::~Box() {}
int Box::operator[](int i) const { return n + i; }
bool Box::operator==(const Box& o) const { return n == o.n; }
Box::operator bool() const { return n != 0; }
Box& Box::operator+=(int k) { n += k; return *this; }
Box Box::operator++(int) { Box t = *this; n += 1; return t; }
static int lastb = -1;
int with_default(int a, int b) { lastb = b; return a + b; }
int last_default() { return lastb; }
}
