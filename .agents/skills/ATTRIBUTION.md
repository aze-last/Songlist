# Third-Party Skill Attribution

This kit vendors select skills from external open-source projects. Attribution and
provenance are recorded here so every copied file stays traceable to its source and
license. When you update a vendored skill, update the pinned commit below in the same change.

## mattpocock/skills

- **Source:** https://github.com/mattpocock/skills
- **Author:** Matt Pocock (https://www.aihero.dev)
- **License:** MIT — Copyright (c) 2026 Matt Pocock
- **Pinned commit:** `a496f5513d4a4cf889bc48e189e579f4b0bdf6aa` (plugin v1.3.2, `main`)
- **Adopted for:** inner engineering discipline referenced by the coder-worker (TDD,
  debugging) and the diff-verifier gate (two-axis review).

### Vendored files

| Local path | Upstream path |
|---|---|
| `skills/tdd/SKILL.md` | `skills/engineering/tdd/SKILL.md` |
| `skills/tdd/tests.md` | `skills/engineering/tdd/tests.md` |
| `skills/tdd/mocking.md` | `skills/engineering/tdd/mocking.md` |
| `skills/diagnosing-bugs/SKILL.md` | `skills/engineering/diagnosing-bugs/SKILL.md` |
| `skills/diagnosing-bugs/scripts/hitl-loop.template.sh` | `skills/engineering/diagnosing-bugs/scripts/hitl-loop.template.sh` |
| `skills/code-review/SKILL.md` | `skills/engineering/code-review/SKILL.md` (forked earlier; provenance retrofitted) |
| `skills/code-review/agents/openai.yaml` | `skills/engineering/code-review/agents/openai.yaml` (harness interface metadata; unused by this kit) |

### Adaptation notes

- `skills/tdd/SKILL.md` and `skills/diagnosing-bugs/SKILL.md` are vendored **verbatim** from
  the pinned commit, except for: (a) a provenance comment after the frontmatter, and (b) a
  **subordination banner** (see below).
- `skills/code-review/SKILL.md` is **not verbatim at the pin.** It is a fork of an *earlier*
  revision of this repo, carrying these known deltas from `a496f551`:
  - local `docs/agents/issue-tracker.md` references replace upstream's generic "the tracker doc"
    / "tell the user to run `/setup-matt-pocock-skills`";
  - local adds `CODING_STANDARDS.md` wording to the standards-sources step;
  - upstream's sentence "Start every sub-agent with a fresh context window." is absent locally.
  - On top of those deltas this kit adds a provenance comment and a *Crew adaptation* callout
    that re-points the "spawn two parallel sub-agents" step at our tool-less verifier gate.
- **Subordination banner** (uniform across all three vendored skills): every vendored SKILL.md
  carries an explicit "inner discipline only" banner stating the kit contract always wins —
  `PLAN.md` is the sole build contract, commands are `rtk`-prefixed, the `diff-scan` gate runs
  first, instinct notes are mandatory, only declared write surfaces are touched, external
  `Skill`/plugin references are **inert**, and execution is non-interactive.
- Upstream skills reference `GLOSSARY.md`, ADRs, and companion skills (`codebase-design`,
  the `Skill` tool) that are **not bundled here**. Those references are inert in this kit unless
  the operator installs the full plugin; the subordination banner instructs agents to ignore them.
- The `code-review` fork additionally ships its upstream `agents/openai.yaml` (harness interface
  metadata targeting other agents). It is attributed in the table above and unused by this kit.
  No other upstream `agents/` subdirectories are vendored.
- Upstream skills assume two harness features we do not provide by default — a Claude-Code-style
  `Skill` tool and parallel sub-agent spawning. Where our pipeline differs, the kit's outer
  contract always wins.

### Full license text

```
MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
