#include <stdint.h>
// plain C called from Zark
int64_t c_gcd(int64_t a, int64_t b) { while (b) { int64_t t = a % b; a = b; b = t; } return a; }
// C calling back into Zark (exported function)
extern int64_t zark_square(int64_t x);
int64_t c_sum_squares(int64_t n) { int64_t s = 0; for (int64_t i = 1; i <= n; i++) s += zark_square(i); return s; }
