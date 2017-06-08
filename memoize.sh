memoize() {
    local _ cache key
    cache="${XDG_CACHE_HOME:-$HOME/.cache}/memoize"

    if [ "$1" = "-d" ]; then
        shift
        echo -n "$*" | sha1sum | read key _
        rm -f "${cache}/${key}".{rc,out,err}
        return 0
    fi

    echo -n "$*" | sha1sum | read key _
    local base="${cache}/${key}"

    if [ -f "${base}.rc" ]; then
        # replay

        # The reason for forking these off is the (somewhat odd) case where
        # stdout and stderr are consumed in synchrony. It might otherwise
        # block when the reader won't read more from stdout because it expects
        # something on stderr or vice versa.
        ( [ -f "${base}.out" ] && cat "${base}.out" & )
        ( [ -f "${base}.err" ] && cat "${base}.err" 1>&2 & )
        rc=$(cat "${base}.rc")
        return $rc
    else
        # capture
        $* \
             2> >(tee "${base}.err" 1>&2) \
             1> >(tee "${base}.out")

        rc="$?"
        echo "$rc" > "${base}.rc"
        return $rc
    fi
}
