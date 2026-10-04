# newcomer: transcript of the real Claude Code session

**User:** <command-message>vbw:vibe</command-message>
<command-name>/vbw:vibe</command-name>
<command-args>I want to build a small greeting tool. One small milestone.</command-args>

**VBW:** I set up VBW here (`.vbw/` and the status line). Next is a short interview, because VBW asks it once at the start of a project.

**VBW asks:**
- How much software have you built? (options: never / small scripts or no-code / professionally / senior engineer)

**User answers:** Your questions have been answered: "How much software have you built?"="never". You can now continue with these answers in mind.

**VBW asks:**
- How should I explain things? (options: plain words / plain with technical terms explained / technical and brief)

**User answers:** Your questions have been answered: "How should I explain things?"="plain words". You can now continue with these answers in mind.

**VBW asks:**
- How involved do you want to be in technical decisions? (options: decide and tell me / options with a recommendation / I make the calls)

**User answers:** Your questions have been answered: "How involved do you want to be in technical decisions?"="decide and tell me". You can now continue with these answers in mind.

**VBW asks:**
- What kind of greeting tool do you have in mind, and who will use it? (For example: a small program where you type a name and it says hello.) (options: Type a name, get a greeting / A simple web page / Time-aware greeting)

**User:** [Request interrupted by user for tool use]

**User:** a script greet.sh: ./greet.sh Ana prints Hello, Ana! and ./greet.sh alone prints Hello, world!. It is for my grandmother, who is learning English.

**VBW asks:**
- Where should I keep your answers about how you like me to work (your experience, how I explain, how much you decide)? (options: private on this machine (Recommended) / saved in the project)

**User answers:** Your questions have been answered: "Where should I keep your answers about how you like me to work (your experience, how I explain, how much you decide)?"="private on this machine (Recommended)". You can now continue with these answers in mind.

**VBW:** The plan is ready and needs your approval before I change anything.

**What I'll build:** one file, `greet.sh`.
- `./greet.sh Ana` prints `Hello, Ana!` (requirement R1)
- `./greet.sh` with no name prints `Hello, world!` (requirement R2)

**How each one is checked:** two tiny test scripts, `test_named.sh` and `test_default.sh`. Each runs `greet.sh` and compares the output to the exact text above. They fail today because `greet.sh` doesn't exist yet. After the build they should pass.

**Files involved:** `greet.sh`, `test_named.sh` and `test_default.sh`. That's all. No other commands will run on your computer.

**Decision I made for you:** this is small enough to skip the heavy planning step. One builder does the whole job and a quick check follows.

To approve, type `/vbw:approve`. I can't do that part for you.

**User:** <command-message>vbw:approve</command-message>
<command-name>/vbw:approve</command-name>

**VBW:** The approval didn't go through. The two test scripts the contract relies on didn't exist yet, so VBW refused it. I've now written `test_named.sh` and `test_default.sh`. I ran both and they fail, as they should, because `greet.sh` isn't written yet.

Please type `/vbw:approve` once more. I can't approve for you.

**User:** <command-message>vbw:approve</command-message>
<command-name>/vbw:approve</command-name>

**VBW:** The contract is approved, and the build is running in the background. One builder is writing `greet.sh` now. I'll carry on when it finishes.

**VBW asks:**
- The greeting script is built and both checks pass. Do you want to ship this milestone (mark it finished)? (options: Yes, ship it / Not yet)

**User answers:** Your questions have been answered: "The greeting script is built and both checks pass. Do you want to ship this milestone (mark it finished)?"="Yes, ship it". You can now continue with these answers in mind.

**VBW:** Milestone M1, "Greeting script", is shipped. `greet.sh` is in the project folder.

I ran it myself:
- `./greet.sh Ana` prints `Hello, Ana!`
- `./greet.sh` with no name prints `Hello, world!`

Both automatic checks pass. I couldn't check the one thing only you can judge, which is whether your grandmother finds it easy to use.

I made two decisions for you, as you asked. I used VBW's fast path, with one builder and a quick check, because the job was so small. I also kept your answers about how you like to work private on this machine. `/vbw:profile` changes either.

