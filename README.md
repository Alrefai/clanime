# clanime

A powerful command-line interface for managing, downloading, and streaming video series using yt-dlp.

## Features

- 📺 **Stream or Download** video series with a single command
- 🤖 **Non-Interactive Mode** for automation, scripting, and CI/CD
- 📋 **Interactive Series Management** with local watchlist storage
- 🎯 **Smart Navigation** using fzf for fuzzy searching and selection
- ⚙️ **Flexible Configuration** via environment variables and config files
- 📊 **Playlist Support** with custom index parsing and modifiers
- 🎨 **Rich UI** with unicode symbols and color-coded output
- 🔧 **Extensible** with custom extractors and format filters
- 💾 **Archive Support** to track downloaded episodes
- 🏷️ **Smart Naming** with customizable output templates
- 🎞️ **Subtitle Management** with ISO 639-1 code formatting

## Installation

### Prerequisites

- macOS (tested on Darwin)
- [Homebrew](https://brew.sh/) package manager

### Quick Install

```bash
git clone https://github.com/Alrefai/clanime.git
cd clanime
./install.sh
```

This will:
1. Install required dependencies via Homebrew
2. Copy `clanime` to `/usr/local/bin/` for global access

### Dependencies

The install script will automatically install these via Homebrew:

- `bash` - Modern bash shell
- `fzf` - Fuzzy finder for interactive selection
- `jq` - JSON processor for data management
- `yt-dlp` - Video downloader (successor to youtube-dl)
- `mpv` - Media player for streaming

## Usage

### Basic Commands

```bash
# Stream a series
clanime stream <URL>
clanime st <URL>

# Download a series
clanime download <URL>
clanime dl <URL>

# Interactive mode (browse saved series)
clanime
```

### Command-Line Options

#### General Options
- `-e, --extractor <name>` - Specify yt-dlp extractor
- `--series <name>` - Override series name
- `--season-template <type>` - Season numbering (single|multi|custom)
- `--parse-index <number>` - Starting index for playlist parsing
- `-y, --non-interactive` - Skip all prompts (automation-friendly)

#### Download Options
- `--base-dir <path>` - Download to specific directory
- `--dir <path>` - Download to directory without series subdirectory
- `--here` - Download to current directory
- `--no-sub-dir` - Don't create series subdirectory

#### Advanced Options
- `--ytd-series` - Use yt-dlp provided series name in template
- `--no-delete` - Don't delete fragmented download files
- `--delete-frag` - Force delete fragmented files
- `--no-iso-sub` - Don't rename subtitles to ISO format
- `--batch-iso-sub` - Batch rename subtitles in download directory

#### yt-dlp Pass-through
- `-- <yt-dlp options>` - Pass additional options directly to yt-dlp
  - `--download-archive <file>` - Archive file for tracking downloads
  - `--autonumber-start <number>` - Starting number for autonumbering
  - `--format <filter>` - Video quality/format selection

### Examples

```bash
# Stream with specific quality
clanime stream "https://example.com/series" -- --format "best[height<=720]"

# Download to specific directory
clanime download "https://example.com/series" --base-dir ~/Downloads/Series

# Use custom series name and season template
clanime dl "https://example.com/series" --series "My Series" --season-template multi

# Download with archive tracking
clanime download "https://example.com/series" -- --download-archive downloaded.txt
```

### Non-Interactive Mode

Perfect for automation, scripting, and CI/CD pipelines. Uses a streamlined execution path that bypasses watchlist and config management.

```bash
# Basic non-interactive download (defaults to download if no sub-command specified)
clanime --non-interactive "https://youtube.com/playlist?list=..." --series "Series Name"

# Explicit download sub-command
clanime download "https://youtube.com/playlist?list=..." --non-interactive --series "Series Name"

# Short flag with custom directory and format
clanime download "https://example.com/series" -y --series "My Series" --dir ~/Downloads --format "best[height<=720]"

# Non-interactive streaming
clanime stream "https://example.com/series" --non-interactive

# Automation example with error handling
if clanime download "$URL" -y --series "$SERIES_NAME" --dir "$DOWNLOAD_DIR"; then
    echo "Download completed successfully"
else
    echo "Download failed with exit code $?"
fi
```

**Features:**
- 🚫 **No Prompts** - Completely silent operation
- ⚡ **Streamlined** - Bypasses watchlist and config management for direct execution
- 📁 **Smart Defaults** - Uses sensible fallbacks (defaults to download mode)
- 🔄 **Auto-Cleanup** - Automatically handles fragmented files
- 🛡️ **Error Handling** - Clear error messages for automation debugging

## Configuration

### Environment Variables

#### Core Settings
- `CLANIME_DEBUG` - Debug mode (1=enhanced errors, 2=verbose trace)
- `CLANIME_DOWNLOAD_DIR` - Default download directory
- `CLANIME_MAKE_SUB_DIR` - Create series subdirectories (1=on, 0=off)
- `CLANIME_NON_INTERACTIVE` - Enable non-interactive mode (0=off, 1=on)
- `CLANIME_NON_INTERACTIVE_FORMAT` - Default format for non-interactive downloads

#### Template Customization
- `CLANIME_SERIES_NAME_SUFFIX` - Text after series name (default: " - ")
- `CLANIME_SERIES_SEASON_PREFIX` - Text before season number
- `CLANIME_SERIES_SEASON_SUFFIX` - Text after season number (default: "E")
- `CLANIME_SERIES_EPISODE_PREFIX` - Text before episode number
- `CLANIME_SERIES_EPISODE_SUFFIX` - Episode number format (default: "02d - ")

#### UI Customization
- `CLANIME_MENU_TOP` - Main menu symbol (default: ❯❯)
- `CLANIME_MENU_NAV` - Navigation symbol (default: ❯)
- `CLANIME_MENU_BACK` - Back option symbol (default: ❮)
- `CLANIME_MENU_END` - End/final option symbol (default: ❖)

#### Advanced Options
- `CLANIME_DEFAULT_SEASON_NO` - Default season template (single|multi|custom)
- `CLANIME_YTD_SERIES_NAME` - Use yt-dlp series name (1=on, 0=off)
- `CLANIME_PARSE_INDEX_START` - Starting index for playlist parsing (default: 1)
- `CLANIME_ISO_SUB` - Rename subtitles to ISO format (1=on, 0=off)
- `CLANIME_DELETE_FRAG` - Auto-delete fragmented files (1=on, 0=off)

#### Custom Format Filters
```bash
# Define custom format presets
export CLANIME_FORMAT_HD_NAME="High Definition"
export CLANIME_FORMAT_HD_FILTER="best[height<=1080]"

export CLANIME_FORMAT_MOBILE_NAME="Mobile Quality"
export CLANIME_FORMAT_MOBILE_FILTER="worst[ext=mp4]"
```

#### fzf Customization
```bash
# Customize fzf behavior
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
```

### Configuration Files

- **User Config**: `~/.config/clanime/` - Series configurations and settings
- **Cache**: `~/.cache/clanime/` - Playlist indexes and temporary data
- **Watchlist**: `~/.config/clanime/list.json` - Local series database

## Interactive Features

### Main Menu
- **Browse Lists** - Navigate saved series and episodes
- **Manage Lists** - Add, remove, rename, and organize series lists
- **Manage Configurations** - Edit series-specific configurations

### Series Management
- **Add to Watchlist** - Save series URLs for easy access
- **Configuration Wizard** - Interactive setup for download options
- **Playlist Parsing** - Extract episode information with yt-dlp
- **Format Selection** - Choose video quality and format
- **Output Templates** - Customize file naming patterns

### Navigation Controls
- **J/K** - Move down/up in menus
- **Ctrl+A** - Select all items
- **Ctrl+D** - Deselect all items
- **Ctrl+T** - Toggle all selections
- **Esc** - Go back or cancel

## Debug Mode

Enable debug mode for troubleshooting:

```bash
# Basic debug (enhanced error messages with line numbers)
export CLANIME_DEBUG=1
clanime stream "https://example.com/series"

# Verbose debug (full bash trace)
export CLANIME_DEBUG=2
clanime stream "https://example.com/series"
```

## File Locations

- **Config Directory**: `~/.config/clanime/`
- **Cache Directory**: `~/.cache/clanime/`
- **Series Configurations**: `~/.config/clanime/*.conf`
- **Watchlist Database**: `~/.config/clanime/list.json`
- **Playlist Indexes**: `~/.cache/clanime/playlist-index/`
- **List Backups**: `~/.cache/clanime/list-backup/`

## Troubleshooting

### Common Issues

1. **"youtube-dl not found"** - Make sure yt-dlp is installed via Homebrew
2. **Permission errors** - Check write permissions for download directory
3. **Network issues** - Verify internet connection and URL accessibility
4. **Format errors** - Try different format filters or let yt-dlp auto-select

### Getting Help

- Run with debug mode: `CLANIME_DEBUG=1 clanime ...`
- Check yt-dlp compatibility: `yt-dlp --version`
- Verify dependencies: `brew bundle check`
- Clear cache: `rm -rf ~/.cache/clanime/`

### Logs and Debugging

Debug information includes:
- Function call traces
- Line numbers for errors
- yt-dlp command execution
- Configuration file parsing
- Network request details

## Development

See [STYLE_GUIDE.md](STYLE_GUIDE.md) for coding conventions.


### Contributing

1. Fork the repository
2. Create a feature branch
3. Follow the style guide
4. Run shellcheck: `shellcheck clanime.sh`
5. Test with debug mode
6. Submit a pull request to `develop` branch

## License

This project is open source. See the repository for license details.

## Related Projects

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) - Video downloader
- [fzf](https://github.com/junegunn/fzf) - Fuzzy finder
- [mpv](https://mpv.io/) - Media player