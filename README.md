# ccinit

A flexible command-line initialization tool for running configuration steps interactively. Configure once, initialize anywhere.

## What is ccinit?

`ccinit` is a Zig-based CLI tool that executes a series of configurable initialization steps with interactive prompts. It's perfect for:

- Setting up new projects with consistent tooling
- Running project initialization scripts
- Installing MCP servers for Claude Code
- Automating repetitive setup tasks

Instead of maintaining shell scripts or remembering multiple commands, define your initialization workflow once in `~/.ccinit.json` and run it anywhere.

## Features

- **Interactive prompts**: Simple y/n questions or checkbox-style multi-select
- **Default values**: Pre-configure sensible defaults for quick setup
- **Environment variable expansion**: Use `${HOME}` and `${VAR}` syntax
- **Command substitution**: Use `$(command)` to dynamically generate values
- **Conditional execution**: Skip steps you don't need
- **Multi-select options**: Choose multiple items from a list with an interactive UI

## Installation

### Build from source

```bash
zig build
```

This creates the executable at `zig-out/bin/ccinit`.

### Install globally

```bash
zig build
cp zig-out/bin/ccinit /usr/local/bin/
```

## Configuration

Create a configuration file at `~/.ccinit.json`:

```json
{
  "steps": [
    {
      "name": "Initialize git repository",
      "command": "git",
      "args": ["init"],
      "default": "y"
    },
    {
      "selection": "MCP Servers",
      "command": "claude",
      "args": ["mcp", "add"],
      "options": [
        {
          "name": "Serena",
          "args": ["serena", "--", "uvx", "..."],
          "default": true
        },
        {
          "name": "Zig Docs",
          "args": ["zig-docs", "--", "bunx", "..."],
          "default": false
        }
      ]
    }
  ]
}
```

See [EXAMPLE_CONFIG.json](./EXAMPLE_CONFIG.json) for a complete example.

## Configuration Format

### Step Types

There are two types of steps:

#### 1. Simple Steps (y/n prompts)

```json
{
  "name": "Step description",
  "command": "command-to-run",
  "args": ["arg1", "arg2"],
  "default": "y"
}
```

- `name`: Question to display to the user
- `command`: Command to execute if user answers yes
- `args`: Optional array of arguments
- `default`: Optional default value ("y" or "n")

#### 2. Selection Steps (multi-select checkboxes)

```json
{
  "selection": "Prompt text",
  "command": "base-command",
  "args": ["base", "args"],
  "options": [
    {
      "name": "Option 1",
      "args": ["option-specific", "args"],
      "default": true
    },
    {
      "name": "Option 2",
      "args": ["other-args"],
      "default": false
    }
  ]
}
```

- `selection`: Header text for the selection menu
- `command`: Base command to execute
- `args`: Optional base arguments passed to all selected options
- `options`: Array of selectable options
  - `name`: Display text for the option
  - `args`: Optional arguments appended for this option
  - `default`: Optional initial selection state (true/false)

**Combined arguments**: When an option is selected, the command runs with `args + option.args` concatenated.

### Environment Variables

Use `${VAR}` syntax to expand environment variables:

```json
{
  "command": "${HOME}/scripts/setup.sh"
}
```

### Command Substitution

Use `$(command)` to capture command output:

```json
{
  "args": ["--project", "$(pwd)"]
}
```

## Usage

Run `ccinit` in any directory:

```bash
ccinit
```

The tool will:
1. Read your configuration from `~/.ccinit.json`
2. Present each step interactively
3. Execute commands based on your choices

### Interactive Controls

**Simple prompts:**
- Type `y` or `n` and press Enter
- Or press Enter to accept the default (shown in parentheses)

**Selection menus:**
- Use arrow keys (↑/↓) to navigate
- Press Space to toggle selection
- Press Enter to confirm and execute

## Example Workflow

```bash
$ ccinit
Initialize git repository? (Y/n) y
Initialized empty Git repository in /path/to/project/.git/

Install cc-sessions? (y/n) n

MCP Servers
> [x] Serena
  [ ] Zig Docs

# (Use arrows to navigate, Space to toggle, Enter to confirm)
```

## Requirements

- Zig 0.14.1 or later
- Unix-like environment (Linux, macOS)
  - Windows? I accept pull requests

## License

See [LICENSE](./LICENSE) for details.

## Contributing

Contributions welcome! Please open an issue or pull request.
