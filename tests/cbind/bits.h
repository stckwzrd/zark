#include <stdbool.h>
struct flags {
    unsigned a : 3;
    int s : 5;
    bool on : 1;
    unsigned : 2;
    unsigned long long wide : 33;
    int : 0;
    char tag;
    short h : 7;
};
typedef struct { unsigned char lo : 4, hi : 4; } nib_t;
struct outer { struct flags f; int n; };
long long flags_sum(struct flags f);
long long flags_sump(const struct flags* f);
void flags_set(struct flags* f);
struct flags flags_make(void);
int nib_val(nib_t n);
