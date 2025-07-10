#!/usr/bin/env bash

echo -ne 'Loading... \r'

#* --{ Debug Mode }-- *#
readonly DEBUG=${CLANIME_DEBUG}

if [[ ${DEBUG} -eq 2 ]]; then
  PS4='+(${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  set -xv
fi

#* --{ Shell Script Settings }-- *#

shopt -s extglob

readonly CACHE_DIR=${XDG_CACHE_HOME:-${HOME}/.cache}/clanime
readonly TMP_DIR_PREFIX=${TMPDIR:-/tmp/}clanime.XXXXXXXXXXXXXXXX
readonly CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME}/.config}
readonly CONFIG_DIR=${CONFIG_HOME}/clanime
readonly INDEX_DIR=${CACHE_DIR}/playlist-index
readonly LIST_JSON=${CONFIG_DIR}/list.json
readonly LIST_JSON_BACKUP_DIR=${CACHE_DIR}/list-backup

#* --{ User Settings with Environment Variables }-- *#

# User fzf default options
readonly FZF_DEFAULT_OPTS_ENV=${FZF_DEFAULT_OPTS}

# youtube-dl user config path (optional)
readonly USER_CONFIG=${YTDL_USER_CONFIG:-${CONFIG_HOME}/yt-dlp/config}

# User config directory for extractors (optional)
readonly \
  EXTRACTORS_CONFIG_DIR=${CLANIME_EXTRACTORS_CONFIG_DIR:-${CONFIG_DIR}}

# User options for format filter
readonly -a FORMAT_FILTER=${!CLANIME_FORMAT@}

# Output template options

readonly NAME_SUFFIX=${CLANIME_SERIES_NAME_SUFFIX:- - }
readonly SEASON_PREFIX=${CLANIME_SERIES_SEASON_PREFIX}
readonly SEASON_SUFFIX=${CLANIME_SERIES_SEASON_SUFFIX:-E}
readonly EPISODE_PREFIX=${CLANIME_SERIES_EPISODE_PREFIX}
readonly EPISODE_SUFFIX=${CLANIME_SERIES_EPISODE_SUFFIX:-02d - }

# Navigation symbols

readonly MENU_TOP=${CLANIME_MENU_TOP:-'\u276F\u276F'}
readonly MENU_NAV=${CLANIME_MENU_NAV:-'\u276F'}
readonly MENU_BACK=${CLANIME_MENU_BACK:-'\u276E'}
readonly MENU_END=${CLANIME_MENU_END:-'\u2756'}
readonly MENU_INT=${CLANIME_MENU_INT:-'\u2750'}

#* --{ User Settings with Environment Variables and CLI }-- *#
#! on/off values for options: on=1 | off=0

# Output template option for season number (single | multi | custom)
DEFAULT_SEASON_NO=${CLANIME_DEFAULT_SEASON_NO}

# Use youtube-dl provided series name in filename template (default: off)
YTD_SERIES=${CLANIME_YTD_SERIES_NAME:-0}

# Create a sub-direcotry with series name (default: on)
MAKE_SUB_DIR=${CLANIME_MAKE_SUB_DIR:-1}

# Optional download directory (default: current working direcotry)
DOWNLOAD_DIR=${CLANIME_DOWNLOAD_DIR}

# Optionally specify starting index when parsing a playlist (default: 1)
PARSE_INDEX_START=${CLANIME_PARSE_INDEX_START:-1}

# Rename subtitles to ISO 639-1 code format (default: on)
ISO_SUB=${CLANIME_ISO_SUB:-1}

# Batch rename subtitles in the download directory to ISO 639-1 code format
# (default: off)
BATCH_ISO_SUB=${CLANIME_BATCH_ISO_SUB:-0}

# Automatically delete fragmented files (default: on)
DELETE_FRAG=${CLANIME_DELETE_FRAG:-1}

#* End of Settings *#

#* --{ Shell Script Global Variables }-- *#

unset -v JSON
unset -v ALL_KEYS
unset -v ALL_KEYS_COUNT
unset -v ACTIVE_KEYS
unset -v TMP_DIR
unset -v AUTONUMBER
unset -v ARCHIVE_PATH
unset -v DL_LOG
unset -v EXTRACTOR
unset -v EXTRACTOR_CONFIG
unset -v SERIES
unset -v SERIES_URL
unset -v SERIES_CONFIG
unset -v SUB_COMMAND
unset -v ARGS

export FZF_DEFAULT_OPTS="
  --bind J:down,K:up,ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all \
  ${FZF_DEFAULT_OPTS_ENV} \
  --reverse \
  --ansi \
  --no-multi \
  --height 20% \
  --min-height 15 \
  --border \
  --exit-0 \
  --info 'inline' \
  --select-1
"
readonly FZF_DEFAULT_OPTS

readonly YTD_ERRORS='
  Error in the pull function
  PES packet size mismatch
  Failed to open segment
  Unable to open resource
  Packet corrupt
'

# Supported video file extentions pattern

readonly SUPPORTED_VIDEO_EXT='mp4|mkv|webm|ogg'

# Font styling and colors

readonly BOLD_TXT='\e[1m'
readonly GREEN_BOLD_TXT='\e[1;32m'
readonly RED_BOLD_TXT='\e[1;31m'
readonly BLUE_TXT='\e[34m'
readonly RED_UNDERLINE_TXT='\e[4;31m'
readonly CYAN_TXT='\e[36m'
readonly MAGENTA_BOLD_TXT='\e[1;35m'
readonly REVERSE_COLORS='\e[7m'
readonly YELLOW_BOLD_TXT='\e[1;33m'
readonly RESET='\e[0m'

#* End of Glabal Variables *#

assertTask() {
  echo -e "${BLUE_TXT}==>${RESET} ${BOLD_TXT}$*${RESET}"
}

assertSuccess() {
  local checkMark="${GREEN_BOLD_TXT}\u2714${RESET}"
  echo -e "${checkMark} ${BOLD_TXT}$1${RESET}" "${@:2}"
}

assertMissing() {
  local missingMark="${RED_BOLD_TXT}\u2718${RESET}"
  echo -e "${missingMark} ${BOLD_TXT}$1${RESET}" "${@:2}" >&2
}

assertWarning() {
  echo -e "${YELLOW_BOLD_TXT}WARNING${RESET}${BOLD_TXT}: $*${RESET}"
}

assertTip() {
  echo -e "${MAGENTA_BOLD_TXT}Tip${RESET}${BOLD_TXT}: $*${RESET}"
}

