#!/bin/sh
# Verify: the test suite under zsh.
#
#   ./test.sh            run everything
#   ./test.sh --in SHELL run the suite in the current shell (internal)
set -u
here=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" != --in ]; then
    status=0
    for sh in zsh; do
        echo "== $sh"
        "$sh" "$here/test.sh" --in "$sh" || status=1
    done
    exit "$status"
fi

. "$here/memoize.sh"

failures=0
XDG_CACHE_HOME=$(mktemp -d)
export XDG_CACHE_HOME
trap 'rm -rf "$XDG_CACHE_HOME"' EXIT
calls="$XDG_CACHE_HOME/calls"

check() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: expected [$3], got [$2]"
        failures=$((failures + 1))
    fi
}

ncalls() {
    wc -l <"$calls" | tr -d ' '
}

# Writes to stdout and stderr, exits 3, and counts its runs.
counted() {
    echo x >>"$calls"
    echo "out $*"
    echo "err $*" >&2
    return 3
}

: >"$calls"
out=$(memoize counted a 2>/dev/null); rc=$?
check "capture stdout" "$out" "out a"
check "capture rc" "$rc" 3
err=$(memoize counted a 2>&1 >/dev/null); rc=$?
check "replay stderr" "$err" "err a"
check "replay rc" "$rc" 3
check "replay does not rerun" "$(ncalls)" 1

[ "$failures" -eq 0 ]
