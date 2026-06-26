---
name: agents-md
description: Generate, review, and maintain AGENTS.md (or CLAUDE.md) files. Use when creating, auditing, or updating AI agent instruction files for a codebase.
disable-model-invocation: true
---

# AGENTS.md Generator & Reviewer

Generate, review, and maintain AGENTS.md files optimized for AI coding agents.

## Workflow Decision

Determine the task type:

- **Creating a new AGENTS.md?** → Follow "Generate" below
- **Reviewing an existing AGENTS.md?** → Follow "Review" below
- **Updating an existing AGENTS.md?** → Follow "Update" below

---

## Generate

### Phase 1: Analyze the Repository

Before writing anything, analyze and report:

1. **Repository type**: Monorepo, multi-package, or simple project?
2. **Tech stack**: Languages, frameworks, versions, key tools
3. **Major directories** needing their own scoped AGENTS.md
4. **Build system**: Package manager, workspaces, task runner
5. **Testing setup**: Test runner, test locations, coverage tools
6. **Key patterns**: Naming conventions, file organization, existing examples
7. **Existing config**: Extract commands from Makefile, package.json, pyproject.toml, go.mod, etc.

Present findings to the user before generating files. Ask about any gaps.

**Filter ruthlessly:** Most of what you discover does NOT belong in the AGENTS.md. Models can read package.json, explore file trees, and grep codebases on their own. Only carry forward information the model can't discover or consistently gets wrong. When in doubt, leave it out — you can always add it later when a real problem surfaces.

### Phase 2: Reconcile CLAUDE.md and AGENTS.md

Check for existing files at the project root:

- **No CLAUDE.md exists** → Create `CLAUDE.md` with `@AGENTS.md`. Continue to Phase 3.
- **CLAUDE.md exists but is just `@AGENTS.md`** → Already correct. Continue.
- **CLAUDE.md has content, no AGENTS.md exists** → Rename `CLAUDE.md` to `AGENTS.md`, create new `CLAUDE.md` with `@AGENTS.md`. Treat the renamed file as an existing AGENTS.md (switch to Update workflow).
- **CLAUDE.md has content AND AGENTS.md exists** → Ask the user how to proceed (merge, replace, or keep both).

The end state is always: `CLAUDE.md` starts with `@AGENTS.md`, and all agent-agnostic instructions live in `AGENTS.md`. Claude Code-specific instructions (hooks, MCP servers, slash commands, permissions, rules files, etc.) go in `CLAUDE.md` after the `@AGENTS.md` line.

### Phase 3: Write the Root AGENTS.md

Target: **30-60 lines** for the root file. Maximum 300 lines. Instruction-following quality degrades as document length increases — keep it tight. Every line must be universally applicable — no task-specific content in the root.

Include all essential sections:

```markdown
# Project Name

## Stack
[Tech stack with specific versions: "React 18, TypeScript 5.3, Vite 5, Tailwind 3.4"]

## Commands
[Copy-paste ready commands with full flags — build, test, lint, typecheck]

## File-Scoped Commands
[Per-file test/lint/typecheck commands — faster and cheaper than full project builds]
| Task | Command |
|------|---------|
| Typecheck | `pnpm tsc --noEmit path/to/file.ts` |
| Lint | `pnpm eslint path/to/file.ts` |
| Test | `pnpm jest path/to/file.test.ts` |

## Structure
[Directory layout with purposes and access levels (read/write/never modify)]

## Conventions
[Code style via concrete examples referencing actual project files, not prose]
[Naming: functions, classes, constants with real examples from the codebase]

## Git
[Commit format, branching strategy, PR process]

## Boundaries

### Always
[Mandatory practices for every session]

### Ask First
[Actions requiring human approval]

### Never
[Absolute prohibitions — always include "Never commit secrets"]
```

**Key rules:**
- Commands must be copy-paste ready with full syntax
- Prefer file-scoped commands over project-wide builds (per-file is faster and cheaper)
- Reference actual project files (`src/components/Button.tsx`), not hypothetical ones
- Delegate code formatting to tools/hooks, not instructions
- Use `file:line` references instead of embedding code snippets

### Phase 4: Write Scoped Sub-Files

