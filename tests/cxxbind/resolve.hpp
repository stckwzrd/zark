namespace a {
typedef short Id;
Id first(Id x);
}
namespace b {
typedef long Id;
Id first(Id x);
a::Id cross(Id x);
}
struct Holder {
    typedef unsigned Size;
};
struct Kid : public Holder {};
Holder::Size size_of(Holder::Size s);
Kid::Size kid_size(Kid::Size s);
using Real = double;
namespace b {
Real half(Real r);
namespace c {
Id inner(Id x, ::a::Id y);
}
}
enum class Mode : unsigned char { Off, On };
Mode toggle(Mode m, const Mode& prev);
