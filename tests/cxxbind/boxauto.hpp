template<class T, auto N> struct AA { T a[N]; };
template<class T, unsigned N> struct UA { T a[N]; };
template struct AA<int, 4>;
template struct AA<int, 4u>;
template struct UA<int, 4>;
struct Use { AA<int, 4> a; UA<int, 4> b; UA<int, 4u> c; };
UA<int, 4> mk();
