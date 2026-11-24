namespace m {
int ov(int);
int ov(long);
int va(int, ...);
wchar_t wc(wchar_t w);
char8_t c8(char8_t c);
char16_t c16(char16_t c);
char32_t c32(char32_t c);
long double ld(long double x);
__int128 i128(__int128 x);
unsigned __int128 u128();
decltype(nullptr) np();
struct S { int x; };
int cls(S s);
int clsp(S* s);
}
template<class T> int tf(T);
int tf(long);
namespace a_b { int h(); }
namespace a { enum b { B0 }; }
