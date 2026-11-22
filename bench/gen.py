#!/usr/bin/env python3
"""Generate the same program in Zark and C (N functions with loops, branches, arrays, calls)."""
import sys
N = int(sys.argv[1]) if len(sys.argv) > 1 else 500
v, c = [], ['#include <stdio.h>']
for k in range(N):
    cv = f"        t += f{k-1}(2, s);\n" if k > 0 else ""
    cc = f"    t += f{k-1}(2, s);\n" if k > 0 else ""
    v.append(f"""i64 f{k}(i64 n, i64 s) {{
    auto acc = n * {k} + s;
    auto i = 0;
    while (i < n) {{
        if ((acc & 1) == 0) {{
            acc = acc / 2 + i;
        }} else {{
            acc = acc * 3 + 1;
        }}
        if (acc > 1000000) {{ acc = acc % 1000; }}
        i += 1;
    }}
    const auto arr = [acc, n, s, {k}];
    auto t = 0;
    for (auto x : arr) {{ t += x; }}
    if (n > 0) {{
{cv}    }}
    return t;
}}""")
    c.append(f"""long f{k}(long n, long s) {{
    long acc = n * {k} + s;
    long i = 0;
    while (i < n) {{
        if ((acc & 1) == 0) {{
            acc = acc / 2 + i;
        }} else {{
            acc = acc * 3 + 1;
        }}
        if (acc > 1000000) {{ acc = acc % 1000; }}
        i += 1;
    }}
    long arr[4] = {{acc, n, s, {k}}};
    long t = 0;
    for (int j = 0; j < 4; j++) {{ t += arr[j]; }}
    if (n > 0) {{
{cc}    }}
    return t;
}}""")
v.append(f"""void main() {{
    auto total = 0;
    for (auto r : 0..2000) {{ total += f{N-1}(10, r); }}
    println("total = {{total}}");
}}""")
c.append(f"""int main(void) {{
    long total = 0;
    for (long r = 0; r < 2000; r++) {{ total += f{N-1}(10, r); }}
    printf("total = %ld\\n", total);
    return 0;
}}""")
open("w.zk", "w").write("\n".join(v) + "\n")
open("w.c", "w").write("\n".join(c) + "\n")
