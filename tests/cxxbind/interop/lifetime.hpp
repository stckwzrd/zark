namespace life {
struct Counter {
    int id;
    Counter(int k);
    Counter(const Counter& o);
    ~Counter();
    int value() const;
    void set(int v);
    Counter bump(int k) const;
    static Counter make(int k);
    static int alive();
};
void drop(Counter c);
Counter make_one(int k);
int ctors();
int dtors();
}
