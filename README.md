# Memoize

Memoize captures and replays outputs of slow (or otherwise expensive)
commands.


## Example

To capture stdout, stderr, and the return code, just prepend the line with
memoize:

    memoize bash -c 'sleep 3; echo moo'

To replay them, just re-run the same command:

    memoize bash -c 'sleep 3; echo moo'

To clear the cache for a command, add the `-d` flag before it:

    memoize -d bash -c 'sleep 3; echo moo'

To only replay results younger than some age, use `-t AGE`, where AGE is a
number with an optional unit `s`, `m`, `h` or `d` (default minutes):

    memoize -t 90s bash -c 'sleep 3; echo moo'

Use `--` to end the options if the command itself starts with `-`.

`memoize.sh` is meant to be sourced from any POSIX shell. Run `./test.sh` to
shellcheck it and run the tests under bash, zsh, dash and busybox sh.


## Technical details

The cache is keyed on the sha1 of the arguments, each terminated by a NUL
byte, so there's no logic to try to understand anything. Whitespace between
arguments is ignored by the shell, but argument boundaries count: `a 'b c'`
and `'a b' c` are different keys.

Runs that were killed by a signal (exit code above 128), or where the command
could not be found or run (126, 127), are not cached.

The results are kept in files named _key_.rc, _key_.out, and _key_.err in
`$XDG_CACHE_HOME/memoize`, or if `XDG_CACHE_HOME` is not set
`~/.cache/memoize`. The .rc file holds the exit code and, on its second
line, the capture time in seconds since the epoch, which is what `-t`
compares against.

A run is written to a `_key_.tmp.*` directory first and moved into place
once it's done, so a half-finished run is never replayed. It's ok to remove
empty files in the cache, and any leftover `.tmp.*` directories.
