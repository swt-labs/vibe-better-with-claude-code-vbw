# Tools: help finding the right ones

After the interview, VBW asks once whether it may look for good tools for your
project. It looks for four kinds:

- **Safety scanners**: programs that check your code and its libraries for
  security problems and leaked passwords.
- **Code-quality tools**: a linter (finds mistakes and sloppy code) and a
  formatter (keeps the code tidy and consistent).
- **Test frameworks**: the tools your tests run on.
- **Community skills**: add-ons for Claude Code that others wrote for your kind of project.

```text
VBW: May I look for the best tools for this project?
You: yes
```

## What yes and no do

- **Yes:** VBW sends Scouts (research agents), one for each kind above, to
  find current, well-regarded options for your project's stack. Each reports
  sources. VBW then shows you a short list of at most 6: what each tool is,
  why it fits, where it comes from and a link.
- **No:** nothing is searched and nothing is installed. VBW carries on as before.

The question is asked once per project. Your answer is stored in the project,
so a new session or a second copy of the project does not ask again.

## Where the picks come from

VBW prefers trusted sources: respected open-source projects. They come first
in the list. A tool from anywhere else can still be proposed, but it shows a
warning in plain words beside it. For each one with a warning you choose to
keep it, drop it or have VBW look further.

## Nothing is installed without your approval

Nothing is installed or downloaded before you approve the list. You can
approve all of it, choose which tools you want, or say "not yet". Declining
installs nothing. If you approve some, VBW installs only the ones you approve.

For each approved tool VBW asks where it goes: **this project** only, or **all
your projects**. Skills install with `npx skills add <skill> -y` (with `-g`
for all your projects); other tools follow their own instructions, into the
place you chose.

If a Scout fails or finds nothing, VBW says so, shows what it did find and
installs nothing for the missing kind.

## Run it again, or check your answer

`/vbw:skills` runs the search again at any time, whatever you answered
before, including "no". Asking there counts as a yes. You can add what to
look for: `/vbw:skills a linter for Python`.

`vbw tools` shows the stored answer:

```text
$ vbw tools
tool search: asked, answer yes (2026-10-05T17:25:37Z)
```

Before you answer, it prints `tool search: not asked yet`. `vbw tools --json`
returns `{asked, answer, at}`. `vbw tools answer yes|no` records an answer
by hand; it does not search or install anything.
