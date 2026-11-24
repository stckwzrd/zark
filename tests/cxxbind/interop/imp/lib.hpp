#pragma once
#include <string>
namespace m {
constexpr int magic = 42;
int add(int a, int b);
namespace text {
int width(int n);
}
}
int twice(int x);
int missing(int x);
inline int digits(int n) { return (int)std::to_string(n).size(); }
#ifdef __STRICT_ANSI__
constexpr int strict = 1;
#endif
