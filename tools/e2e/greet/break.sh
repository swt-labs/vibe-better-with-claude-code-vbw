# A regression after shipping: someone "simplifies" the greeter and drops --shout.
printf '#!/bin/sh\ncase "$1" in -*) echo "usage: greet.sh [name]" >&2; exit 2;; esac\necho "Hello, ${1:-world}!"\n' > greet.sh
