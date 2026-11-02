# Masks the maintainer's folders in a result file before it is committed (T213):
# every string's checkout path ($root) reads <checkout> and the home folder ($home)
# reads ~. The checkout goes first, as it usually sits under the home folder.
# jq --arg root DIR --arg home "$HOME" -f tools/mask-paths.jq
def mask($p; $as): if $p == "" then . else split($p) | join($as) end;
walk(if type == "string" then mask($root; "<checkout>") | mask($home; "~") else . end)
