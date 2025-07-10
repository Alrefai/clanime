# clanime Style Guide

This document outlines the coding conventions, patterns, and architectural decisions used in the clanime project.

## 1. Naming Conventions

### 1.1 Functions
- **Pattern**: `camelCase`
- **Examples**: `assertTask`, `makeTEMP`, `downloadOrStream`, `parsePlaylistIndex`
- **Special Prefixes**:
  - `assert*`: UI/output functions (`assertTask`, `assertSuccess`, `assertError`)
  - `make*`: Resource creation functions (`makeTEMP`, `makeFIFO`)
  - `get*`: Data retrieval functions (`getVideoID`, `getConfigFilename`)

### 1.2 Constants and Configuration
- **Pattern**: `UPPER_CASE` with underscores
- **Examples**: `CACHE_DIR`, `TMP_DIR_PREFIX`, `FZF_DEFAULT_OPTS`
- **All constants declared as `readonly`**

### 1.3 Environment Variables
- **Pattern**: `CLANIME_` prefix followed by `UPPER_CASE`
- **Examples**: `CLANIME_DEBUG`, `CLANIME_FORMAT_*`, `CLANIME_DOWNLOAD_DIR`
- **Configuration**: Allow external configuration while providing sensible defaults

### 1.4 Local Variables
- **Pattern**: `camelCase` or `snake_case` depending on context
- **Always declare as local in functions**: `local variableName`

## 2. Code Organization

### 2.1 File Structure
```bash
#!/usr/bin/env bash

#* --{ Debug Mode }-- *#
# Debug setup

#* --{ Shell Script Settings }-- *#
# Shell options and basic configuration

#* --{ User Settings with Environment Variables }-- *#
# Configuration from environment

#* --{ Shell Script Global Variables }-- *#
# Global state variables

# Functions (grouped by category)
# Main execution logic
```

### 2.2 Section Headers
- **Pattern**: `#* --{ Section Name }-- *#`
- **Usage**: Clear separation between logical sections
- **End markers**: `#* End of Section *#`

### 2.3 Function Organization
Functions are grouped by category:
1. **Assertion/UI Functions**: User feedback and output
2. **Utility Functions**: Helper functions for common operations
3. **Core Functionality**: Main application logic
4. **Configuration Management**: Config file handling
5. **Navigation**: Menu and UI navigation
6. **Data Management**: Series and playlist handling

## 3. Error Handling Patterns

### 3.1 Assertion Functions
- **assertTask()**: Progress indication (blue arrow)
- **assertSuccess()**: Success messages (green checkmark)
- **assertMissing()**: Error messages (red X, to stderr)
- **assertWarning()**: Warning messages (yellow WARNING)
- **assertTip()**: Helpful hints (magenta Tip)
- **assertError()**: Fatal errors with optional stack trace

### 3.2 Error Handling Pattern
```bash
if ! command_that_might_fail; then
  assertError 'descriptive error message'
  exit 1
fi
```

### 3.3 Debug Mode Integration
- **Level 1**: Enhanced error messages with line numbers
- **Level 2**: Full bash trace mode (`set -xv`)
- Function trace format: `+(line): function(): `

## 4. Variable Declaration Patterns

### 4.1 Readonly Usage
- **49 readonly declarations** in the codebase
- All constants and configuration should be readonly
- Pattern: `readonly VARIABLE_NAME=${DEFAULT_VALUE}`

### 4.2 Safe Reading Pattern
- **171 instances** of `read -r` for safe input reading
- Always use `read -r` to prevent backslash interpretation
- Pattern: `read -r variable < <(command)`

### 4.3 Variable Initialization
```bash
# Unset variables at start
unset -v VARIABLE_NAME

# Set with defaults
VARIABLE=${ENV_VAR:-default_value}

# Make readonly when appropriate
readonly CONSTANT_VALUE
```

## 5. UI/UX Patterns

