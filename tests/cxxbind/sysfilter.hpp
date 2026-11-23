#include <cstdint>
#include <string>
typedef std::int32_t Code;
enum class Level : std::uint8_t { Info, Warn };
constexpr Code Ok = 0;
extern "C" Code check(Level l);
std::string greet(const std::string& who);
