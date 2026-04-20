# Vercel Project Cleanup Script

A powerful bash script to bulk-delete Vercel projects with filtering, preview, and safety features.

## Features

- 🗑️ **Bulk delete** Vercel projects with one command
- 🔍 **Dry-run mode** to preview without deleting
- 🌐 **Filter by visibility** (public/private GitHub repos)
- 🔄 **API + CLI fallback** for reliability
- 🐛 **Debug mode** for troubleshooting
- 🔐 **Auto-detects** Vercel auth token
- ✅ **Interactive** confirmation before deletion

---

## Quick Start

```bash
# Make executable (first time only)
chmod +x cleanup-vercel.sh

# Preview what would be deleted (safe)
./cleanup-vercel.sh --dry-run

# Actually delete projects
./cleanup-vercel.sh
```

---

## Commands & Options

### Basic Usage

```bash
./cleanup-vercel.sh [OPTIONS]
```

### All Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview mode - shows what would be deleted without actually deleting |
| `--public` | Only target projects linked to **public** GitHub repositories |
| `--private` | Only target projects linked to **private** GitHub repositories |
| `--debug` | Enable verbose debug output for troubleshooting |
| `--use-cli` | Force using Vercel CLI instead of API |
| `--help` | Show help message |
| `--version` | Show script version |

---

## Command Examples

### 1. Preview All Projects (Recommended First Step)

```bash
./cleanup-vercel.sh --dry-run
```

Shows all projects and what would be deleted. **No actual deletion happens.**

Output:
```
━━━ Projects (87 of 87) ━━━

  Legend: 🌐 public  🔒 private  ❓ unknown
  ─────────────────────────────────────────
    1. 🔒 my-project
    2. 🌐 public-project
    3. 🔒 financialretardedtimes ← KEEP
   ...

━━━ DRY RUN SUMMARY ━━━
  Would keep:   1 project(s)
  Would delete: 86 project(s)
```

---

### 2. Delete All Projects (Except Default)

```bash
./cleanup-vercel.sh
```

Deletes all projects except `financialretardedtimes` (the default keep project).

**Flow:**
1. Lists all projects
2. Asks which to keep (press Enter for default)
3. Shows deletion preview
4. Requires typing `yes` to confirm
5. Deletes projects one by one

---

### 3. Delete Only PUBLIC Projects

```bash
./cleanup-vercel.sh --public
```

Only shows and deletes projects linked to **public** GitHub repositories.

**Preview first:**
```bash
./cleanup-vercel.sh --public --dry-run
```

---

### 4. Delete Only PRIVATE Projects

```bash
./cleanup-vercel.sh --private
```

Only shows and deletes projects linked to **private** GitHub repositories.

**Preview first:**
```bash
./cleanup-vercel.sh --private --dry-run
```

---

### 5. Debug Mode (Troubleshooting)

```bash
./cleanup-vercel.sh --debug --dry-run
```

Shows verbose output including:
- API requests and responses
- Token detection paths
- Project visibility detection
- Each step's execution details

Output example:
```
[DEBUG] Checking Vercel CLI installation...
[DEBUG] Vercel CLI found: /usr/local/bin/vercel
[DEBUG] Fetching API page 1...
[DEBUG] HTTP status: 200
[DEBUG] Project: my-project (private)
...
```

---

### 6. Force CLI Mode

```bash
./cleanup-vercel.sh --use-cli --dry-run
```

Skips the API and uses Vercel CLI directly. Useful when:
- API authentication fails
- You want to test CLI mode
- Network issues with API

⚠️ **Note:** CLI mode doesn't provide visibility info, so all projects show as `❓ unknown`.

---

### 7. Combine Options

```bash
# Preview public projects with debug output
./cleanup-vercel.sh --public --debug --dry-run

# Delete private projects using CLI
./cleanup-vercel.sh --private --use-cli

# Full debug deletion of public repos
./cleanup-vercel.sh --public --debug
```

---

## Interactive Prompts

### Choosing Projects to Keep

When the script runs, it asks:

```
Which projects do you want to KEEP?

  Enter names separated by commas, or press Enter for default.
  Default: financialretardedtimes

  Projects to keep: 
```

**Options:**
- Press **Enter** → Keep only the default (`financialretardedtimes`)
- Type project names → `project1, project2, project3`

---

### Deletion Confirmation

Before deleting, you must type `yes`:

```
╔══════════════════════════════════════════════════╗
║  ⚠️  WARNING: This will PERMANENTLY delete        ║
║      86 project(s) and ALL their deployments!    ║
╚══════════════════════════════════════════════════╝

  Type 'yes' to confirm: 
```

---

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                    MAIN FLOW                        │
├─────────────────────────────────────────────────────┤
│  1. Parse arguments (--dry-run, --public, etc.)     │
│  2. Check Vercel CLI & login status                 │
│  3. Find auth token (auto-detect from config)       │
│  4. Detect team/scope                               │
│  5. Fetch projects (API first, CLI fallback)        │
│  6. Filter by visibility (if --public/--private)    │
│  7. Display projects with icons                     │
│  8. Get user input (which to keep)                  │
│  9. Build delete list                               │
│ 10. Confirm & delete (or dry-run summary)           │
└─────────────────────────────────────────────────────┘
```

### Token Detection

The script automatically finds your Vercel token from:

1. `~/Library/Application Support/com.vercel.cli/auth.json`
2. `~/.config/vercel/auth.json`
3. `~/.vercel/auth.json`
4. `~/.local/share/com.vercel.cli/auth.json`

---

## Visibility Icons

| Icon | Meaning |
|------|---------|
| 🌐 | Public GitHub repository |
| 🔒 | Private GitHub repository |
| ❓ | Unknown (no deployments or CLI mode) |

---

## Configuration

### Change Default Keep Project

Edit the script and modify line ~45:

```bash
readonly DEFAULT_KEEP="financialretardedtimes"
```

Change to your project name:

```bash
readonly DEFAULT_KEEP="my-important-project"
```

---

## Requirements

- **Vercel CLI** - Install with `npm install -g vercel`
- **Python 3** - For JSON parsing (pre-installed on macOS)
- **Bash** - Works with macOS default bash
- **Logged in to Vercel** - Run `vercel login` if needed

---

## Error Handling

The script handles common errors:

| Error | Solution |
|-------|----------|
| `Vercel CLI not found` | Run `npm install -g vercel` |
| `Not logged in` | Script will prompt `vercel login` |
| `API request failed` | Automatically falls back to CLI |
| `No auth token found` | Run `vercel login` to create token |

---

## Safety Features

1. **Dry-run by default** - Always preview first with `--dry-run`
2. **Explicit confirmation** - Must type `yes` to delete
3. **Keep list** - Specify projects to never delete
4. **Visibility filter** - Only delete public OR private, not both
5. **Progress display** - See each deletion as it happens

---

## Examples Cheat Sheet

```bash
# First time: Preview everything
./cleanup-vercel.sh --dry-run

# See only public repos
./cleanup-vercel.sh --public --dry-run

# See only private repos  
./cleanup-vercel.sh --private --dry-run

# Debug if something is wrong
./cleanup-vercel.sh --debug --dry-run

# Actually delete all (except default)
./cleanup-vercel.sh

# Delete only public repos
./cleanup-vercel.sh --public

# Delete only private repos
./cleanup-vercel.sh --private

# Show help
./cleanup-vercel.sh --help

# Show version
./cleanup-vercel.sh --version
```

---

## License

MIT - Use freely, modify as needed.
