namespace geo {
struct V {
    float x = 0;
    float y = 1.5f;
    V() {}
    V(float a, float b) { x = a; y = b; }
    float len() const;
    void set(float a);
    static int count;
    static V origin();
};
struct NT {
    int n;
    NT(int k);
    ~NT();
    int get() const;
    void set(int k);
    NT plus(int k) const;
    static NT make(int k);
    static int gv;
    void take(const NT& o);
};
int usev(V v, const V& r);
int useref(NT& n);
}
