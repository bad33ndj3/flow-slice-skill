---
name: ast-grep
description: Use to structurally search code using AST patterns. Prefer over regex or grep for finding function calls, struct definitions, and implementations across any codebase.
---

# AST-Grep

`ast-grep` is a fast structural code search tool built on Tree-sitter. It allows agents to search the Abstract Syntax Tree using code patterns instead of fragile regex or plain text matching.

## Basic Usage

Use the `--pattern` (or `-p`) flag to specify structural patterns. The language flag `-l` ensures the correct parser is used.

### Pattern Syntax
- Use `$NAME` (a variable name starting with `$`) to match exactly one AST node (e.g., an identifier, a type, or a single argument).
- Use `$$$` to match multiple statements, arguments, or completely ignore the inner contents of a block.

### Examples (Go)
- **Find all main functions**: `ast-grep -p 'func main() { $$$ }' -l go`
- **Find struct definitions**: `ast-grep -p 'type $NAME struct { $$$ }' -l go`
- **Find method declarations**: `ast-grep -p 'func ($REC *$STRUCT) $NAME($ARGS) $RET { $$$ }' -l go`
- **Find specific function calls**: `ast-grep -p 'outbound.NewRepository($$$)' -l go`
- **Find error handling**: `ast-grep -p 'if err != nil { $$$ }' -l go`

## Rules
- When tracing a codebase, prefer `ast-grep` over `grep` or `findReferences` because it is fast, highly accurate, and doesn't require an active language server (LSP).
- If the `ast-grep` CLI tool is unavailable on the machine, prompt the user to install it (e.g., `task install:ast-grep` or `brew install ast-grep`).
