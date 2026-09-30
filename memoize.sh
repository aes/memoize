memoize() {
    local cache key exists timecheck
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/memoize"
    if [ ! -d "${cache}" ]; then
        mkdir -p "${cache}"
    fi

    while [ -n "$1" ]; do
        case "$1" in
            "-d")
                shift
                key=$(_memoize_key "$@") || return 1
                rm -f "${cache}/${key}".{rc,out,err}
                return 0
                ;;
            "-t")
                shift
                timecheck="$1"
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done

    key=$(_memoize_key "$@") || return 1
    local base="${cache}/${key}"

    if [ -f "${base}.rc" ]; then
        if [[ "$timecheck" ]]; then
            if find "${base}.rc" -mmin "-$timecheck" | grep . >&/dev/null; then
                exists=1
            else
                exists=
            fi
        else
            exists=1
        fi
    fi

    if [[ $exists ]]; then
        _memoize_replay "$base"
    else
        _memoize_capture "$base" "$@"
    fi
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