### 5.1 Color Scheme
```bash
readonly BOLD_TXT='\e[1m'
readonly GREEN_BOLD_TXT='\e[1;32m'    # Success
readonly RED_BOLD_TXT='\e[1;31m'      # Errors  
readonly BLUE_TXT='\e[34m'            # Tasks/Progress
readonly YELLOW_BOLD_TXT='\e[1;33m'   # Warnings
readonly MAGENTA_BOLD_TXT='\e[1;35m'  # Tips
readonly RESET='\e[0m'                # Reset formatting
```

### 5.2 Unicode Symbols
```bash
readonly MENU_TOP='\u276F\u276F'     # ❯❯ Main menu
readonly MENU_NAV='\u276F'           # ❯ Navigation
readonly MENU_BACK='\u276E'          # ❮ Back option
readonly MENU_END='\u2756'           # ❖ End/final option
readonly MENU_INT='\u2750'           # ❐ Interactive option
```

### 5.3 Navigation Pattern
```bash
until functionName; do 
  assertNav  # Handle back/abort navigation
done
```

## 6. Resource Management

### 6.1 Trap-Based Cleanup
```bash
cleanup() {
  trap - EXIT
  [[ -d ${TMP_DIR} ]] && rm -rf -- "${TMP_DIR}"
  [[ -d ${CACHE_DIR} ]] && find -- "${CACHE_DIR}" -empty -delete
}

trap 'cleanup' EXIT
trap 'cleanup HUP' HUP  
trap 'cleanup TERM' TERM
trap 'cleanup INT' INT
```

### 6.2 Temporary Files
- Use `mktemp` with project-specific prefix
- Always clean up in trap handlers
- Check creation success before proceeding

## 7. Shellcheck Integration

### 7.1 Selective Disabling
- **9 shellcheck disable directives** used judiciously
- Common disables:
  - `SC2016`: Echo literal strings (for templates)
  - `SC2001`: Use of sed (when appropriate)
  - `SC2034`: Unused variables (for optional features)

### 7.2 Best Practices
- Run `shellcheck clanime.sh` before commits
- Document reason for each disable directive
- Prefer fixing code over disabling checks

## 8. Testing and Debugging

### 8.1 Debug Modes
```bash
# Basic debug: Enhanced error messages
export CLANIME_DEBUG=1

# Verbose debug: Full bash tracing
export CLANIME_DEBUG=2
```

### 8.2 Testing Commands
```bash
# Lint the code
shellcheck clanime.sh

# Test basic functionality
./clanime.sh --help

# Test with debug
CLANIME_DEBUG=2 ./clanime.sh
```

## 9. Documentation Standards

### 9.1 Function Documentation
- Complex functions should have inline comments
- Document parameters and return values for non-obvious functions
- Use clear, descriptive function names that indicate purpose

### 9.2 Configuration Documentation
- All environment variables should be documented in README.md
- Include default values and expected formats
- Group related configuration options together

## 10. Git Conventions

### 10.1 Commit Messages
- **Format**: `type: emoji description`
- **Types**: `feat`, `fix`, `refactor`, `perf`, `docs`
- **Emojis**: `🎸` (feat), `🐛` (fix), `💡` (refactor), `⚡️` (perf)
- **Examples**: 
  - `feat: 🎸 add custom format filter presets`
  - `fix: 🐛 handle archiving when list doesn't exist`

### 10.2 Branch Strategy
- Feature branches merge to `develop`
- Conventional commit format required
- Test with shellcheck before committing

## Examples

### Function Template
```bash
functionName() {
  local param1=$1
  local param2=${2:-default}
  
  if ! [[ -f "${param1}" ]]; then
    assertError "file not found: ${param1}"
    return 1
  fi
  
  # Function logic here
  assertSuccess "operation completed successfully"
}
```

### Configuration Pattern
```bash
# User-configurable option with default
readonly OPTION_NAME=${CLANIME_OPTION_NAME:-default_value}

# Validation if needed
if ! [[ ${OPTION_NAME} =~ ^[0-9]+$ ]]; then
  assertError "CLANIME_OPTION_NAME must be a number"
  exit 1
fi
```

This style guide ensures consistency, maintainability, and reliability across the clanime codebase.