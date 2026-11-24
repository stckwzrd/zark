#include "opsuf.hpp"

V operator+(V a, int k) { return V{a.x + k}; }
V operator+(V a, short k) { return V{a.x + k + 1000000}; }
V operator+(V a, long k) { return V{static_cast<int>(a.x + k + 2000000)}; }
V operator+(V a, V b) { return V{a.x + b.x + 3000000}; }
V operator-(V a, int k) { return V{a.x - k}; }
bool operator==(V a, V b) { return a.x == b.x; }
W operator+(W a, W b) { return W{a.x + b.x}; }
W operator*(W a, int k) { return W{a.x * k}; }
W operator*(W a, double k) { return W{static_cast<int>(a.x * k) + 1000}; }
