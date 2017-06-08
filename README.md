# Memoize

Memoize captures and replays outputs of slow (or otherwise expensive)
commands.


## Example

To capture stdout, stderr, and the return code, just prepend the line with
memoize:

    memoize bash -c 'sleep 3; echo moo'

To replay them, just re-run the same command:

    memoize bash -c 'sleep 3; echo moo'

To clear the cache, add the `-d` flag before anything else:

    memoize -d bash -c 'sleep 3; echo moo'


## Technical details

The cache is keyed on the sha1 of echo "$*" of the line, so there's no logic
to try to understand anything. Shell lexing will ignore whitespace between
arguments, but that's it.

The results are kept in files named _key_.rc, _key_.out, and _key_.err in
`$XDG_CACHE_HOME/memoize`, or if `XDG_CACHE_HOME` is not set
`~/.cache/memoize`.

It's ok to remove empty files in the cache.
