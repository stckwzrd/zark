#include "std.hpp"
namespace st {
static int live = 0;
static std::string hello_storage = "hello";
Thing::Thing(int k) : v(k) { live += 1; }
Thing::~Thing() { live -= 1; }
int Thing::get() const { return v; }
int Thing::alive() { return live; }
std::string echo(std::string s) { return s + "!"; }
const std::string& hello() { return hello_storage; }
std::string_view view(std::string_view v) { return v; }
int sum(const std::vector<int>& v) { int r = 0; for (int x : v) { r += x; } return r; }
std::vector<int> make(int n) { std::vector<int> r; for (int i = 0; i < n; i++) { r.push_back(i); } return r; }
std::unique_ptr<Thing> make_thing(int k) { return std::unique_ptr<Thing>(new Thing(k)); }
int take(std::unique_ptr<Thing> p) { return p->v; }
int map_size(std::map<int, int> m) { return (int)m.size(); }
}
