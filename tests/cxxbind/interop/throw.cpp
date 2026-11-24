#include "throw.hpp"
#include <stdexcept>
namespace t {
int boom(int x) {
    if (x > 0) throw std::runtime_error("bad thing");
    return -x;
}
int calm(int x) noexcept { return x + 1; }
}
