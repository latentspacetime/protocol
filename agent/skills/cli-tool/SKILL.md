---
name: cli-tool
description: Build a focused single-file Python command-line utility with uv, a clear terminal interface, and deterministic error handling. Use for small terminal tools and automation scripts.
---

# CLI Tool

Build the smallest complete command-line tool that satisfies the request.

## Contract

- Use Python 3.11 or newer.
- Keep a genuinely small tool in one file.
- Declare dependencies in an inline `uv` script header.
- Use `argparse` unless subcommands or a large option surface justify another
  parser.
- Send normal output to stdout and diagnostics to stderr.
- Return zero only when the requested operation completed successfully.
- Add explicit timeouts to network and subprocess boundaries.
- Never print credentials or full sensitive payloads.

## Interface

- Provide `--help` with examples and meaningful defaults.
- Validate user input before side effects.
- Use color only when stdout is a terminal; honor `NO_COLOR`.
- Keep progress indicators on stderr so stdout remains pipeable.
- Handle `Ctrl-C` without a traceback.

## Verification

Run the script through `uv run`, exercise help, success, invalid input, and one
real failure path. If behavior is non-trivial, add tests beside the script only
when the surrounding repository has an established test layout.
