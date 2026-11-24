namespace op {
struct V {
    float x = 0;
    float y = 0;
    V(float a, float b) { x = a; y = b; }
};
V operator+(V a, V b);
V operator-(V a, V b);
bool operator==(V a, V b);
bool operator!=(V a, V b);
bool operator<(V a, V b);
V operator-(V a);
struct Box {
    int n;
    Box(int k);
    Box(const Box& o);
    ~Box();
    int operator[](int i) const;
    bool operator==(const Box& o) const;
    operator bool() const;
    Box& operator+=(int k);
    Box& operator&=(int k);
    Box& operator|=(int k);
    Box operator++(int);
};
}
namespace op {
struct W { float x; };
W operator+(W a, int k);
W operator+(W a, W b);
}
