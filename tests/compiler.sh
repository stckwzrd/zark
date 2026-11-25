# Print the compiler called $1, skipping ccache wrappers.
#
# Distributions ship clang both as a real binary and as a symlink to ccache
# (/usr/lib64/ccache/clang on Fedora, /usr/lib/ccache/clang on Debian). A test
# shim that execs the ccache wrapper makes ccache look up the shim in PATH and
# exec it again, so the shim would loop forever. The tests below exec the
# compiler itself.
compiler_path() {
    local name=$1 path d old
    path=$(command -v "$name") || return 1
    case "$path" in
      */ccache/*)
        old=$IFS
        IFS=:
        for d in $PATH; do
            case "$d" in */ccache) continue ;; esac
            if [ -x "$d/$name" ]; then path=$d/$name; break; fi
        done
        IFS=$old ;;
    esac
    printf '%s\n' "$path"
}
