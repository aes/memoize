# memoize [-d] [-t AGE] [--] COMMAND [ARG...]
#
# Runs COMMAND, caching its stdout, stderr and exit code. Later runs of the
# same command line replay the cache instead of running it. See README.md.
memoize() {
    local delete='' maxage='' cache key base
    while [ $# -gt 0 ]; do
        case "$1" in
            -d)
                delete=1
                shift
                ;;
            -t)
                if [ $# -lt 2 ]; then
                    _memoize_usage
                    return 2
                fi
                maxage="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "memoize: unknown option: $1" >&2
                _memoize_usage
                return 2
                ;;
            *)
                break
                ;;
        esac
    done
    if [ $# -eq 0 ]; then
        _memoize_usage
        return 2
    fi

    cache=$(_memoize_cache_dir) || return 1
    key=$(_memoize_key "$@") || return 1
    base="${cache}/${key}"

    if [ -n "$delete" ]; then
        rm -f "${base}.rc" "${base}.out" "${base}.err"
    elif _memoize_fresh "$base" "$maxage"; then
        _memoize_replay "$base"
    else
        _memoize_capture "$base" "$@"
    fi
}

_memoize_usage() {
    echo "usage: memoize [-d] [-t AGE] [--] COMMAND [ARG...]" >&2
}

# Prints the cache directory, creating it if needed.
_memoize_cache_dir() {
    local dir="${XDG_CACHE_HOME:-$HOME/.cache}/memoize"
    mkdir -p "$dir" && printf '%s\n' "$dir"
}

# Succeeds if the entry at $1 exists and, when $2 is set, is less than $2
# minutes old.
_memoize_fresh() {
    [ -f "$1.rc" ] || return 1
    [ -n "$2" ] || return 0
    [ -n "$(find "$1.rc" -mmin "-$2")" ]
}

_memoize_replay() {
    local rc
    rc=$(cat "$1.rc") || return 1
    # stdout and stderr are replayed concurrently so a reader consuming both
    # in lockstep can't deadlock. The subshell waits for both before we
    # return, without touching the caller's jobs or printing job notices.
    (
        [ ! -f "$1.out" ] || cat "$1.out" &
        [ ! -f "$1.err" ] || cat "$1.err" >&2
        wait
    )
    return "$rc"
}

# Runs the command into a scratch directory and only moves the result into
# the cache if the run was one worth replaying.
_memoize_capture() {
    local base="$1" tmp rc
    shift
    tmp=$(mktemp -d "${base}.tmp.XXXXXX") || return 1
    _memoize_tee "$tmp" "$@"
    rc=$(cat "$tmp/rc" 2>/dev/null)
    if _memoize_cacheable "$rc"; then
        _memoize_commit "$tmp" "$base"
    fi
    rm -rf "$tmp"
    return "${rc:-1}"
}

# Runs the command with stdout and stderr each teed into $1, and its exit
# code written to $1/rc. Plain pipelines (not >(...)) so both tees have
# finished when this returns. The nesting keeps each redirection of fd 1 on
# its own level; zsh's MULTIOS would otherwise send stdout into both.
_memoize_tee() {
    local tmp="$1"
    shift
    {
        {
            {
                "$@" 3>&-
                printf '%s\n' "$?" >"$tmp/rc"
            } 1>&3
        } 2>&1 | tee "$tmp/err" >&2 3>&-
    } 3>&1 | tee "$tmp/out"
}

# Rejects runs that didn't finish (no rc), were killed by a signal (>128), or
# never started (126: not executable, 127: not found).
_memoize_cacheable() {
    case "$1" in
        '' | 126 | 127) return 1 ;;
    esac
    [ "$1" -le 128 ]
}

# Moves the run in $1 into the cache entry $2. The rc file marks an entry as
# complete, so it goes first and is replaced last.
_memoize_commit() {
    rm -f "$2.rc"
    mv -f "$1/out" "$2.out" &&
        mv -f "$1/err" "$2.err" &&
        mv -f "$1/rc" "$2.rc"
}

# NUL-separating the arguments keeps `a 'b c'` and `'a b' c` apart, and
# printf (unlike zsh's echo) leaves backslashes alone.
_memoize_key() {
    local sum
    sum=$(printf '%s\0' "$@" | sha1sum) || return 1
    printf '%s\n' "${sum%% *}"
}

# Local Variables:
# mode: shell-script
# sh-shell: zsh
# End:
