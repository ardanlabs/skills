# skills

A collection of AI skills for development work, primarily Go. Compatible with Claude Code and other agents that read the `.agents/skills` convention.

## Agent instructions

| File                     | Purpose                                                                                                    |
|--------------------------|------------------------------------------------------------------------------------------------------------|
| [AGENTS.md](AGENTS.md)   | The agent's identity, working style, git policy, mandatory-skill triggers, and layer-conversion reference. |
| [CLAUDE.md](CLAUDE.md)   | Claude Code entry point — points at `AGENTS.md`.                                                           |

## Skills

| Skill                                                                            | Purpose                                                                                                                                 |
|----------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| [use-modern-go](.agents/skills/use-modern-go/SKILL.md)                           | Apply modern Go syntax based on the project's Go version.                                                                               |
| [layered-architecture-types](.agents/skills/layered-architecture-types/SKILL.md) | Enforce primitives-at-edges / strong-types-in-Business layering and the toBus/fromBusResponse/toDB converter pattern.                   |
| [business-layer-extensions](.agents/skills/business-layer-extensions/SKILL.md)   | Add cross-cutting concerns (OTEL, logging, metrics) via the `ExtBusiness`/`Extension` decorator seam.                                   |
| [branching-logic-flow](.agents/skills/branching-logic-flow/SKILL.md)             | Prefer defaulting and naked switches over if/else chains for shallow branching.                                                         |
| [review-pr](.agents/skills/review-pr/SKILL.md)                                   | Read-only PR review lenses for correctness, error visibility, comments, tests, contracts, and simplification across all repo languages. |

## Claude Code settings

Example Claude Code configuration, split into global (user-level) and project-level.

| File                                                                                                | Purpose                                                                                             |
|-----------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| [global/.claude/settings.json](claude/global/.claude/settings.json)                                 | User settings: permission allow/deny lists, model, plugins, Go-version SessionStart hook.           |
| [global/claude.json](claude/global/claude.json)                                                     | MCP servers (`gopls`, `goland`).                                                                    |
| [global/statusline.sh](claude/global/statusline.sh)                                                 | Powerline statusline: model, dir, git state, context/cost/edits.                                    |
| [project/.claude/settings.json](claude/project/.claude/settings.json)                               | Shared project settings: git/gh permissions, git-policy PreToolUse hook, SessionStart instructions. |
| [project/.claude/settings.local.json](claude/project/.claude/settings.local.json)                   | Local per-machine permission grants (example).                                                      |
| [project/.claude/hooks/git-policy-reminder.py](claude/project/.claude/hooks/git-policy-reminder.py) | PreToolUse hook reminding the agent of git/GitHub policy before write ops.                          |

## Layout

```
AGENTS.md           # agent identity, policy, and skill triggers
CLAUDE.md           # Claude Code entry point -> AGENTS.md
.agents/skills/     # canonical skill files
.claude/skills      # symlink -> ../.agents/skills
claude/global/      # example user-level Claude Code config
claude/project/     # example project-level Claude Code config
```

`.claude/skills` is a symlink so Claude Code and `.agents`-aware tools share one source.

## Windows setup

> [!IMPORTANT]
> The `.claude/skills` symlink requires git symlink support on Windows. Without it, git checks out the link as a plain text file and skills fail to load.
>
> Enable it **before cloning**:
> ```
> git config --global core.symlinks true
> ```
> Creating the symlink also needs OS permission to do so — **either** run git in
> an elevated (admin) shell, **or** enable Windows Developer Mode
> (Settings → Privacy & security → For developers).
>
> If a clone already checked out `.claude/skills` as a text file:
> ```
> git config core.symlinks true
> git checkout -- .claude/skills
> ```
