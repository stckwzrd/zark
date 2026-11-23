#include <cstdint>
enum Color { Red, Green = 5, Blue };
enum Sign { Neg = -2, Zero, Pos };
enum Truth { Yes = 2 > 1, No = sizeof(int) < 1 };
enum class Kind : uint8_t { Circle = 1, Square, Tri = 7 };
enum class Mode { Off, On };
enum Big : unsigned long long { Huge = 0xFFFFFFFFFFFFFFFFull };
enum : short { AnonA = -1, AnonB };
namespace geo {
enum class Dir : int8_t { Left = -1, Right = 1 };
enum Flags { FlagA = 1 << 0, FlagB = 1 << 4, FlagAB = FlagA | FlagB };
namespace deep {
enum Level { Low, High = Low + 10 };
}
}
struct Box {
    enum Side { Top, Bottom };
    enum class Fit : unsigned { Fill = 3, Crop };
    int w;
};
typedef enum { TdA, TdB } TdEnum;
