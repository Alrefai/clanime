# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

clanime is a bash CLI tool for managing, downloading, and streaming anime/video series using yt-dlp (formerly youtube-dl).

## Development Commands

### Linting
```bash
shellcheck clanime.sh
```

### Debug Mode
```bash
# Enable enhanced error messages with line numbers
export CLANIME_DEBUG=1

# Enable verbose trace mode (set -xv)
export CLANIME_DEBUG=2
```

### Installation
```bash
# Install dependencies
brew bundle

# Install clanime globally
./install.sh
```

### Testing
```bash
# Run the script directly
./clanime.sh

# Test specific commands
./clanime.sh stream [URL]
./clanime.sh download [URL]
```

### Non-Interactive Mode
```bash
# Download without any prompts (automation-friendly)
./clanime.sh download [URL] --non-interactive --series "Series Name"
./clanime.sh download [URL] -y --series "Series Name" --dir ~/Downloads

# Stream without prompts
./clanime.sh stream [URL] --non-interactive

# With custom format
./clanime.sh download [URL] -y --series "Anime" --format "best[height<=720]"

# Auto-generates config with reliable naming: "Series - 01 - Video Title.mp4"
```

## Architecture Overview

### Core Components

1. **Main Script**: `clanime.sh` (2568 lines)
   - Single-file bash application
   - Modular function design with ~60 functions
   - Uses traps for cleanup and error handling

2. **Data Storage**:
   - User config: `${XDG_CONFIG_HOME:-${HOME}/.config}/clanime/`
   - Series list: `${CONFIG_DIR}/list.json`
   - Cache: `${XDG_CACHE_HOME:-${HOME}/.cache}/clanime/`

3. **Key Dependencies**:
   - `fzf`: Interactive menu selection
   - `jq`: JSON processing for list management
   - `yt-dlp`/`youtube-dl`: Video downloading
   - `mpv`: Video streaming

### Important Functions

- `main()`: Entry point, handles command parsing
- `stream_manager()`: Core streaming logic (clanime.sh:1477)
- `download_manager()`: Core download logic (clanime.sh:1935)
- `series_manager()`: Manages series selection and navigation (clanime.sh:994)
- `play_episode()`: Handles video playback (clanime.sh:1587)
- `download_episode()`: Handles video downloading (clanime.sh:2045)

### Configuration System

Environment variables control behavior:
- `CLANIME_DEBUG`: Debug mode (1 or 2)
- `CLANIME_NON_INTERACTIVE`: Enable non-interactive mode (0 or 1)
- `CLANIME_NON_INTERACTIVE_FORMAT`: Default format for non-interactive downloads
- `CLANIME_FORMAT_<PREFIX>_NAME/FILTER`: Custom format presets
- `CLANIME_DOWNLOAD_DIR`: Default download directory
- `CLANIME_EXTRACTOR`: Default yt-dlp extractor
- `CLANIME_SYMBOLS_*`: Customize menu navigation symbols

## Development Notes

1. **Error Handling**: Uses custom `assert()` function for consistent error reporting
2. **Cleanup**: Trap handlers ensure temp files are cleaned up on exit
3. **Shellcheck**: Code includes shellcheck directives; always run `shellcheck clanime.sh` before committing
4. **Git Branch Strategy**: Feature branches merge to `develop`, not `main`
5. **Commit Style**: Use conventional commits with emojis (feat: 🎸, fix: 🐛, perf: ⚡️, refactor: 💡)
6. **GitHub Workflow**: 
   - **Issues**: High-level status updates, requirements, planning, milestone updates
   - **PRs**: Technical implementation details, code review, commit-specific changes
   - **Cross-reference**: Issues link to PRs for technical details, avoid duplicating content
   - **Comments**: Keep issue comments brief and strategic, detailed technical discussion in PRs

## Common Tasks

### Adding New Features
1. Follow existing function patterns in clanime.sh
2. Use the established error handling with `assert()`
3. Add shellcheck directives if needed
4. Test with both `CLANIME_DEBUG=1` and `CLANIME_DEBUG=2`

### Debugging Issues
1. Enable debug mode: `export CLANIME_DEBUG=2`
2. Check temp files in `/tmp/clanime-*`
3. Verify JSON structure in `~/.config/clanime/list.json`
4. Test yt-dlp commands directly for download issues

### Updating Dependencies
The project uses `youtube-dl` in Brewfile but likely needs `yt-dlp`. To update:
```bash
brew uninstall youtube-dl
brew install yt-dlp
# Update Brewfile to reflect this change
```