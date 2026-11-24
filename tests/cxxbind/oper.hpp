enum class E : unsigned char { A, B };
E operator|(E a, E b);
bool operator!(E a);
unsigned long long operator""_kb(unsigned long long v);
namespace n { int operator+(E a, int b); }
void* operator new(unsigned long n, E e);
int operatorx(int v);
