namespace geo {
struct Shape {
    int id;
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
struct Mix : M1, M2 { int c; };
struct VB { int v; virtual ~VB(); };
struct VD : virtual VB { int w; };
struct Hide : Shape {
    int x;
    double area() const override;
    int f(int a);
};
struct Hide2 : Hide { int f(); };
}
