# Hop agent guide

Hop is a strict Luau CLI running on Lute and compiling to a native executable.

## Setup and validation

Run these commands before completing a change:

```sh
rokit install
lute run install
lute setup
lute run analyze
lute test
lute run build
```

## Conventions

- Keep production code in `src/` and colocate tests as `*.spec.luau`.
- Preserve strict types and use the aliases declared in `.luaurc`.
- Route every external command through the `CommandRunner` seam in `src/types.luau`.
- Keep every `code` and `agent` invocation in `src/editor.luau`.
- Treat missing Cursor, Claude Code, or local tool data as provider degradation rather than a failure of unrelated commands.
- Never follow symlinks or remove the repository and depth bounds from discovery.
- Do not add machine-specific absolute paths.
- Add a `.changes/` entry for user-facing changes.
