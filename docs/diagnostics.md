# Diagnostics

## vbw report

```
$ vbw report
### Environment

- VBW 2.0.0
- Darwin 25.5.0
- bash 5.3.20(1)-release

### vbw doctor
...
### Project state

milestone M1 active
requirements: proven 3, unproven 1
plans: done 2
checks: 4
fixes: none
lease: none
evidence: 2026-10-02T02:20:53Z passed=true failing=
profile: balanced
last next: prove
```

`vbw report` prints diagnostic facts for a bug report about VBW (no spec text or code). Paste its output into the issue. It runs from any directory and changes nothing.

It prints:

- **Environment:** the VBW version, the operating system and the bash version.
- **`vbw doctor`:** the result of every check VBW needs, with the fix for anything wrong.
- **Project state** (inside a VBW project): the milestone, and counts of requirements, plans and checks by status. It also prints the fixes with their status and attempts, the run lease, the last proof (time, pass, failing check ids), the profile and the last step `vbw next` chose. An empty list prints `none`.

It never prints the spec's text, requirement text, code, file contents or check output. If `.vbw/record.json` does not parse, it prints `record: corrupt` and none of the content. Outside a git repository, it prints the environment and doctor sections only.

`/vbw:report` runs this command for you.