assertError() {
  local functionsTrace=": ${FUNCNAME[*]:1:${#FUNCNAME[*]}-2}"

  if [[ ${DEBUG} -ge 1 ]]; then
    echo -ne "${RED_UNDERLINE_TXT}Error${RESET}" \
      "[${BASH_LINENO[0]}${FUNCNAME[2]:+$functionsTrace}]: " >&2
  else
    echo -ne "${RED_UNDERLINE_TXT}Error${RESET}: " >&2
  fi

  if [[ $# -eq 0 ]]; then
    echo 'something wrong happened!' >&2
  else
    echo "$*" >&2
  fi

  return 1
}

cleanup() {
  trap - EXIT

  # Delete temporary directory
  [[ -d ${TMP_DIR} ]] && rm -rf -- "${TMP_DIR}"

  # Delete empty files in cache directory
  [[ -d ${CACHE_DIR} ]] && find -- "${CACHE_DIR}" -empty -delete

  # Delete empty files in config directory
  [[ -d ${CONFIG_DIR} ]] && find -- "${CONFIG_DIR}" -empty -delete

  # Keep only the last 5 added list backups
  xargs -0 rm -f -- < <(tr '\n' '\0' < <(tail -n +6 <(grep -v '/$' <(
    ls -tp "${LIST_JSON_BACKUP_DIR}/${LIST_JSON##*\/}".*.bak 2>/dev/null
  ))))

  # Keep only the last 20 added playlist index files
  xargs -0 rm -f -- < <(tr '\n' '\0' < <(tail -n +21 <(grep -v '/$' <(
    ls -tp "${INDEX_DIR}"/*.txt 2>/dev/null
  ))))

  if [[ $1 ]]; then
    trap - "$1"
    kill -"$1" -- -$$ &>/dev/null
  fi
}

clearLines() {
  local -a range
  mapfile -t range < <(seq "$1")
  # shellcheck disable=SC2034
  for i in "${range[@]}"; do echo -ne '\e[1A\e[K'; done
}

trimWhiteSpace() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' <(grep '\S' <(echo -e "$1"))
}

assertSelection() {
  fzf "${@:2}" < <(trimWhiteSpace "$1")
}

makeTEMP() {
  if [[ ! $1 ]]; then
    assertError 'unable to create a temporary file!' \
      '[filename prefix is missing]'
  elif ! mktemp -q -- "${TMP_DIR}/$1.XXXXXXXXXXXXXXXX"; then
    assertError 'unable to create a temporary file!'
  fi
}

makeFIFO() {
  local pipe
  read -r pipe < <(makeTEMP 'fifo') || return 1
  [[ -d ${TMP_DIR} ]] && rm -f -- "${pipe}" || assertError || return 1
  mkfifo -m 600 "${pipe}" 2>/dev/null

  if [[ ! -p ${pipe} ]]; then
    assertError 'unable to create a FIFO (named pipe)!'
  else
    echo "${pipe}"
  fi
}

navMenu() {
  until "$@" || if [[ $? -eq 2 ]]; then
    return 1
  else
    false
  fi; do assertNav; done
}

assertNav() {
  local pipe
  read -r pipe < <(makeFIFO) || exit 1

  assertSelection "
    ${MENU_BACK} Back to previous menu
    Abort (esc)
  " --disabled >"${pipe}" &

  local nav
  read -r nav <"${pipe}"

  if [[ ${nav} != *'Back to previous menu' ]]; then
    assertMissing 'Exiting...'
    exit 1
  fi
}

assertTryAgain() {
  local pipe
  read -r pipe < <(makeFIFO) || exit 1

  assertSelection "
    ${1:-...}
    Try again
    Abort (esc)
  " --disabled --header-lines 1 >"${pipe}" &

  local tryAgain
  read -r tryAgain <"${pipe}"

  if [[ ${tryAgain} != 'Try again' ]]; then
    assertMissing 'Exiting...'
    exit 1
  fi
}

safeFilename() {
  local beSafe='
    s/(?!
    (?:COM[0-9]|CON|LPT[0-9]|NUL|PRN|AUX|com[0-9]|con|lpt[0-9]|nul|prn|aux)
    |^[\s\.])
    [\/:*\"?<>|~\\\\]{1,254}/_/g
  '
  perl -pe "${beSafe//[[:space:]]/}"
}

readHeader() {
  echo -e "${REVERSE_COLORS} $1 ${RESET}"
}

readPrompt() {
  local prefix=$1
  local suffix=$2

  local prompt
  IFS= read -r prompt < <(
    echo -e "${CYAN_TXT}Text input ${MAGENTA_BOLD_TXT}->${RESET} ${prefix}"
  )

  local textInput
  IFS= read -erp "${prompt}" -i "${suffix}" textInput

  echo "${textInput}"
}

isPlural() {
  local count
  read -r count < <(wc -l <<<"$1")
  [[ ${count} -gt 1 ]] && echo s
}

isPositiveInteger() {
  [[ $1 == +([0-9]) && (($1 -gt 0)) ]] && echo "$1"
}

confirmModifiers() {
  local indexFile=$1
  local maxItems=$2
  local headerItems=$3
  local -a modifiers=("${@:4}")

  local pipeSelectModifiers
  read -r pipeSelectModifiers < <(makeFIFO) || exit 1

  assertSelection "
    ${MENU_NAV} Select ${headerItems}:
    ${modifiers[*]}
  " -m "${maxItems}" +1 --header-lines 1 >"${pipeSelectModifiers}" &

  local -a playlistModifier
  mapfile playlistModifier <"${pipeSelectModifiers}"
  local modifiersCount=${#playlistModifier[@]}
  [[ ${modifiersCount} -gt 0 ]] || return 2

  if grep -qF 'playlist-items' <<<"${playlistModifier[@]}" 2>/dev/null &&
    grep -qE 'playlist-(start|end)' <<<"${playlistModifier[@]}" \
      2>/dev/null; then
    assertMissing 'Use either --playlist-items or --playlist-(start|end)'
    return 1
  fi

  local pipeConfirmSelection
  read -r pipeConfirmSelection < <(makeFIFO) || exit 1
  local maybePlural
  read -r maybePlural < <([[ ${modifiersCount} -gt 1 ]] && echo s)

  assertSelection "
    ${MENU_END} Playlist modifier${maybePlural}:
    ${playlistModifier[*]}
    Confirm
    Cancel (esc)
  " --header-lines $((modifiersCount + 1)) >"${pipeConfirmSelection}" &

  local confirmSelection
  read -r confirmSelection <"${pipeConfirmSelection}" || return 1

  if [[ ${confirmSelection} == 'Confirm'* ]]; then
    assertSuccess "Playlist modifier${maybePlural}:"
    tee -a "${SERIES_CONFIG}" < <(printf '%s' "${playlistModifier[@]}")
  else
    return 1
  fi
}

playlistSelection() {
  local indexFile=$1

  while true; do
    local pipePlaylist
    read -r pipePlaylist < <(makeFIFO) || exit 1
    local fzfHeader
    read -r fzfHeader < <(
      echo -e "${MENU_TOP} Select one or two items:"
    )

    fzf --exact --no-sort +1 -m 2 --header "${fzfHeader}" <"${indexFile}" \
      >"${pipePlaylist}" &

    local -a playlistItems
    mapfile -t playlistItems < <(awk '{printf "%d\n", $1}' "${pipePlaylist}")
    [[ ${#playlistItems[@]} -gt 0 ]] && break

    local pipeTryAgain
    read -r pipeTryAgain < <(makeFIFO) || exit 1

    assertSelection '
      Continue without modifiers
      Try again
      Abort (esc)
    ' --disabled >"${pipeTryAgain}" &

    local tryAgain
    read -r tryAgain <"${pipeTryAgain}"

    if [[ ${tryAgain} == 'Continue'* ]]; then
      return
    elif [[ ${tryAgain} == 'Try again' ]]; then
      continue
    else
      assertMissing 'Exiting...'
      exit 1
    fi
  done

  local pipePlaylistModifiers
  read -r pipePlaylistModifiers < <(makeFIFO) || exit 1

  awk '
    END{print "--playlist-end "$1}
    NR==1{print "--playlist-start "$1}
  ' <(printf '%s\n' "${playlistItems[@]}") >"${pipePlaylistModifiers}" &

  local -a playlistModifiers
  mapfile playlistModifiers <"${pipePlaylistModifiers}"

  local -a newPlaylistModifiers
  if [[ ${#playlistItems[@]} -eq 1 ]]; then
    newPlaylistModifiers=(
      "${playlistModifiers[@]}" "--playlist-items ${playlistItems[0]}"
    )
    navMenu confirmModifiers "${indexFile}" 1 'a modifier' \
      "${newPlaylistModifiers[@]}" || return 1
  else
    local range
    read -r range < <(
      paste -sd '-' <(printf '%s\n' "${playlistItems[@]}")
    )
    newPlaylistModifiers=("${playlistModifiers[@]}" "--playlist-items ${range}")
    navMenu confirmModifiers "${indexFile}" 2 'one or two modifiers' \
      "${newPlaylistModifiers[@]}" || return 1
  fi
}

outputTemplate() {
  local templateSelection
  if [[ ${DEFAULT_SEASON_NO} ]]; then
    templateSelection=${DEFAULT_SEASON_NO}
  else

    local pipeTemplateSelection
    read -r pipeTemplateSelection < <(makeFIFO) || exit 1

    assertSelection '
      Select season number preset for output template:
      Single season
      Multi seasons
      Custom season
    ' --header-lines 1 >"${pipeTemplateSelection}" &

    read -r templateSelection <"${pipeTemplateSelection}" || return 1
  fi

  local seriesSeasonNumber
  if [[ ${templateSelection} == [Ss]ingle* ]]; then
    seriesSeasonNumber=1
  elif [[ ${templateSelection} == [Mm]ulti* ]]; then
    seriesSeasonNumber='%(season_number)1d'
  elif [[ ${templateSelection} == [Cc]ustom* ]]; then
    readHeader 'Modify season number below (then press [ENTER])'
    read -r seriesSeasonNumber < <(readPrompt '' '0')
    clearLines 2
  fi

  local seriesName
  if [[ ${YTD_SERIES} -ne 1 ]]; then
    seriesName="${SERIES}"
  else
    seriesName='%(series)s'
  fi

  local templateBlocks="
    ${seriesName}${NAME_SUFFIX}
    ${SEASON_PREFIX}${seriesSeasonNumber}${SEASON_SUFFIX}
    ${EPISODE_PREFIX}%(episode_number)${EPISODE_SUFFIX}
    %(episode)s.%(ext)s
  "

  local template
  # shellcheck disable=SC2001
  read -r template < <(
    tr -d '\n' < <(sed 's/^[[:space:]]*//' <<<"${templateBlocks}")
  )

  assertSuccess "Output template was saved to series config:"
  tee -a "${SERIES_CONFIG}" < <(echo "-o \"${template}\"")
}

parsePlaylistIndex() {
  local indexFile=$1

  echo
  assertTask 'Parsing series playlist with youtube-dl...'
  assertWarning \
    'youtube-dl may take several minutes to parse long playlists'

  local concatConf
  read -r concatConf < <(makeTEMP 'config') || exit 1
  cat "${USER_CONFIG}" "${EXTRACTOR_CONFIG}" "${SERIES_CONFIG}" 2>/dev/null \
    >"${concatConf}"
  [[ ${FORMAT} ]] && echo "--format ${FORMAT}" >>"${concatConf}"
  # local -a concatConf
  # mapfile -t concatConf < <(
  #   cat "${USER_CONFIG}" "${EXTRACTOR_CONFIG}" "${SERIES_CONFIG}" 2>/dev/null
  # )
  #
  local format
  read -r format < <(
    sed -E "s/'|\"//g" <(awk '{print $2}' <(tail -n 1 < <(
      grep '^\s*--format ' "${concatConf}"
      # grep '^\s*--format ' <(printf '%s\n' "${concatConf[@]}")
    )))
  )

  if [[ ${format} ]]; then
    assertSuccess 'Format:' "${format}"
  else
    assertSuccess 'Format: no filter'
  fi

  assertSuccess 'Cache file:' "${indexFile/#$HOME/\~}"
  assertSuccess 'Data output:' 'INDEX | SEASON NUMBER | TITLE'

  local pipeIndex
  read -r pipeIndex < <(makeFIFO) || exit 1

  jq -cr --unbuffered '[.playlist_index,.season_number,.title] | join("|")' < <(

    # --config-location <(printf '%s\n' "${concatConf[@]}") \
    yt-dlp "${SERIES_URL}" \
      --config-location "${concatConf}" \
      --dump-json \
      --no-match-filter \
      --ignore-errors \
      --playlist-start "${PARSE_INDEX_START}"

  ) >"${pipeIndex}" &

  tee "${indexFile}" < <(
    awk -F '|' '{printf "%4d | S%-2d| %s\n", $1,$2,$3; fflush()}' "${pipeIndex}"
  )

  if [[ -s ${indexFile} ]]; then
    assertSuccess 'Done with playlist parsing'
    echo
    assertTask 'Resuming previous activity...'
    return
  fi

  assertMissing 'Failed to parse playlist'
  local pipeTryAgain
  read -r pipeTryAgain < <(makeFIFO) || exit 1

  assertSelection '
    Try again
    Skip (esc)
    Abort
  ' --disabled >"${pipeTryAgain}" &

  local tryAgainOrSkip
  read -r tryAgainOrSkip <"${pipeTryAgain}" || return 0

  if [[ ${tryAgainOrSkip} == 'Try'* ]]; then
    return 1
  elif [[ ${tryAgainOrSkip} == 'Abort' ]]; then
    assertMissing 'Exiting...'
    exit 1
  fi
}

playlistFormat() {
  declare -A formatName
  declare -A formatFilter

  local formatFromENV
  for formatFromENV in "${FORMAT_FILTER[@]}"; do
    local presetTemplate=${formatFromENV#CLANIME_FORMAT_}
    local presetPrefix=${presetTemplate%%_*}
    [[ ${formatFromENV} == *'_NAME' ]] &&
      formatName["${presetPrefix}"]=${!formatFromENV}
    [[ ${formatFromENV} == *'_FILTER' ]] &&
      formatFilter["${presetPrefix}"]=${!formatFromENV}
  done

  local formatPresets
  printf -v formatPresets '%s\n' "${formatName[@]}"

  local pipeFormat
  read -r pipeFormat < <(makeFIFO) || exit 1

  assertSelection "
    Select format filter:
    ${formatPresets}
    Custome filter
    No filter (esc)
  " --header-lines 1 >"${pipeFormat}" &

  local filter
  read -r filter <"${pipeFormat}"

  local format
  if [[ ${filter} == 'Custome'* ]]; then
    readHeader 'Type your preferred format filter (then press [ENTER])'
    read -r format < <(readPrompt)
    clearLines 2

  elif [[ ${filter} && ${filter} != 'No filter'* ]]; then
    local preset
    for preset in "${!formatName[@]}"; do
      [[ ${filter} == "${formatName[${preset}]}" ]] &&
        format=${formatFilter[${preset}]}
    done

    if [[ ! ${format} ]]; then
      assertMissing 'Format filter was not found for this preset!'
      return 1
    fi
  else
    assertSuccess 'Format: no filter'
    return
  fi

  assertSuccess 'Format filter was saved to series config:'
  tee -a "${SERIES_CONFIG}" < <(echo "--format '${format}'")
}

customizeConfigFile() {
  local pipeUsePresets
  read -r pipeUsePresets < <(makeFIFO) || exit 1

  assertSelection "
    ${MENU_TOP} Customize series config...
    with presets
    manually (esc)
  " --disabled --header-lines 1 >"${pipeUsePresets}" &

  local useConfigPresets
  read -r useConfigPresets <"${pipeUsePresets}"

  if [[ ${useConfigPresets} != *'presets' ]]; then
    ${EDITOR:-vi} "${SERIES_CONFIG}"

    if [[ -s ${SERIES_CONFIG} ]]; then
      assertSuccess 'Series config was customized manually'
    else
      assertMissing "Config file is empty; it will be discarded!"
    fi

    return
  fi

  local pipeConfigOptions
  read -r pipeConfigOptions < <(makeFIFO) || exit 1

  assertSelection "
    ${MENU_END} Select one or more options:
    --format FORMAT
    --playlist-(start|end) NUMBER; --playlist-items ITEM_SPEC
    --output TEMPLATE
  " --disabled --header-lines 1 -m >"${pipeConfigOptions}" &

  local -a configOptions
  mapfile -t configOptions <"${pipeConfigOptions}"
  [[ ${#configOptions[@]} -gt 0 ]] || return 1

  grep -qF 'format' <<<"${configOptions[@]}" 2>/dev/null && playlistFormat

  createIndexFile() {
    if ! mkdir -p "${INDEX_DIR}" 2>/dev/null; then
      assertError 'unable to create index directory in path:' "${INDEX_DIR}"
      exit 1
    fi

    # Keep only the last 2 added playlist index files of the series
    xargs -0 rm -f -- < <(tr '\n' '\0' < <(tail -n +3 <(grep -v '/$' <(
      ls -tp "${INDEX_DIR}"/*"${SERIES}".txt 2>/dev/null
    ))))

    local indexFileDate
    read -r indexFileDate < <(date '+%Y-%m-%d')
    echo "${INDEX_DIR}/${indexFileDate} - ${SERIES}.txt"
  }

  if grep -qF 'playlist' <<<"${configOptions[@]}" 2>/dev/null; then
    local indexFile

    if compgen -G "${INDEX_DIR}/*${SERIES}*" >/dev/null; then
      local pipeIndexFilePrompt
      read -r pipeIndexFilePrompt < <(makeFIFO) || exit 1

      assertSelection '
        Use existing playlist index (esc)
        Create a new playlist index with youtube-dl
      ' --disabled >"${pipeIndexFilePrompt}" &

      local playlistIndexPrompt
      read -r playlistIndexPrompt <"${pipeIndexFilePrompt}"

      if [[ ${playlistIndexPrompt} == 'Create'* ]]; then
        read -r indexFile < <(createIndexFile) || return 1
        until parsePlaylistIndex "${indexFile}"; do continue; done
      else
        local pipeIndexFile
        read -r pipeIndexFile < <(makeFIFO) || exit 1
        local matchSlashes
        read -r matchSlashes < <(echo "${INDEX_DIR//[!\/]/}")

        # shellcheck disable=SC2016
        fzf < <(find -- "${INDEX_DIR}"/*"${SERIES}"*) \
          --header 'Select a playlist index file:' \
          --tac \
          --delimiter '/' \
          --with-nth $((${#matchSlashes} + 2)).. \
          --preview 'head -n ${FZF_PREVIEW_LINES} <{} 2>/dev/null' \
          >"${pipeIndexFile}" &

        read -r indexFile <"${pipeIndexFile}" || return 1
      fi

    else
      read -r indexFile < <(createIndexFile)
      until parsePlaylistIndex "${indexFile}"; do continue; done
    fi

    if [[ -s ${indexFile} ]]; then
      navMenu playlistSelection "${indexFile}" || return 1
    fi
  fi

  grep -qF 'output' <<<"${configOptions[@]}" 2>/dev/null && outputTemplate

  [[ -s ${SERIES_CONFIG} ]] && ${EDITOR:-vi} "${SERIES_CONFIG}"

  if [[ -s ${SERIES_CONFIG} ]]; then
    assertSuccess 'Config file was saved:' "${SERIES_CONFIG/#$HOME/\~}"
  else
    assertMissing "Config file is empty; it will be discarded!"
  fi
}

getConfigFilename() {
  readHeader \
    'Append text to series title or leave it as is (then press [ENTER])'

  local textInput
  IFS= read -r textInput < <(readPrompt "${SERIES}")
  clearLines 2

  local confFilename
  read -r confFilename < <(safeFilename <<<"${SERIES}${textInput}.conf")

  if [[ -f ${CONFIG_DIR}/${confFilename} ]]; then
    local pipeConflictPrompt
    read -r pipeConflictPrompt < <(makeFIFO) || exit 1
    local fileExistWarn
    read -r fileExistWarn < <(assertWarning 'Filename already exists')

    assertSelection "
      ${fileExistWarn}
      Try a different filename
      Use existing config file
      Abort (esc)
    " --disabled --header-lines 1 >"${pipeConflictPrompt}" &

    local conflictPrompt
    read -r conflictPrompt <"${pipeConflictPrompt}"

    if [[ ${conflictPrompt} == 'Try'* ]]; then
      return 1
    elif [[ ${conflictPrompt} == 'Use'* ]]; then
      echo -n
    else
      assertMissing 'Exiting...'
      exit 1
    fi
  fi

  local pipeConfirmFilename
  read -r pipeConfirmFilename < <(makeFIFO) || exit 1

  assertSelection "
    ${MENU_END} ${confFilename}
    Confirm config filename
    Rename it (esc)
  " --disabled --header-lines 1 >"${pipeConfirmFilename}" &

  local confirmConfFile
  read -r confirmConfFile <"${pipeConfirmFilename}"

  if [[ ${confirmConfFile} == 'Confirm'* ]]; then
    readonly SERIES_CONFIG="${CONFIG_DIR}/${confFilename}"
    assertSuccess 'Series config filename:' "${confFilename}"
  else
    return 1
  fi
}

createConfigFile() {
  until getConfigFilename; do continue; done
  until customizeConfigFile; do assertNav; done
}

findConfig() {
  local series=$1
  local header=$2

  [[ ${header} ]] ||
    read -r header < <(echo -e "${MENU_END} Select a config file:")
  local matchSlashes
  read -r matchSlashes < <(echo "${CONFIG_DIR//[!\/]/}")
  # shellcheck disable=SC2016
  fzf < <(find -- "${CONFIG_DIR}/${series}"*) \
    --header "${header}" \
    --keep-right \
    --no-select-1 \
    --delimiter '/' \
    --with-nth $((${#matchSlashes} + 2)).. \
    --preview 'head -n ${FZF_PREVIEW_LINES} <{} 2>/dev/null'
}

selectConfigFile() {
  local escape=$1

  local pipeSeriesConfig
  read -r pipeSeriesConfig < <(makeFIFO) || exit 1
  findConfig "${SERIES}" >"${pipeSeriesConfig}" &

  read -r SERIES_CONFIG <"${pipeSeriesConfig}" || return 1
  readonly SERIES_CONFIG

  local pipeIsCustom
  read -r pipeIsCustom < <(makeFIFO) || exit 1

  [[ ! ${escape} ]] && local skipOption='Skip customization (esc)'
  # shellcheck disable=SC2016
  assertSelection "
    ${SERIES_CONFIG##*\/}
    ${skipOption}
    Customize this config file
    ${escape:+${escape} (esc)}
  " --header-lines 1 +1 --disabled --preview '
      head -n ${FZF_PREVIEW_LINES} <"'"${SERIES_CONFIG}"'" 2>/dev/null
    ' >"${pipeIsCustom}" &

  local isCustom
  read -r isCustom <"${pipeIsCustom}"

  if [[ ${isCustom} == 'Customize'* ]]; then
    assertSuccess 'Customize config file:' "${SERIES_CONFIG/#$HOME/\~}"
    until customizeConfigFile; do assertNav; done
  else
    if [[ -s ${SERIES_CONFIG} ]]; then
      assertSuccess 'Series config:' "${SERIES_CONFIG/#$HOME/\~}"
    else
      assertMissing "Config file is empty; it will be discarded!"
    fi
  fi
}

handleYtdErrors() {
  local file=$1
  local task=${2:-parse}

  local error403='HTTP Error 403: Forbidden'
  local error404='HTTP Error 404: Not Found'
  local errorURL='Unsupported URL'
  local errorDRM='DRM protected'
  local formatNA='Requested format is not available'

  local lastLine
  read -r lastLine < <(tail -n 1 "${file}")

  # if grep -qF "${error403}" "${file}" 2>/dev/null; then
  if grep -qF "${error403}" <<<"${lastLine}" 2>/dev/null; then
    assertMissing "Unable to ${task} series with youtube-dl! [${error403}]"
    local header
    read -r header < <(
      assertTip 'provide your auth credentials with cookies or other methods'
    )
    assertTryAgain "${header}"
    unset -v header
    clearLines 1
    return 1

  # elif grep -qF "${error404}" "${file}" 2>/dev/null; then
  elif grep -qF "${error404}" <<<"${lastLine}" 2>/dev/null; then
    assertMissing "Unable to ${task} series with youtube-dl! [${error404}]"
    exit 1

  # elif grep -qF "${errorDRM}" "${file}" 2>/dev/null; then
  elif grep -qF "${errorDRM}" <<<"${lastLine}" 2>/dev/null; then
    assertMissing "Unable to ${task} series with youtube-dl! [${errorDRM}]"
    exit 1

  # elif grep -qF "${errorURL}" "${file}" 2>/dev/null; then
  elif grep -qF "${errorURL}" <<<"${lastLine}" 2>/dev/null; then
    assertMissing "Unable to ${task} series with youtube-dl! [${errorURL}]"
    exit 1

  # elif grep -qF "${formatNA}" "${file}" 2>/dev/null; then
  elif grep -qF "${formatNA}" <<<"${lastLine}" 2>/dev/null; then
    return

  # elif grep -qF 'ERROR' "${file}" 2>/dev/null; then
  elif grep -qF 'ERROR' <<<"${lastLine}" 2>/dev/null; then
    if [[ ${task} == 'parse' ]]; then
      assertError 'unhandled youtube-dl error:'
      grep -F 'ERROR' <<<"${lastLine}" >&2
    else
      assertError 'unhandled youtube-dl error'
    fi
    exit 1
  fi
}

preSelectedSeries() {
  local json
  local config
  read -r json < <(makeTEMP 'json') || exit 1
  read -r config < <(makeTEMP 'json') || exit 1
  cat "${USER_CONFIG}" "${EXTRACTOR_CONFIG}" 2>/dev/null >"${config}"

  # --config-location <(
  #   cat "${USER_CONFIG}" "${EXTRACTOR_CONFIG}" 2>/dev/null
  # ) \
  parseSeriesWithYtd() {
    yt-dlp "${SERIES_URL}" \
      --config-location "${config}" \
      --dump-json \
      --max-download 1 \
      --all-formats \
      --no-match-filter \
      --abort-on-error \
      --compat-options abort-on-error \
      --no-warnings &>"${json}"
  }

  until [[ -s ${json} ]]; do
    parseSeriesWithYtd &
    local pid=$!
    waitingFor 'youtube-dl to parse series' "${pid}"
    wait "${pid}" && break

    local exitStatus="$?"
    # cat "${json}"
    # echo "${exitStatus}"
    if [[ ${exitStatus} -eq 101 ]]; then
      break
    else
      if ! handleYtdErrors "${json}"; then
        rm -f -- "${json}"
      else
        assertError
        exit 1
      fi
    fi
  done

  if [[ ! ${SERIES} ]]; then
    local series
    if ! read -r series < <(jq -cr '.series' <"${json}" 2>/dev/null) ||
      [[ ${series} == 'null' ]]; then
      assertMissing 'Series title was not found! Trying playlist name...'

      if ! read -r series < <(jq -cr '.playlist' <"${json}" 2>/dev/null) ||
        [[ ${series} == 'null' ]]; then
        assertMissing 'Playlist name was not found! Trying title name...'

        if ! read -r series < <(jq -cr '.title' <"${json}" 2>/dev/null) ||
          [[ ${series} == 'null' ]]; then
          assertMissing 'Title name was not found!'
          exit 1
        fi
      fi
    fi

    if ! read -r SERIES < <(safeFilename <<<"${series}"); then
      assertMissing 'Unable to prase a safe filename from series title:' \
        "${series}"
      exit 1
    fi

    readonly SERIES
    assertSuccess 'Series:' "${SERIES}"
  fi

  read -r EXTRACTOR < <(jq -cr '.extractor' <"${json}" 2>/dev/null) ||
    assertError || exit 1
  readonly EXTRACTOR
  assertSuccess 'Exractor:' "${EXTRACTOR}"

  if [[ ! ${EXTRACTOR_CONFIG} ]]; then
    local extractor
    read -r extractor < <(safeFilename <<<"${EXTRACTOR%\:*}")
    local extractorConfFile=${EXTRACTORS_CONFIG_DIR}/${extractor}.conf

    if [[ -f ${extractorConfFile} ]]; then
      readonly EXTRACTOR_CONFIG=${extractorConfFile}
      assertSuccess 'Extractor config:' "${EXTRACTOR_CONFIG/#$HOME/\~}"
    fi
  fi
}

addToWatchList() {
  [[ -s $LIST_JSON ]] || echo '{ "watching": [] }' >"${LIST_JSON}"
  [[ ${SERIES} ]] || assertError || exit 1

  local pipeTitles
  read -r pipeTitles < <(makeFIFO) || exit 1
  jq -r '.[][]?.title' 2>/dev/null <<<"${JSON}" >"${pipeTitles}" &

  if ! grep -qxF "${SERIES}" "${pipeTitles}" 2>/dev/null; then
    local pipeAddToList
    read -r pipeAddToList < <(makeFIFO) || exit 1

    assertSelection "
      Add series to 'watching' list
      Skip (esc)
    " --disabled >"${pipeAddToList}" &

    local confirmAddToWatchList
    read -r confirmAddToWatchList <"${pipeAddToList}" || return 0

    if [[ ${confirmAddToWatchList} == 'Add'* ]]; then
      jq \
        --arg url "${SERIES_URL}" \
        --arg title "${SERIES}" \
        --arg extractor "${EXTRACTOR}" \
        '.watching += [{ $url, $title, $extractor }]' <<<"${JSON}" \
        >"${LIST_JSON}" 2>/dev/null || assertError || exit 1

      assertSuccess "Series was added to 'watching' list"
      assertSuccess 'List path:' "${LIST_JSON/#$HOME/\~}"
    fi

  else
    local pipeList
    read -r pipeList < <(makeFIFO) || exit 1

    jq -cr --arg title "${SERIES}" \
      'keys[] as $list | select(.[$list][].title==$title) | $list' \
      <<<"${JSON}" >"${pipeList}" 2>/dev/null &

    local list
    read -r list <"${pipeList}" || assertError || exit 1
    assertSuccess "Series was found in '${list}' list"
    assertSuccess 'List path:' "${LIST_JSON/#$HOME/\~}"
  fi
}

processConfig() {
  local escape=$1

  if compgen -G "${CONFIG_DIR}/${SERIES}*" >/dev/null; then
    local pipeFoundConfig
    read -r pipeFoundConfig < <(makeFIFO) || exit 1

    assertSelection "
      ${MENU_TOP} Manage Series Config
      Select a config file for this series
      Create a new config file for this series
      ${escape:-Skip} (esc)
    " --disabled --header-lines 1 --preview-window 'wrap' --preview '
        echo "Available config files:"
        xargs -0 basename -a < <(find -- "'"${CONFIG_DIR}/${SERIES}"'"* -print0)
      ' >"${pipeFoundConfig}" &

    local useExistingConf
    read -r useExistingConf <"${pipeFoundConfig}" || return 0

    if [[ ${useExistingConf} == 'Select'* ]]; then
      selectConfigFile "${escape}" || return 1
    elif [[ ${useExistingConf} == 'Create'* ]]; then
      createConfigFile
    fi

  else
    local pipeNewConfig
    read -r pipeNewConfig < <(makeFIFO) || exit 1

    assertSelection "
      ${MENU_TOP} Manage Series Config
      Create a config file for this series
      ${escape:-Skip} (esc)
    " --disabled --header-lines 1 >"${pipeNewConfig}" &

    local createNewConf
    read -r createNewConf <"${pipeNewConfig}" || return 0
    [[ ${createNewConf} == 'Create'* ]] && createConfigFile
    return 0
  fi
}

stream() {
  echo
  assertTask 'Processing stream with MPV...'
  local mpvConf="${HOME}/.config/mpv/mpv.conf"

  if [[ ! -f ${mpvConf} ]]; then
    if mkdir -p ~/.config/mpv 2>/dev/null; then
      assertMissing "MPV config file not found!\n"
      assertTask 'Creating MPV config templates...'
      cp -ir /usr/local/share/doc/mpv/ ~/.config/mpv/
      assertSuccess 'MPV config file:' "${mpvConf/#$HOME/\~}"
    fi
  fi

  local -a mpvArgs=(
    "--ytdl-raw-options-append=config-location=$1"
    "${@:2}"
  )

  if grep -qxF "[${EXTRACTOR%\:*}]" "${mpvConf}" 2>/dev/null; then
    assertSuccess "'${EXTRACTOR%\:*}' profile was found in MPV config file"
    mpvArgs=("--profile=${EXTRACTOR%\:*}" "${mpvArgs[@]}")
  fi

  local playUnicode="${BLUE_TXT}\u25B6${RESET}"
  echo -e "${playUnicode} Opening '${SERIES}' stream..."
  mpv "${mpvArgs[@]}"
}

# shellcheck disable=SC2016
#! Don't replace `uniq` command with `sort`.
#* It breaks batchRenameSubtitles function for reversed playlist.
getVideoID() {
  local pattern="/^\[${EXTRACTOR}\]"'/{a=$0}/'"${*:-1}"'/{print a"\n"$0}'
  uniq <(sed 's/[][]//g;s/://' <(awk '{print $1, $2}' <(
    grep -F "[${EXTRACTOR}]" <(awk "${@:1:$#-1}" "${pattern}" "${DL_LOG}")
  )))
}

archiveVideoID() {
  local archivePath=$1
  local archiveExtra=$2

  if grep -qF 'Requested format is not available' "${DL_LOG}" 2>/dev/null; then
    echo
    assertTask 'Adding video-IDs with no matching format to archive...'
    local formatNotAvailableIDs
    # mapfile -t formatNotAvailableIDs < <(getVideoID 'format is not available')
    mapfile -t formatNotAvailableIDs < <(sed 's/[][]//g;s/://g' <(
      awk '{print $2, $3}' <(
        grep -F 'format is not available' "${DL_LOG}" 2>/dev/null
      )
    ))

    if [[ ${#formatNotAvailableIDs[@]} -gt 0 ]]; then
      printf '%s\n' "${formatNotAvailableIDs[@]}" >>"${archiveExtra}" &&
        assertSuccess 'IDs saved to:' "${archiveExtra/#$HOME/\~}"

      printf '%s\n' "${formatNotAvailableIDs[@]}" >>"${archivePath}" &&
        assertSuccess 'IDs saved to:' "${archivePath/#$HOME/\~}"
    else
      assertError 'unable to parse IDs from download log file'
      exit 1
    fi

  fi
}

renameSubtitles() {
  eval '
    local mediaFile=${1%.*}

    local file
    # for file in "${mediaFile}"*.[a-z][a-z]-[A-Z][A-Z].@(ass|srt|vtt|lrc); do
    for file in "${mediaFile}"*.[a-z][a-z]-[A-Z][A-Z].ass; do
      if [[ -f ${file} ]]; then
        local fileExtension=${file##*.}
        local renameFile
        read -r renameFile < <(
          mv -v -- "${file}" "${file%-[A-Z][A-Z].*}.${fileExtension}"
        )
        echo "[ ISO 639-1 subtitle ] ${renameFile#*-> }"
      fi
    done 2>/dev/null
  '
}

batchRenameSubtitles() {
  if compgen -G ./*.[a-z][a-z]-[A-Z][A-Z].@(ass|srt|vtt|lrc) >/dev/null; then
    echo
    assertTask 'Renaming subtitles...'
    renameSubtitles
  fi
}

processFragmentedDownload() {
  local fragmentedDownload=$1
  local patterns=$2
  local archivePath=$3

  local fileExtension=${fragmentedDownload##*.}
  local fragmentedFiles
  read -r fragmentedFiles < <(
    find -- "${fragmentedDownload%"$fileExtension"}"*"${fileExtension}"* \
      2>/dev/null
  )

  if [[ ! ${fileExtension} =~ (${SUPPORTED_VIDEO_EXT}) ]] ||
    [[ ! ${fragmentedFiles} ]]; then
    assertError 'invalid list of fragmented files!'
    exit 1
  fi

  local filesToDelete
  if [[ ${DELETE_FRAG} -ne 0 ]]; then
    filesToDelete=${fragmentedFiles}
  else
    local header='Select one or more files to delete:'
    read -r filesToDelete < <(
      fzf -m --no-select-1 --header "${header}" <<<"${fragmentedFiles}"
    )
  fi

  if [[ ${filesToDelete} ]]; then
    local pluralFile
    read -r pluralFile < <(isPlural "${filesToDelete}")
    echo
    assertTask "Deleting fragmented file${pluralFile} from disk..."
    local foundPattern
    read -r foundPattern < <(
      sort --unique < <(grep -oE "${patterns}" "${DL_LOG}" 2>/dev/null)
    )

    if [[ ${foundPattern} ]]; then
      local pattern
      while IFS= read -r pattern; do
        assertMissing 'Detected error:' "${pattern}"
      done <<<"${foundPattern}"
    fi

    local filesCount
    read -r filesCount < <(wc -l <<<"${filesToDelete}")

    local deleteFragmentedFiles
    if [[ ${DELETE_FRAG} -eq 0 ]]; then
      local pipeDeleteFrag
      read -r pipeDeleteFrag < <(makeFIFO) || exit 1

      assertSelection "
        ${RED_BOLD_TXT}${filesToDelete}${RESET}
        Delete listed file${pluralFile} from disk!
        Cancel (esc)
      " --header-lines "${filesCount}" >"${pipeDeleteFrag}" &

      read -r deleteFragmentedFiles <"${pipeDeleteFrag}"
    fi

    local file
    if [[ ${deleteFragmentedFiles} == 'Delete'* || ${DELETE_FRAG} -ne 0 ]]; then
      while IFS= read -r file; do
        rm -f -- "${PWD}/${file}" 2>/dev/null

        if [[ ! -f ${file} ]]; then
          assertSuccess 'Deleted:' "${file}"
        else
          assertMissing 'Unable to delete:' "${file}"
        fi

      done <<<"${filesToDelete}"
    else

      while IFS= read -r file; do
        assertMissing 'Fragmented file:' "${file}"
      done <<<"${filesToDelete}"
    fi

    echo
    assertTask 'Removing fragmented video-ID from archive...'
    local fragmentedID
    read -r fragmentedID < <(getVideoID "${patterns}")

    if [[ ${fragmentedID} ]]; then
      if grep -qxF "${fragmentedID}" "${archivePath}" 2>/dev/null; then
        local archiveBackup
        read -r archiveBackup < <(cp -v -- "${archivePath/#$HOME/\~}"{,.bak})
        assertSuccess 'Backup:' "${archiveBackup#*-> }"
        sed -ni "/^${fragmentedID}$/!p" "${archivePath}"

        if ! grep -qxF "${fragmentedID}" "${archivePath}" 2>/dev/null; then
          assertSuccess 'Removed ID:' "${fragmentedID}"
        else
          assertMissing 'Unable to remove ID:' "${fragmentedID}"
          exit 1
        fi

      else
        assertSuccess 'No fragemented video-IDs were found in archive'
      fi

    else
      assertError 'unable to parse fragmented video-IDs'
      exit 1
    fi

  else
    assertMissing 'Deleting fragmented files was canceled!'
  fi
}

fragmentMonitor() {
  local patterns=$1
  local downloadPID=$2
  local ytdArgs=$3

  until grep -qE "${patterns}" "${DL_LOG}" 2>/dev/null; do
    sleep 1

    if ! pgrep -qP "${downloadPID}"; then
      #! This check is important!
      # In case youtube-dl was terminated before an error pattern was catched.
      grep -qE "${patterns}" "${DL_LOG}" 2>/dev/null && break
      return 0
    fi
  done

  pkill -f -- yt-dlp "${ytdArgs}"
  while pgrep -qf -- "yt-dlp ${ytdArgs//\[/\\\[}"; do
    sleep 1
  done

  echo
  assertTask 'Terminating download process...'
  assertMissing 'fragment error detected!'
  kill -SIGTERM -- -"${downloadPID}" &>/dev/null

  while pgrep -qP "${downloadPID}"; do
    sleep 1
  done

  assertSuccess "Download process has been terminated"
  return 1
}

getBaseDir() {
  local path=$1

  local evaluatedPath
  read -r evaluatedPath < <(eval echo "${path}")

  local baseDir
  read -r baseDir < <(dirname "${evaluatedPath}")

  if cd "${baseDir}" 2>/dev/null; then
    pwd
  else
    assertError 'unable to access the base directory of file:' "$1"
  fi
}

youtubeDl() {
  declare -xf renameSubtitles
  #! Keep the following command inside this function!
  #* Otherwise, user won't be able to interrupt download process with CTL+C.
  script -q "${DL_LOG}" yt-dlp "$@"
}

download() {
  local archiveDir
  local archivePath
  if [[ ${ARCHIVE_PATH} ]]; then
    read -r archiveDir < <(getBaseDir "${ARCHIVE_PATH}") || exit 1
    archivePath=${archiveDir}/${ARCHIVE_PATH##*\/}
  fi

  if [[ ${DOWNLOAD_DIR} || ${MAKE_SUB_DIR} -ne 0 ]]; then
    [[ ${DOWNLOAD_DIR} ]] && if ! cd "${DOWNLOAD_DIR}" 2>/dev/null; then
      assertError 'unable to change to Clanime Downloads directory'
      exit 1
    fi

    if [[ ${MAKE_SUB_DIR} -ne 0 ]]; then
      mkdir -p "${SERIES}" 2>/dev/null
      if ! cd "${SERIES}" 2>/dev/null; then
        assertError 'unable to change to series directory'
        exit 1
      fi
    fi

    assertSuccess 'Download directory:' "${PWD/#$HOME/\~}"
  fi

  #* Keep the following archive variables here.
  #* They must refer to the active directory
  if [[ ! ${ARCHIVE_PATH} ]]; then
    local archiveFromConfig
    # if read -r archiveFromConfig < <(sed -E "s/'|\"//g" <(awk '{print $2}' <(
    if read -r archiveFromConfig < <(
      sed -E "s/^\s*--download-archive //;s/^('|\")//;s/('|\")$//" <(
        tail -n 1 <(grep '^\s*--download-archive ' "$1" 2>/dev/null)
      )
    ); then
      # ))); then
      read -r archiveDir < <(getBaseDir "${archiveFromConfig}") || exit 1
      archivePath=${archiveDir}/${archiveFromConfig##*\/}
    else
      archiveDir=${PWD}
      archivePath=${archiveDir}/archive.txt
    fi
  fi

  local archiveExtra=${archivePath%.*}-extra.${archivePath##*.}
  # --***-- #

  if [[ -w ${archiveDir} ]]; then
    assertSuccess 'Download archive:' "${archivePath/#$HOME/\~}"
  else
    assertMissing 'Download archive path:' "${archivePath/#$HOME/\~}"
    assertMissing 'Invalid download archive path.' \
      'Make sure to set a valid path with writting permission!!!'
    exit 1
  fi

  findLastVidoAdded() {
    local file
    local latest

    for file in *.@(${SUPPORTED_VIDEO_EXT}); do
      [[ ${file} -nt ${latest} ]] && latest=${file}
    done 2>/dev/null

    echo "${latest}"
  }

  promptAutonumber() {
    local number
    read -r number < <(readPrompt '--autonumber-start ' '1')
    isPositiveInteger "${number}"
  }

  read -r DL_LOG < <(makeTEMP 'yt-dlp-log') || exit 1
  readonly DL_LOG

  local -a ytdArgsModel=(
    '--config-location' "$1"
    '--download-archive' "${archivePath}"
    "${@:2}"
  )

  local patterns
  read -r patterns < <(paste -sd '|' <(trimWhiteSpace "${YTD_ERRORS}"))

  local hasAutonumber
  read -r hasAutonumber < <(
    grep -E '\s*(--output |-o ).*%\(autonumber\)' <<<"$*" 2>/dev/null ||
      grep -E '^\s*(--output |-o ).*%\(autonumber\)' "$1" \
        2>/dev/null
  )

  local startNumber=${AUTONUMBER}
  local maxAttempts=10
  local -a range
  mapfile -t range < <(seq ${maxAttempts})

  for retry in "${range[@]}"; do
    local -a ytdArgs
    if [[ ${startNumber} ]]; then
      ytdArgs=('--autonumber-start' "${startNumber}" "${ytdArgsModel[@]}")

    elif [[ ${hasAutonumber} ]]; then
      assertWarning "you are using 'autonumber' in filename output."
      assertTip "pass the next episode number with 'autonumber-start' option."

      local latest
      read -r latest < <(findLastVidoAdded)
      if [[ ${latest} ]]; then
        assertTip 'the following file is potentially the last episode added!'
        echo "${latest}"
      fi

      echo
      while true; do
        readHeader 'Edit the number below (then press [ENTER])'
        if ! read -r startNumber < <(promptAutonumber); then
          clearLines 3
          assertMissing 'Invalid autonumber-start value!' \
            'It must be an integer that is greater than 0.'
        else
          if [[ ${latest} ]]; then
            clearLines 7
          else
            clearLines 5
          fi
          break
        fi
      done

      ytdArgs=('--autonumber-start' "${startNumber}" "${ytdArgsModel[@]}")
    else
      ytdArgs=("${ytdArgsModel[@]}")
    fi

    # local execFromConfig
    # read -r execFromConfig < <(paste -sd ';' <(
    #   sed -E "s/^\s*--exec //;s/^('|\")//;s/('|\")$//" <(
    #     grep '^\s*--exec ' "$1" 2>/dev/null
    #   )
    # ))

    # local execAll="${execFromConfig}; ${EXEC}"

    # shellcheck disable=SC2016
    # if [[ ${ISO_SUB} -ne 0 ]]; then
    #   ytdArgs+=(
    #     '--exec'
    #     "bash -c 'shopt -s extglob; renameSubtitles \"\$1\"' -- {}; ${execAll}"
    #   )
    # elif [[ ${EXEC} || ${execFromConfig} ]]; then
    #   ytdArgs+=('--exec' "${execAll}")
    # fi

    echo
    assertTask "Downloading with youtube-dl [attempt ${retry} of 10]..."
    youtubeDl "${ytdArgs[@]}" &
    local youtubeDLPID=$!

    until pgrep -qf -- 'yt-dlp' "${ytdArgs[@]//\[/\\\[}"; do
      echo -ne \
        "${CYAN_TXT}[${MAGENTA_BOLD_TXT}" \
        'sleeping' \
        "${CYAN_TXT}]${RESET}" \
        'Waiting for yt-dlp process... \r'
      sleep 1
      pgrep -qP "${youtubeDLPID}" || exit 1
    done

    if ! fragmentMonitor \
      "${patterns}" "${youtubeDLPID}" "${ytdArgs[@]}"; then
      local pipeFragDownload
      read -r pipeFragDownload < <(makeFIFO) || exit 1

      awk '/^\[download\] Destination/{a=$0}/'"${patterns}"'/{print a"\n"$0}' \
        "${DL_LOG}" >"${pipeFragDownload}" 2>/dev/null &

      local fragmentedDownload
      read -r fragmentedDownload < <(tr -d '\r' < <(awk -F ': ' '{print $2}' <(
        head -n 1 <(grep -F '[download] Destination' "${pipeFragDownload}")
      )))

      processFragmentedDownload \
        "${fragmentedDownload}" "${patterns}" "${archivePath}"
    fi

    wait "${youtubeDLPID}"
    # archiveVideoID "${archivePath}" "${archiveExtra}"
    handleYtdErrors "${DL_LOG}" 'download' &&
      if [[ ! ${fragmentedDownload} ]]; then
        [[ ${BATCH_ISO_SUB} -eq 1 ]] && batchRenameSubtitles
        break
      fi

    unset -v fragmentedDownload
    unset -v youtubeDLPID
    unset -v renameSubtitlesPID
    unset -v startNumber
    unset -v latest

    if [[ ${retry} -eq 10 ]]; then
      assertMissing 'maximum download attempts has been reached.' \
        'Please try again later!'
      exit 1
    fi

    echo
    assertTask "Downloading with youtube-dl [attempt $((retry + 1)) of 10]..."

    for second in {15..2}; do
      echo -ne \
        "${CYAN_TXT}[${MAGENTA_BOLD_TXT}" \
        'sleeping' \
        "${CYAN_TXT}]${RESET}" \
        "${second} seconds... \r"
      sleep 1
    done

    echo -ne \
      "${CYAN_TXT}[${MAGENTA_BOLD_TXT}" \
      'sleeping' \
      "${CYAN_TXT}]${RESET}" \
      "1 second... \r"
    sleep 1
    clearLines 2
  done
}

downloadOrStream() {
  local streamOrDownload=$1
  [[ ${streamOrDownload} ]] || if command -v mpv >/dev/null; then
    read -r streamOrDownload < <(assertSelection 'Stream \n Download')
  else
    streamOrDownload='Download'
  fi

  local concatConf
  read -r concatConf < <(makeTEMP 'config') || exit 1

  cat "${USER_CONFIG}" "${EXTRACTOR_CONFIG}" "${SERIES_CONFIG}" \
    >"${concatConf}" 2>/dev/null

  if [[ ${streamOrDownload} == 'Stream' ]]; then
    assertSuccess 'Stream series with MPV media player'

    if [[ $* =~ '--playlist=' ]]; then
      stream "${concatConf}" "${@:2}"
      exit
    else
      stream "${concatConf}" "${@:2}" -- "${SERIES_URL}"
      exit
    fi

  elif [[ ${streamOrDownload} == 'Download' ]]; then
    assertSuccess 'Download series with youtube-dl'

    if [[ $* =~ ('-a '|'--batch-file ') ]]; then
      download "${concatConf}" "${@:2}"
      exit
    else
      download "${concatConf}" "${@:2}" "${SERIES_URL}"
      exit
    fi

  else
    assertMissing 'Exiting...'
    exit 1
  fi
}

parseListTitles() {
  local selectedList=$1

  if ! jq -cr --arg list "${selectedList}" '.[$list][].title' <<<"${JSON}" \
    2>/dev/null; then
    assertError 'unable to parse titles from list!'
    exit 1
  fi
}

selectFromList() {
  local selectedList=$1

  local pipeTitles
  read -r pipeTitles < <(makeFIFO) || exit 1
  parseListTitles "${selectedList}" >"${pipeTitles}" &

  local header
  read -r header < <(echo -e "${MENU_END} Select a series from the list:")
  local series
  read -r series < <(fzf --header "${header}" <"${pipeTitles}") || return 1
  readonly SERIES=${series}

  local pipeObject
  read -r pipeObject < <(makeFIFO) || exit 1

  jq -c --arg list "${selectedList}" --arg title "${SERIES}" \
    '.[$list][] | select(.title==$title)' <<<"${JSON}" >"${pipeObject}" \
    2>/dev/null || assertError || exit 1 &

  local seriesObject
  read -r seriesObject <"${pipeObject}" || exit 1
  read -r SERIES_URL < <(jq -cr '.url' <<<"${seriesObject}" 2>/dev/null)
  read -r EXTRACTOR < <(jq -cr '.extractor' <<<"${seriesObject}" 2>/dev/null)

  readonly SERIES_URL
  readonly EXTRACTOR

  if [[ ! ${SERIES_URL} || ${SERIES_URL} == 'null' ]]; then
    assertError 'invalid url value!'
    exit 1
  elif [[ ! ${EXTRACTOR} || ${EXTRACTOR} == 'null' ]]; then
    assertError 'invalid extractor value!'
    exit 1
  fi

  local extractor
  read -r extractor < <(safeFilename <<<"${EXTRACTOR%\:*}")
  local extractorConfFile=${EXTRACTORS_CONFIG_DIR}/${extractor}.conf

  assertSuccess 'Series:' "${SERIES}"
  assertSuccess 'URL:' "${SERIES_URL}"
  assertSuccess 'Extractor:' "${EXTRACTOR}"

  if [[ -f ${extractorConfFile} ]]; then
    readonly EXTRACTOR_CONFIG=${extractorConfFile}
    assertSuccess 'Extractor config:' "${EXTRACTOR_CONFIG/#$HOME/\~}"
  fi
}

selectList() {
  local keys=$1
  local header=$2
  local hide=$3

  local pipeLists
  read -r pipeLists < <(makeFIFO) || exit 1
  grep -vixF "${hide} List" <(browseList "${keys}") >"${pipeLists}" \
    2>/dev/null &

  local -a lists
  mapfile lists <"${pipeLists}"

  local pipeSelectedList
  read -r pipeSelectedList < <(makeFIFO) || exit 1
  # shellcheck disable=SC2016,SC1004
  assertSelection "
    ${header}
    ${lists[*]}
  " --header-lines 1 --no-select-1 --preview '
      read -r list < <(grep -ixF {..-2} <(jq -nr '\'"${ACTIVE_KEYS}"'|.[]'\''))
      head -n ${FZF_PREVIEW_LINES} <(
        jq -cr --arg list "${list}" '\''.[$list][]?.title'\'' <'"${LIST_JSON}"'
      )
    ' >"${pipeSelectedList}" &

  local selectedList
  read -r selectedList <"${pipeSelectedList}" || return 1
  grep -ixF "${selectedList/' List'/}" <(jq -r '.[]' <<<"${keys}") \
    2>/dev/null || assertError 'unable to match list in json file!' || exit 1
}

backupList() {
  if ! mkdir -p "${LIST_JSON_BACKUP_DIR}" 2>/dev/null; then
    assertError 'could not create list backup directory:' \
      "${LIST_JSON_BACKUP_DIR}"
    exit 1
  fi

  local backupDate
  read -r backupDate < <(date '+%Y-%m-%d_%H-%M-%S')
  local backupPath
  read -r backupPath < <(
    cp -v -- "${LIST_JSON}" \
      "${LIST_JSON_BACKUP_DIR}/${LIST_JSON##*\/}.${backupDate}.bak"
  )
  assertSuccess 'Backup list:' "${backupPath/#*-> $HOME/\~}"
}

moveToList() {
  local from=$1
  local to=$2

  if [[ ! -f ${LIST_JSON} ]]; then
    assertError "list 'JSON' file was not found: ${LIST_JSON}"
    exit 1
  fi

  local header
  if [[ ${to} == 'delete' ]]; then
    header='Delete series'
  elif [[ ${to} ]]; then
    header="Move series to '${to}' list"
  else
    header='Move series'
  fi

  local fromListHeader
  fromListHeader="${MENU_NAV} ${header} from..."

  if [[ ${from} ]]; then
    if ! grep -qxF "${from}" <(jq -r '.[]' <<<"${ACTIVE_KEYS}"); then
      assertError "'${from}' list is not available!"
      exit 1
    fi
  else
    local pipeFromList
    read -r pipeFromList < <(makeFIFO) || exit 1
    selectList "${ACTIVE_KEYS}" "${fromListHeader}" "${to}" >"${pipeFromList}" &
    read -r from <"${pipeFromList}" || return 2
  fi

  local pipeSeries
  read -r pipeSeries < <(makeFIFO) || exit 1

  if [[ ${SERIES} ]]; then
    echo "${SERIES}" >"${pipeSeries}" &
  else
    local pipeTitles
    read -r pipeTitles < <(makeFIFO) || exit 1
    parseListTitles "${from}" >"${pipeTitles}" &

    local seriesListHeader
    read -r seriesListHeader < <(
      echo -e "${MENU_INT} Select one or more series from list:"
    )

    # shellcheck disable=SC2016
    fzf <"${pipeTitles}" -m --no-select-1 \
      --header "${seriesListHeader}" \
      --preview 'head -n ${FZF_PREVIEW_LINES} <(printf "%s\n" {+})' \
      >"${pipeSeries}" &
  fi

  local series
  read -r series < <(jq -cs < <(jq -cR <"${pipeSeries}")) || return 1
  [[ ! ${series} || ${series} == '[]' ]] && return 1

  local pipeObjectsList
  read -r pipeObjectsList < <(makeFIFO) || exit 1

  jq -c --argjson series "${series}" --arg list "${from}" \
    '.[$list] | map(select(.title as $title | $series | index($title)))' \
    <<<"${JSON}" 2>/dev/null >"${pipeObjectsList}" &

  local objectsList
  read -r objectsList <"${pipeObjectsList}"
  [[ ${objectsList} && ${objectsList} != '[]' ]] || assertError || exit 1

  if [[ ${to} ]]; then
    if [[ ! ${to} =~ ('delete'|'archive') ]] &&
      ! grep -qxF "${to}" <(jq -r '.[]' <<<"${ALL_KEYS}"); then
      assertError "'${to}' list is not available!"
      exit 1
    fi
  else
    local pipeToList
    read -r pipeToList < <(makeFIFO) || exit 1
    selectList "${ALL_KEYS}" "
      ${MENU_END} ${fromListHeader/@("${MENU_NAV} "|'...')/} '${from}' list to:
    " "${from}" >"${pipeToList}" &
    read -r to <"${pipeToList}" || return 1
  fi

  if [[ ${to} == 'delete' ]]; then
    assertWarning 'associated config files will be permanently deleted' \
      'from disk if you chose to delete them'
    assertWarning 'the following series will be permanently deleted from' \
      "'${from}' list"
    jq -cr 'map("- "+.)[]' <<<"${series}"

    local sereisItemsNo
    read -r sereisItemsNo < <(jq 'length' <<<"${series}")
    local maybeThem
    read -r maybeThem < <(
      [[ ${sereisItemsNo} -gt 1 ]] && echo them || echo it
    )
    local deletOption="Delete ${maybeThem} from list"
    local pipeConfirmDelete
    read -r pipeConfirmDelete < <(makeFIFO) || exit 1

    assertSelection "
      ${deletOption}!
      ${deletOption} along with associated config files!
      Abort (esc)
    " --disabled >"${pipeConfirmDelete}" &

    local confirmDelete
    read -r confirmDelete <"${pipeConfirmDelete}"
    if [[ ${confirmDelete} == "${deletOption}"* ]]; then
      backupList || exit 1

      jq --argjson objectsList "${objectsList}" --arg fromList "${from}" \
        '.[$fromList] -= $objectsList' <<<"${JSON}" \
        >"${LIST_JSON}" 2>/dev/null &

      local pid=$!
      waitingFor 'jq to rebuild list file' "${pid}"

      if wait "${pid}"; then
        local maybeWere
        read -r maybeWere < <(
          [[ ${sereisItemsNo} -gt 1 ]] && echo were || echo was
        )
        assertSuccess "Series ${maybeWere} deleted from '${from}' list"
        assertSuccess 'List path:' "${LIST_JSON/#$HOME/\~}"

        if [[ ${confirmDelete} == "${deletOption} along"* ]]; then
          local pipeConfig
          read -r pipeConfig < <(makeFIFO) || exit 1

          local title
          while IFS= read -r title; do
            # findConfig "${title}" # make it interactive?
            find -- "${CONFIG_DIR}/${title}"*.conf 2>/dev/null
          done < <(jq -r '.[]' <<<"${series}") >"${pipeConfig}" &

          local configFile
          while IFS= read -r configFile; do
            rm -f -- "${configFile}" 2>/dev/null

            if [[ ! -f ${configFile} ]]; then
              assertSuccess 'Config file was deleted:' "${configFile##*\/}"
            else
              assertMissing 'Unable to delete:' "${configFile##*\/}"
            fi

          done <"${pipeConfig}"
        fi
        exit
      else
        assertError 'jq failed to rebuild the list!'
        exit 1
      fi
    else
      assertMissing 'Exiting...'
      exit
    fi
  fi

  if ! backupList || ! jq --argjson objectsList "${objectsList}" \
    --arg fromList "${from}" \
    --arg toList "${to}" \
    '.[$toList] += $objectsList | .[$fromList] -= $objectsList' <<<"${JSON}" \
    >"${LIST_JSON}"; then
    assertError
    exit 1
  else
    assertSuccess "Series transfered from '${from}' list to '${to}' list"
    if [[ ! ${SERIES} ]]; then
      jq -cr 'map("- "+.)[]' <<<"${series}"
    else
      echo
    fi
  fi
}

waitingFor() {
  local processMessage=$1
  local pid=$2

  local maxDuration=30
  local duration
  local -a range
  mapfile -t range < <(seq ${maxDuration})

  for duration in "${range[@]}"; do
    local dots
    read -r dots < <(perl -E "print '.' x ${duration}")

    echo -ne \
      "${CYAN_TXT}[${MAGENTA_BOLD_TXT}" \
      'sleeping' \
      "${CYAN_TXT}]${RESET}" \
      "Waiting for ${processMessage}..${dots} \r"
    sleep 1

    if ! pgrep -qP "${pid}"; then
      echo -e '\e[K\e[1A'
      break
    fi

    if [[ ${duration} -eq "${maxDuration}" ]]; then
      echo -e '\e[K\e[1A'
      assertError 'time out! Please try again later!'
      kill -SIGTERM -- -"${pid}" &>/dev/null
      exit 1
    fi
  done
}

deleteList() {
  local pipeSelectedList
  read -r pipeSelectedList < <(makeFIFO) || exit 1
  selectList "${ALL_KEYS}" "${MENU_NAV} Delete..." 'watching' \
    >"${pipeSelectedList}" &

  local selectedList
  read -r selectedList <"${pipeSelectedList}" || return 2

  assertWarning "'${selectedList}' list will be permanently deleted!"

  local pipeConfirmDelete
  read -r pipeConfirmDelete < <(makeFIFO) || exit 1

  assertSelection "
    ${RED_BOLD_TXT}Confirm deletion!${RESET}
    Abort (esc)
  " --disabled >"${pipeConfirmDelete}" &

  local confirmDelete
  read -r confirmDelete <"${pipeConfirmDelete}"

  if [[ ${confirmDelete} != 'Confirm'* ]]; then
    assertMissing 'Exiting...'
    exit 1
  fi

  backupList || exit 1

  jq --arg list "${selectedList}" 'del(.[$list])' <<<"${JSON}" >"${LIST_JSON}" \
    2>/dev/null

  local pid=$!
  waitingFor 'jq to rebuild list file' "${pid}"
  if wait "${pid}"; then
    assertSuccess "'${selectedList}' list was deleted"
    assertSuccess 'List path:' "${LIST_JSON/#$HOME/\~}"
    exit
  else
    assertError
    exit 1
  fi
}

renameList() {
  local old=$1
  local new=$2
  jq --arg old "${old}" --arg new "${new}" \
    'with_entries(if .key == $old then .key = $new else . end)' 2>/dev/null ||
    assertError
}

rearrangeLists() {
  local pipeSelectedList
  read -r pipeSelectedList < <(makeFIFO) || exit 1
  selectList "${ALL_KEYS}" "${MENU_NAV} Reposition..." >"${pipeSelectedList}" &

  local selectedList
  read -r selectedList <"${pipeSelectedList}" || return 2

  local pipePosition
  read -r pipePosition < <(makeFIFO) || exit 1

  assertSelection "
    Reposition '${selectedList}' list...
    To top
    To bottom
    Above a list...
    Below a list...
  " --header-lines 1 >"${pipePosition}" &

  local position
  read -r position < <(awk '{print tolower($0)}' "${pipePosition}") || return 1

  if [[ ! ${position} =~ ('to top'|'to bottom') ]]; then
    local pipePositionFromList
    read -r pipePositionFromList < <(makeFIFO) || exit 1
    selectList "${ALL_KEYS}" "Move it ${position%' a list...'}..." \
      "${selectedList}" >"${pipePositionFromList}" &

    local positionFromList
    read -r positionFromList <"${pipePositionFromList}" || return 1

    local pipeTargetIndex
    read -r pipeTargetIndex < <(makeFIFO) || exit 1
    jq -c \
      --arg selectedList "${selectedList}" \
      --arg targetList "${positionFromList}" \
      '.-=[$selectedList] | index($targetList)' <<<"${ALL_KEYS}" \
      >"${pipeTargetIndex}" &

    local targetIndex
    read -r targetIndex <"${pipeTargetIndex}"
  fi

  newArrangement() {
    local selectedList=$1
    local index=$2

    jq -c \
      --arg list "${selectedList}" \
      --argjson index "${index}" \
      '.-=[$list] | [.[0:$index][], $list, .[$index:][]]' <<<"${ALL_KEYS}"
  }

  local newOrder
  local index
  if [[ ${position} == 'to top' ]]; then
    read -r newOrder < <(newArrangement "${selectedList}" '0')

  elif [[ ${position} == 'to bottom' ]]; then
    index=$((ALL_KEYS_COUNT - 1))
    read -r newOrder < <(newArrangement "${selectedList}" "${index}")

  elif [[ ${position} == 'above a list...' ]]; then
    index=${targetIndex}
    read -r newOrder < <(newArrangement "${selectedList}" "${index}")

  elif [[ ${position} == 'below a list...' ]]; then
    index=$((targetIndex + 1))
    read -r newOrder < <(newArrangement "${selectedList}" "${index}")
  fi

  if [[ ! ${newOrder} ]]; then
    assertError 'unable to reposition list!'
    exit 1
  elif [[ ${newOrder} == "${ALL_KEYS}" ]]; then
    assertMissing 'No changes were made!'
    exit
  else

    backupList

    jq --argjson keys "${newOrder}" \
      '. as $list | reduce $keys[] as $key ({}; .[$key] = $list[$key])' \
      <<<"${JSON}" >"${LIST_JSON}" 2>/dev/null &

    local pid=$!
    waitingFor 'jq to rebuild list file' "${pid}"
    if wait "${pid}"; then
      assertSuccess 'List file was rebuilt'
      assertSuccess 'List path:' "${LIST_JSON/#$HOME/\~}"
      exit
    else
      assertError
      exit 1
    fi
  fi
}

manageLists() {
  local count
  read -r count < <(jq 'length' <<<"${ACTIVE_KEYS}")
  if [[ ${count} -eq 1 ]]; then
    grep -qxF 'archive' <(jq -r '.[]' <<<"${ACTIVE_KEYS}") 2>/dev/null ||
      local toArchive='Move Series to Archive'
    grep -qxF 'watching' <(jq -r '.[]' <<<"${ACTIVE_KEYS}") 2>/dev/null ||
      local deleteAList='Delete a List'
  else
    local toArchive='Move Series to Archive'
    local deleteAList='Delete a List'
  fi

  if [[ ${ALL_KEYS_COUNT} -gt 1 ]]; then
    local between='Move Series Between Lists'
    local arrange='Rearrange Lists'
  fi

  local selectedAction
  read -r selectedAction < <(makeFIFO) || exit 1

  assertSelection "
    ${MENU_NAV} Manage Lists
    ${toArchive}
    ${between}
    Delete Series From a List
    ${deleteAList}
    ${arrange}
  " --header-lines 1 --no-select-1 >"${selectedAction}" &

  local action
  read -r action <"${selectedAction}" || return 2

  if [[ ${action} == 'Move Series to Archive' ]]; then
    navMenu moveToList '' 'archive' || return 1

  elif [[ ${action} == 'Move Series Between Lists' ]]; then
    navMenu moveToList || return 1

  elif [[ ${action} == 'Delete Series From a List' ]]; then
    navMenu moveToList '' 'delete' || return 1

  elif [[ ${action} == 'Delete a List' ]]; then
    navMenu deleteList || return 1

  elif [[ ${action} == 'Rearrange Lists' ]]; then
    navMenu rearrangeLists || return 1
  fi

  exit
}

listKeys() {
  jq -cr 'keys_unsorted' 2>/dev/null || assertError
}

removeEmptyLists() {
  jq -c '
    walk(if type=="object" then with_entries(select(.value!=[])) else . end)
  ' 2>/dev/null || assertError
}

browseList() {
  local keys=$1
  sed "s/\b\(.\)/\u\1/g;s/$/ List/" <(jq -r '.[]' <<<"${keys}")
}

browse() {
  local pipeSelectedList
  read -r pipeSelectedList < <(makeFIFO) || exit 1
  selectList "${ACTIVE_KEYS}" "${MENU_NAV} Browse..." >"${pipeSelectedList}" &
  local selectedList
  read -r selectedList <"${pipeSelectedList}" || return 2

  selectFromList "${selectedList}" || return 1
}

configProcessOptions() {
  local header="${MENU_NAV} Process config of a series from..."
  local pipeSelectedList
  read -r pipeSelectedList < <(makeFIFO) || exit 1
  selectList "${ACTIVE_KEYS}" "${header}" >"${pipeSelectedList}" &

  local selectedList
  read -r selectedList <"${pipeSelectedList}" || return 2
  selectFromList "${selectedList}" || return 1

  until processConfig 'Cancel'; do assertNav; done
  exit
}

navigate() {
  local pipeMenu
  read -r pipeMenu < <(makeFIFO) || exit 1

  assertSelection "
    ${MENU_TOP} Main Menu
    Browse Lists
    Manage Lists
    Manage Configurations
  " --header-lines 1 >"${pipeMenu}" &

  if ! read -r menu <"${pipeMenu}"; then
    assertMissing 'Exiting...'
    exit
  fi

  if [[ ${menu} == 'Browse Lists' ]]; then
    navMenu browse || return 1
    until processConfig; do assertNav; done
    downloadOrStream "${SUB_COMMAND}" "${ARGS[@]}"

  elif [[ ${menu} == 'Manage Lists' ]]; then
    navMenu manageLists || return 1

  else
    navMenu configProcessOptions || return 1
  fi
}

processExtractorEntry() {
  local extractorEntry
  read -r extractorEntry < <(
    head -n 1 <(grep -iF "${EXTRACTOR_ENTRY}" <(yt-dlp --list-extractors))
  )

  if ! [[ ${extractorEntry} ]]; then
    assertMissing 'Extractor was not found in yt-dlp list!'
    exit 1
  fi

  assertSuccess 'Extractor entry:' "${extractorEntry}"

  local extractor
  read -r extractor < <(safeFilename <<<"${extractorEntry%\:*}")
  local extractorConfFile=${EXTRACTORS_CONFIG_DIR}/${extractor}.conf

  if [[ -f ${extractorConfFile} ]]; then
    readonly EXTRACTOR_CONFIG=${extractorConfFile}
    assertSuccess 'Extractor config:' "${EXTRACTOR_CONFIG/#$HOME/\~}"
  else
    assertMissing 'Extractor config was not found:' \
      "${extractorConfFile/#$HOME/\~}"
  fi
}

validateOptionValue() {
  if [[ $2 =~ ^'-' ]]; then
    assertMissing "Invalid value '$2' for option '$1'." \
      "Do not use a value that begins with '-'."
    exit 1
  fi
}

#* --{ Main workflow }-- *#
while [[ $# -gt 0 ]]; do
  case "$1" in
  st | stream)
    if [[ ${SUB_COMMAND} ]]; then
      assertMissing 'Subcommand conflict!' \
        'Pass either stream (st) or download (dl) as a subcommand.'
      exit 1
    fi
    # readonly SUB_COMMAND='Stream'
    SUB_COMMAND='Stream'
    ;;

  dl | download)
    if [[ ${SUB_COMMAND} ]]; then
      assertMissing 'Subcommand conflict!' \
        'Pass either stream (st) or download (dl) as a subcommand.'
      exit 1
    fi
    # readonly SUB_COMMAND='Download'
    SUB_COMMAND='Download'
    ;;

  -e | --extractor)
    validateOptionValue "$1" "$2"
    # readonly EXTRACTOR_ENTRY=$2
    EXTRACTOR_ENTRY=$2
    shift
    ;;

  --no-delete)
    DELETE_FRAG=0
    ;;

  --delete-frag)
    DELETE_FRAG=1
    ;;

  --here)
    unset -v DOWNLOAD_DIR
    ;;

  --no-sub-dir)
    MAKE_SUB_DIR=0
    ;;

  --base-dir)
    validateOptionValue "$1" "$2"
    DOWNLOAD_DIR=$2
    shift
    ;;

  --dir)
    validateOptionValue "$1" "$2"
    DOWNLOAD_DIR=$2
    MAKE_SUB_DIR=0
    shift
    ;;

  --no-iso-sub)
    ISO_SUB=0
    BATCH_ISO_SUB=0
    ;;

  --batch-iso-sub)
    ISO_SUB=1
    BATCH_ISO_SUB=1
    ;;

  --ytd-series)
    # readonly YTD_SERIES=1
    YTD_SERIES=1
    ;;

  --series)
    validateOptionValue "$1" "$2"
    read -r SERIES < <(safeFilename <<<"$2")
    readonly SERIES
    shift
    ;;

  --season-template)
    if [[ ! $2 =~ ([Ss]ingle|[Mm]ulti|[Cc]ustom) ]]; then
      assertError 'invalid season-template value!' \
        'Valid values: single, multi, or custom.'
      exit 1
    fi
    # readonly DEFAULT_SEASON_NO=$2
    DEFAULT_SEASON_NO=$2
    shift
    ;;

  --parse-index)
    if ! read -r PARSE_INDEX_START < <(isPositiveInteger "$2"); then
      assertError 'invalid parse-index value!' \
        'It must be an integer number that is greater than 0.'
      exit 1
    fi
    # readonly PARSE_INDEX_START
    shift
    ;;

  --)
    ARGS=("${@:2}")
    unset -v index
    for index in "${!ARGS[@]}"; do
      [[ ${ARGS[${index}]} ]] || unset -v "ARGS[${index}]"
      if [[ ${ARGS[${index}]} == '--download-archive' ]]; then
        # readonly ARCHIVE_PATH=${ARGS[${index} + 1]}
        ARCHIVE_PATH=${ARGS[${index} + 1]}
        unset -v "ARGS[${index}]"
        unset -v "ARGS[${index} + 1]"
      elif [[ ${ARGS[${index}]} == '--autonumber-start' ]]; then
        if ! read -r AUTONUMBER < <(
          isPositiveInteger "${ARGS[${index} + 1]}"
        ); then
          assertError 'invalid autonumber-start value!' \
            'It must be an integer that is greater than 0.'
          exit 1
        fi
        # readonly -a AUTONUMBER
        unset -v "ARGS[${index}]"
        unset -v "ARGS[${index} + 1]"
      elif [[ ${ARGS[${index}]} == '--format' ]]; then
        # readonly FORMAT=${ARGS[${index} + 1]}
        FORMAT=${ARGS[${index} + 1]}
        unset -v "ARGS[${index}]"
        unset -v "ARGS[${index} + 1]"
      # elif [[ ${ARGS[${index}]} == '--exec' ]]; then
      #   readonly EXEC=${ARGS[${index} + 1]}
      #   unset -v "ARGS[${index}]"
      #   unset -v "ARGS[${index} + 1]"
      fi
      shift
    done
    unset -v index
    readonly -a ARGS
    shift
    break
    ;;

  *)
    if [[ $1 =~ https?://.* ]]; then
      if [[ ! ${SERIES_URL} ]]; then
        readonly SERIES_URL=$1
      else
        assertMissing 'Only one URL is supported!' \
          'Additional URLs will be ignored!'
      fi
    elif [[ $1 ]]; then
      assertMissing 'Invalid option:' "$1"
      exit 1
    fi
    ;;
  esac
  shift
done

readonly FORMAT
readonly -a AUTONUMBER
readonly ARCHIVE_PATH
readonly PARSE_INDEX_START
readonly DEFAULT_SEASON_NO
readonly YTD_SERIES
readonly EXTRACTOR_ENTRY
readonly SUB_COMMAND
#
readonly DELETE_FRAG
readonly DOWNLOAD_DIR
readonly MAKE_SUB_DIR
# shellcheck disable=SC2034  # Used in command line processing
readonly ISO_SUB
readonly BATCH_ISO_SUB

# if [[ ! -t 0 ]]; then
#   if [[ ${SERIES_URL} ]]; then
#     cat &>/dev/null
#     assertMissing 'URL was already provided as an argument!' \
#       'STDIN will be ignored!'
#   else
#
#     unset -v url
#     while IFS= read -r url; do
#       if [[ ! ${SERIES_URL} ]]; then
#         if [[ ${url} =~ https?://.* ]]; then
#           readonly SERIES_URL=${url}
#
#         elif [[ ${SERIES_URL} ]]; then
#           assertMissing 'Invalid URL:' "$1"
#           exit 1
#
#         else
#           assertError
#           exit 1
#         fi
#
#       else
#         # cat &>/dev/null
#         assertMissing 'Only one URL is supported!' \
#           'Additional URLs will be ignored!'
#         break
#       fi
#     done
#     unset -v url
#   fi
# fi

[[ ${DOWNLOAD_DIR} ]] && if [[ ! -d ${DOWNLOAD_DIR} ]]; then
  assertMissing 'Clanime Downloads directory was not found:'
  echo "${DOWNLOAD_DIR}"
  exit 1
elif [[ ! -w ${DOWNLOAD_DIR} ]]; then
  assertMissing 'You do not have permission to write files in the configured' \
    'Clanime Downloads directory.'
  exit 1
fi

if [[ ! -d ${CONFIG_DIR} ]]; then
  assertTask 'Creating config directory...'
  if ! mkdir -p "${CONFIG_DIR}" 2>/dev/null; then
    assertError 'unable to create config directory:' "${CONFIG_DIR}"
    exit 1
  fi
  assertSuccess 'Config directory:' "${CONFIG_DIR}\n"
fi

if [[ ! -d ${CACHE_DIR} ]]; then
  assertTask "Creating cache directory..."
  if ! mkdir -p "${CACHE_DIR}" 2>/dev/null; then
    assertError 'unable to create cache directory:' "${CACHE_DIR}"
    exit 1
  fi
  assertSuccess 'Cache directory:' "${CACHE_DIR}\n"
fi

if [[ -s "${LIST_JSON}" ]]; then
  read -r JSON < <(jq -c <"${LIST_JSON}" 2>/dev/null) || assertError || exit 1
  readonly JSON
  read -r ALL_KEYS < <(listKeys <<<"${JSON}")
  readonly ALL_KEYS
  read -r ACTIVE_KEYS < <(listKeys < <(removeEmptyLists <<<"${JSON}"))
  readonly ACTIVE_KEYS
  read -r ALL_KEYS_COUNT < <(jq 'length' <<<"${ALL_KEYS}")
  readonly ALL_KEYS_COUNT

  if [[ ! ${ALL_KEYS} || ${ALL_KEYS} == '[]' ]]; then
    assertMissing 'Invalid list file!'
    echo
    assertTask 'Deleting invalid list file...'
    if rm -- "${LIST_JSON}" 2>/dev/null; then
      assertSuccess 'File was deleted:' "${LIST_JSON/#$HOME/\~}"
      assertTip 'try to recover it from a backup.' \
        'Or add a new series to watching list.'
      exit 1
    else
      assertError 'unable to delete invalid list file!'
      exit 1
    fi
  fi
fi

read -r TMP_DIR < <(mktemp -qd "${TMP_DIR_PREFIX}")
readonly TMP_DIR
if ! [[ -d ${TMP_DIR} ]]; then
  assertError 'unable to create temporary directory!'
  exit 1
fi

trap 'cleanup' EXIT
trap 'cleanup HUP' HUP
trap 'cleanup TERM' TERM
trap 'cleanup INT' INT

if [[ ${SERIES_URL} ]]; then
  [[ ${EXTRACTOR_ENTRY} ]] && processExtractorEntry
  preSelectedSeries
  addToWatchList
  until processConfig; do assertNav; done
  downloadOrStream "${SUB_COMMAND}" "${ARGS[@]}"

elif [[ ! -s ${LIST_JSON} ]]; then
  assertMissing 'Nothing is stored in your local list, yet!' \
    'Provide series URL to add it to your list.'
  exit

else
  if [[ ${ACTIVE_KEYS} == '[]' ]]; then
    assertMissing 'Nothing is stored in your local list, yet!' \
      'Provide series URL to add it to your list.'
    exit
  fi

  until navigate; do assertNav; done
fi

exit
