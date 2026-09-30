#!/bin/sh
# Verify: shellcheck, then the test suite under both bash and zsh.
#
#   ./test.sh            run everything
#   ./test.sh --in SHELL run the suite in the current shell (internal)
set -u
here=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" != --in ]; then
    shellcheck "$here/memoize.sh" "$here/test.sh" || exit 1
    status=0
    for sh in bash zsh; do
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

entries() {
    find "$XDG_CACHE_HOME/memoize" -name '*.rc' | wc -l | tr -d ' '
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

check "args keep boundaries" "$(memoize printf '%s|' 'a b' c)" "a b|c|"
check "boundaries are part of key" "$(memoize printf '%s|' a 'b c')" "a|b c|"
check "empty args survive" "$(memoize printf '[%s]' '' x)" "[][x]"
check "backslashes are part of key" \
    "$(memoize printf '%s' 'a\nb'; memoize printf '%s' 'a
b')" 'a\nba
b'

memoize seq 100000 >/dev/null
check "output complete on return" \
    "$(wc -l <"$XDG_CACHE_HOME/memoize/$(_memoize_key seq 100000).out" | tr -d ' ')" \
    100000

before=$(entries)
memoize no-such-command-xyz 2>/dev/null
check "not-found not cached" "$(entries)" "$before"
memoize sh -c 'kill -TERM $$'
check "signalled not cached" "$(entries)" "$before"

: >"$calls"
memoize counted t >/dev/null 2>&1
memoize -t 5m counted t >/dev/null 2>&1
check "-t fresh replays" "$(ncalls)" 1
touch -d '-10 minutes' "$XDG_CACHE_HOME/memoize/$(_memoize_key counted t).rc"
memoize -t 5m counted t >/dev/null 2>&1
check "-t stale reruns" "$(ncalls)" 2
memoize -t 5 -d counted t
memoize counted t >/dev/null 2>&1
check "-t before -d still deletes" "$(ncalls)" 3

memoize 2>/dev/null
check "no command is usage error" "$?" 2
memoize -t 5x true 2>/dev/null
check "bad age is usage error" "$?" 2
check "-- ends options" "$(memoize -- printf '%s' -d)" "-d"

[ "$failures" -eq 0 ]
