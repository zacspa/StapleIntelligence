# iOS CLAUDE.md

## Planning Discipline

Whenever a new plan, feature, or significant work item is discussed or started, keep `Project Documentation/Plans/` up to date:

- **New plan**: Create `Project Documentation/Plans/Backlog/YYYY-MM-DD-short-slug.md` (or `Active/` if starting immediately)
- **Starting work**: Move the plan file from `Backlog/` to `Active/`
- **Completing work**: Move the plan file from `Active/` to `Completed/`
- **Update the index**: Keep `Project Documentation/Plans/README.md` current — one line per plan with status and date

### Plan File Template

```markdown
# Plan: <Title>

**Status**: Backlog | Active | Completed
**Created**: YYYY-MM-DD
**Completed**: YYYY-MM-DD (if done)

## Goal
One sentence.

## Scope
What is in and out of scope.

## Acceptance Criteria
- [ ] ...

## Approach
Steps or notes on implementation.

## Open Questions / Blockers
- ...
```

### File Naming
`YYYY-MM-DD-short-slug.md` — use the date the plan was created.
