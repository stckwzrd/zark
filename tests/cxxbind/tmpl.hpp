template<class T> struct Box {
    T v;
    T get() const;
    void set(T x);
};
template struct Box<int>;
extern template struct Box<double>;
template<class T> T twice(T x) { return x; }
template int twice<int>(int);
template<class T> struct Vec {
    T* p;
    int n;
    int size() const;
    T get(int i) const;
};
struct IO { Vec<int> v; Vec<double>* q; };
struct Holder { IO io; Vec<unsigned short> u; };
template<class T, int N> struct Arr {
    T a[N];
    int len() const;
};
struct HasArr { Arr<int, 4> a; };
template<class T> struct Unused { T v; };
template<class T> struct Bad {
    T v;
    void no() { v.nope(); }
    int ok() const;
};
struct UseBad { Bad<int> b; };
