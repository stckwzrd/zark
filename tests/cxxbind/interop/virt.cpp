#include "virt.hpp"
namespace geo {
static int live = 0;
Shape::Shape() : id(11) {}
Shape::~Shape() {}
double Shape::area() const { return 0.0; }
const char* Shape::name() const { return "shape"; }
int Shape::tag() const { return id + 7; }
Circle::Circle(double rr) : r(rr) { live += 1; }
Circle::~Circle() { live -= 1; }
double Circle::area() const { return 3.0 * r * r; }
const char* Circle::name() const { return "circle"; }
M2::~M2() {}
Mix::Mix(int aa, int bb, int cc) { a = aa; b = bb; c = cc; }
int m2_b(M2* p) { return p->b; }
VB::~VB() {}
VD::VD(int vv, int ww) { v = vv; w = ww; }
int vb_v(VB* p) { return p->v; }
int circle_live() { return live; }
}
