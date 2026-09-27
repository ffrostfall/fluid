# Contributing

This project uses Rokit as a toolchain manager.

## Commands

1. Clone down the repository
2. Run `rokit install`
3. **Optional:** If you'd like to test in Roblox, run `lute run build-test-place`, then open the file in studio.
4. Run `lute run dev`

## Styling

Casing:

- snake_case for values (variables, functions, anything which is a Thing)
- UPPER_SNAKE_CASE for constants
- PascalCase for types

Other rules:

- Exported value name must match the file name.

## Codebase Overview

### Structure

- The `instances` subfolder within the `src` directory contains reactive bindings to instances.
- The `reactive` subfolder contains, as you guessed it, the reactive graph 8 all associated primitives.
- The `utils` subfolder contains utilities which don't really fit into either of the two above categories.
