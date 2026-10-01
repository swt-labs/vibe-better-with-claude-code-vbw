# textkit

## Goals

Three small, independent text tools, each its own POSIX sh script reading stdin.

## Constraints

Each tool is a separate file and does not depend on the others.

## Requirements

- R1 [auto] `./upper.sh` prints its standard input converted to upper case
- R2 [auto] `./words.sh` prints the number of words on its standard input, as a bare integer
- R3 [auto] `./rev.sh` prints each line of its standard input with its characters reversed
