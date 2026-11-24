enum class Mode : unsigned char { Off, On };
struct Flags { unsigned a : 3; int s : 5; bool on : 1; unsigned : 2; unsigned long long wide : 33; int : 0; char tag; short h : 7; };
struct WithEnum { Mode m : 2; int rest; };
class PB { int hidden : 4; public: int shown : 4; };
struct Nest { struct { int b : 2; } an; int c : 5; };
