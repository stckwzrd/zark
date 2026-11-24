#include <string>
#include <string_view>
#include <vector>
#include <memory>
#include <map>
namespace st {
struct Thing {
    int v;
    Thing(int k);
    ~Thing();
    int get() const;
};
struct StrField {
    int a;
    std::string s;
    std::vector<int> v;
    int z;
};
std::string echo(std::string s);
const std::string& hello();
std::string_view view(std::string_view v);
int sum(const std::vector<int>& v);
std::vector<int> make(int n);
std::unique_ptr<Thing> make_thing(int k);
int take(std::unique_ptr<Thing> p);
int map_size(std::map<int, int> m);
std::string& bad_ref();
}