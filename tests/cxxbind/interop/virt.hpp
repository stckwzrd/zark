namespace geo {
struct Shape {
    int id;
    Shape();
    virtual ~Shape();
    virtual double area() const = 0;
    virtual const char* name() const;
    int tag() const;
};
struct Circle : Shape {
    double r;
    Circle(double rr);
    ~Circle() override;
    double area() const override;
    const char* name() const override;
};
struct M1 { int a; };
struct M2 { virtual ~M2(); int b; };
struct Mix : M1, M2 { int c; Mix(int aa, int bb, int cc); };
int m2_b(M2* p);
struct VB { int v; virtual ~VB(); };
struct VD : virtual VB { int w; VD(int vv, int ww); };
int vb_v(VB* p);
int circle_live();
}
