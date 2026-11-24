template<class T> struct CBox { T v; };
template struct CBox<int>;
template struct CBox<const int>;
template struct CBox<volatile int>;
struct UseCv { CBox<int> a; CBox<const int> b; CBox<volatile int> c; };
