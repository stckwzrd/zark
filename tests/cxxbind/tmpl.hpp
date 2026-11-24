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
template<class T> struct Res;
Res<int> parse();
int use(Res<int>);
Res<int>* ptr();
template<class T, int N> struct Num { int n; };
struct Neg { Num<int, -4> a; };
enum Kind { KA, KB };
template<class T, Kind K> struct ByEnum { int n; T v; };
struct HasEnum { ByEnum<int, KB> a; };

template<class T> struct VStore {
    T* p;
    int n;
    VStore(const VStore& o) { n = o.n; p = (T*)malloc(n * sizeof(T)); }
    VStore& operator=(const VStore& o) { n = o.n; p = (T*)malloc(n * sizeof(T)); return *this; }
    ~VStore() { }
};
struct Item;
struct CopyBad { int a; VStore<Item> v; };