For each major subsystem (app, service, package), create a scoped AGENTS.md:

```markdown
# Package Name

## Purpose
[1-2 lines: what it does, primary tech]

## Commands
[Package-specific: dev, build, test, lint]

## Patterns
[Concrete examples with actual file paths]
- DO: Pattern from `src/components/Button.tsx`
- DON'T: Anti-pattern like `src/legacy/OldButton.tsx`

## Key Files
[Important files to understand the package]

## Gotchas
[Non-obvious pitfalls specific to this package]
```

Sub-files should have MORE detail than the root — they're only loaded when the agent works in that directory.

### Phase 5: Present Output

Present files in order with paths:

```
--- File: AGENTS.md (root) ---
[content]

--- File: apps/web/AGENTS.md ---
[content]
```

### Anti-Patterns

Avoid these in generated AGENTS.md files:

**Writing style:**
- No filler intros ("Welcome to...", "This document explains...")
- No condescending tone ("You should...", "Remember to...", "Make sure to...")
- No prose paragraphs — use headers, bullets, and code blocks
- No explaining "why" — state the rule, not the rationale
- No duplicating skill content — reference the skill file path instead

**Content quality:**
- No hallucinated paths — verify every file reference exists before writing
- No restating model knowledge — frontier models already know best practices (e.g., "use descriptive names", "handle errors", "follow DRY"). Only document project-specific deviations from standard practice.
- No restating discoverable info — if the model can find it by reading package.json, tsconfig, file structure, or grepping the codebase, it doesn't belong in the AGENTS.md. Only include what the model can't find or consistently gets wrong.
- No negative instructions — mentioning something (even "don't use X") biases the model toward it. Remove the topic entirely, or restructure the codebase so the wrong path is harder to reach.
- No placeholder commands — extract real commands or ask the user
- No contradictions between root and sub-files
- No stale versions — extract programmatically from package.json/lockfiles
- No listing installed skills or plugins — agents discover these automatically

**Structure:**
- No embedded code snippets — use `file:line` references (snippets go stale)
- No vague stack descriptions — include specific versions
- No missing boundaries — always include "Never commit secrets"
- No using LLMs as linters — delegate formatting to tools/hooks
- No uncurated /init output — LLM-generated context files perform worse than no file at all. Always manually review and strip auto-generated content down to only what the model can't discover on its own.
- No full project-wide build commands when file-scoped alternatives exist
- No AI attribution rules unless the project explicitly requires them

### Quality Gate

Before presenting, verify:
- `CLAUDE.md` exists with `@AGENTS.md`
- Root file is under 300 lines (ideally 30-60)
- Root links to all sub-files
- Every command is copy-paste ready
- Examples reference real project paths
- No duplication between root and sub-files
- "Never commit secrets" or equivalent is present
- No AI attribution requirement is added unless explicitly requested

---

## Review

### Process

1. Read the existing AGENTS.md (and any sub-files)
2. Evaluate against these criteria:
   - Every line passes the "can the model discover this on its own?" test
   - Commands are copy-paste ready and actually run
   - File references point to paths that exist
   - No section exceeds 20 lines (extract to sub-file)
   - Root file is under 300 lines, ideally 30-60
   - No duplication between root and sub-files
   - No lines compressible 50%+ without losing meaning
   - Boundaries include "never commit secrets" and read-only dirs
   - Destructive/production actions gated behind "ask first"
   - File-scoped commands are preferred over project-wide builds
   - No AI attribution requirement is added unless explicitly requested
   - All anti-patterns from the Generate workflow are absent
3. Propose a rewritten AGENTS.md (or diff) fixing every issue found
4. For each change, include a one-line rationale

### Output Format

Present the proposed rewrite as a complete file (or files), not a report card. Precede it with a short summary of what changed and why.

---

## Update

1. Read the existing AGENTS.md
2. **Subtract first:** Remove lines the model no longer gets wrong, stale references, and anything discoverable from the codebase. With each model generation, agents need less steering — prune aggressively.
3. Identify what changed in the codebase (new packages, changed commands, updated stack)
4. Apply changes while preserving manual content
5. Verify the file still meets the quality gate from the Generate workflow

