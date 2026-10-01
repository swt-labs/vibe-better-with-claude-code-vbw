# greet

## Goals

A command-line greeter, `./greet.sh`, written in POSIX sh with no dependencies.

## Requirements

- R1 [auto] `./greet.sh Ana` prints exactly `Hello, Ana!` and exits 0
- R2 [auto] `./greet.sh` with no name prints exactly `Hello, world!` and exits 0
- R3 [auto] `./greet.sh --shout Ana` prints exactly `HELLO, ANA!` and exits 0
- R4 [auto] `./greet.sh --bogus` prints a usage line to stderr and exits 2
