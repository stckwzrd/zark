#include <vector>
#include <algorithm>
#include <string>
#include <cstdint>
#include <cstdio>
// C++ behind an extern "C" facade
struct Engine { std::vector<double> v; std::string name; };
extern "C" {
  struct Vec3 { double x, y, z; };
  void* engine_new(const char* name) { auto* e = new Engine; e->name = name; return e; }
  void  engine_push(void* e, double x) { static_cast<Engine*>(e)->v.push_back(x); }
  double engine_median(void* e) {
    auto& v = static_cast<Engine*>(e)->v; std::sort(v.begin(), v.end());
    return v.empty() ? 0 : v[v.size() / 2];
  }
  void engine_hello(void* e) { std::printf("[c++] engine '%s' holds %zu values\n", static_cast<Engine*>(e)->name.c_str(), static_cast<Engine*>(e)->v.size()); }
  void engine_free(void* e) { delete static_cast<Engine*>(e); }
  double vec3_dot(const Vec3* a, const Vec3* b) { return a->x*b->x + a->y*b->y + a->z*b->z; }
}
