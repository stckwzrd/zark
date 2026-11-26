# Print the compiler called $1, skipping ccache wrappers.
#
# Distributions ship clang both as a real binary and as a symlink to ccache
# (/usr/lib64/ccache/clang on Fedora, /usr/lib/ccache/clang on Debian). A test
# shim that execs the ccache wrapper makes ccache look up the shim in PATH and
# exec it again, so the shim would loop forever. The tests below exec the
# compiler itself.

# A path is a ccache wrapper when its directory or its resolved target is
# ccache itself (a symlink in /usr/bin also counts).
is_ccache() {
    local p=$1 r
    case "$p" in */ccache|*/ccache/*) return 0 ;; esac
    r=$(readlink -f "$p" 2>/dev/null) || r=$p
    case "$r" in */ccache|*/ccache/*) return 0 ;; esac
    return 1
}

compiler_path() {
    local name=$1 path d old
    path=$(command -v "$name") || return 1
    if ! is_ccache "$path"; then
        printf '%s\n' "$path"
        return 0
    fi
    old=$IFS
    IFS=:
    for d in $PATH; do
        case "$d" in */ccache) continue ;; esac
        if [ -x "$d/$name" ] && ! is_ccache "$d/$name"; then path=$d/$name; break; fi
    done
    IFS=$old
    printf '%s\n' "$path"
}
