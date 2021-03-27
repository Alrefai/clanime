#!/usr/bin/env bash

#* --{ Shell Script Settings }-- *#

set -o pipefail

readonly CACHE_HOME=${XDG_CACHE_HOME:-${HOME}/.cache}
readonly CACHE_DIR=${CACHE_HOME}/clanime
readonly CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME}/.config}
readonly CONFIG_DIR=${CONFIG_HOME}/clanime
readonly INDEX_DIR=${CONFIG_DIR}/playlist-index
readonly LIST_JSON=${CONFIG_DIR}/list.json
readonly DL_LOG=${CACHE_DIR}/download-log.txt

#* --{ User Settings with Environment Variables }-- *#

# youtube-dl user config path (optional)
readonly USER_CONFIG=${YTDL_USER_CONFIG:-${CONFIG_HOME}/youtube-dl/config}

# Crunchyroll config path (optional)
readonly \
  CRUNCHYROLL_CONFIG=${CRUNCHYROLL_CONFIG:-${CONFIG_DIR}/crunchyroll.conf}

# Default option for format filter
readonly \
  FORMAT_FILTER=${CLANIME_FORMAT:-[format_id*=jaJP][format_id!*=hardsub]}

# Output template options

readonly NAME_SUFFIX=${CLANIME_SERIES_NAME_SUFFIX:- - }
readonly SEASON_PREFIX=${CLANIME_SERIES_SEASON_PREFIX}
readonly SEASON_SUFFIX=${CLANIME_SERIES_SEASON_SUFFIX:-x}
readonly EPISODE_PREFIX=${CLANIME_SERIES_EPISODE_PREFIX}
readonly EPISODE_SUFFIX=${CLANIME_SERIES_EPISODE_SUFFIX:-03d - }

#* --{ User Settings with Environment Variables and CLI }-- *#
#! on/off values for options: on=1 | off=0

# Output template option for season number (single | multi | custom)
DEFAULT_SEASON_NO=${CLANIME_DEFAULT_SEASON_NO}

# Use youtube-dl provided series name in filename template (default: off)
YTD_SERIES=${CLANIME_YTD_SERIES_NAME}

# Create a sub-direcotry with series name (default: on)
MAKE_SUB_DIR=${CLANIME_MAKE_SUB_DIR}

# Optional download directory (default: current working direcotry)
DOWNLOAD_DIR=${CLANIME_DOWNLOAD_DIR}

# Optionally specify starting index when parsing a playlist (default: 1)
PARSE_INDEX_START=${CLANIME_PARSE_INDEX_START:-1}

# Rename subtitles to ISO 639-1 code format (default: on)
ISO_SUB=${CLANIME_ISO_SUB}

# Automatically delete fragmented files (default: on)
DELETE_FRAG=${CLANIME_DELETE_FRAG}

#* End of Settings *#

#* --{ Shell Script Global Variables }-- *#

unset EXTRACTOR
unset SERIES
unset SERIES_URL
unset SERIES_CONFIG
unset SUB_COMMAND
unset ARGS
unset MAIN

readonly BROWSE_LIST='Watching List'

# Font styling and colors

readonly BOLD_TXT=$'\e[1m'
readonly GREEN_BOLD_TXT=$'\e[1;32m'
readonly RED_BOLD_TXT=$'\e[1;31m'
readonly BLUE_TXT=$'\e[34m'
readonly RED_UNDERLINE_TXT=$'\e[4;31m'
readonly CYAN_TXT=$'\e[36m'
readonly MAGENTA_BOLD_TXT=$'\e[1;35m'
readonly MAGENTA_BG_BLACK_TXT=$'\e[45;30m'
readonly YELLOW_BOLD_TXT=$'\e[1;33m'
readonly RESET=$'\e[0m'

# shellcheck disable=SC2034
readonly FZF_DEFAULT_OPTS="
  --bind J:down,K:up,ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all \
  --reverse \
  --ansi \
  --no-multi \
  --height 20% \
  --min-height 15 \
  --border \
  --select-1"

readonly YTD_ERRORS='
  Error in the pull function
  PES packet size mismatch
  Failed to open segment
  Unable to open resource
  Packet corrupt
'

readonly BASE_URL='https://www.crunchyroll.com'

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
  echo -e "${missingMark} ${BOLD_TXT}$1${RESET}" "${@:2}"
}

assertWarning() {
  echo -e "${YELLOW_BOLD_TXT}WARNING${RESET}${BOLD_TXT}: $*${RESET}"
}

assertError() {
  echo -n "${RED_UNDERLINE_TXT}Error${RESET}: " >&2

  if [[ $# == 0 ]]; then
    echo 'something wrong happened!' >&2
  else
    echo "$*" >&2
  fi
}

trimWhiteSpace() {
  echo -e "$1" | grep '\S' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

assertSelection() {
  trimWhiteSpace "$1" | fzf "${@:2}"
}

assertTryAgain() {
  local tryAgain
  tryAgain=$(
    assertSelection '
      Would you like to try again?
      Yes
      Abort
    ' --header-lines 1
  )

  if [[ ${tryAgain} == 'Yes' ]]; then
    "$@"
  else
    assertMissing 'Aborted by user'
    exit 1
  fi
}

safeFilename() {
  local beSafe='
    s/^\W+|(?!
    (?:COM[0-9]|CON|LPT[0-9]|NUL|PRN|AUX|com[0-9]|con|lpt[0-9]|nul|prn|aux)
    |[\s\.])
    [\/:*\"?<>|~\\\\;]{1,254}/_/g
  '
  perl -pe "${beSafe//[[:space:]]/}"
}

readHeader() {
  echo "${MAGENTA_BG_BLACK_TXT} $1 ${RESET}"
}

readPrompt() {
  local prefix=$1
  local suffix=$2

  local textInput
  IFS= read \
    -erp "${CYAN_TXT}Text input ${MAGENTA_BOLD_TXT}->${RESET} ${prefix}" \
    -i "${suffix}" textInput

  echo "${textInput}"
}

isPlural() {
  test "$(wc -l <<<"$1")" -gt 1 && echo s
}

selectModifiers() {
  local maxItems=$1
  local headerItems=$2
  local modifiers=$3

  assertSelection "
    Select ${headerItems}
    ${modifiers}
  " -m "${maxItems}" --header-lines 1
}

confirmModifiers() {
  local indexFile=$1

  local playlistModifier
  until [[ ${playlistModifier} ]]; do
    if ! playlistModifier=$(selectModifiers "${@:2}"); then
      assertTryAgain
    elif grep -q '^--playlist-items' <<<"${playlistModifier}" &&
      grep -qE '^--playlist-(start|end)' <<<"${playlistModifier}"; then
      assertMissing 'Do not use --playlist-item with --playlist-(start|end)'
      unset playlistModifier
      assertTryAgain
    fi
  done

  local modifiersCount
  modifiersCount=$(wc -l <<<"${playlistModifier}")

  local confirmSelection
  if ! confirmSelection=$(
    assertSelection "
      Confirm playlist modifiers?
      $(assertSuccess "Playlist modifiers:\n${playlistModifier}")
      Yes
      No, reselect index numbers
      Skip
    " --header-lines $((modifiersCount + 2))
  ); then
    assertTryAgain confirmModifiers "$@"

  else
    if [[ ${confirmSelection} == 'Yes'* ]]; then
      assertSuccess 'Playlist modifiers:' "\n${playlistModifier}\n"
      echo "${playlistModifier}" >>"${SERIES_CONFIG}"
    elif [[ ${confirmSelection} == 'No'* ]]; then
      playlistSelection "${indexFile}"
    else
      assertMissing "Skipped by user\n"
    fi
  fi
}

playlistSelection() {
  local indexFile=$1

  if [[ ! -s ${indexFile} ]]; then
    assertMissing "No items in playlist index file\n"
    return
  fi

  local fzfHeader='Select one or two items from the list'
  local playlistItems
  if ! playlistItems=$(
    fzf --exact --no-sort -m 2 --header "${fzfHeader}" <"${indexFile}" |
      awk '{print $1}'
  ); then

    local tryAgain
    tryAgain=$(
      assertSelection '
        Would you like to try again?
        Yes
        No, continue without modifiers
        Abort
      ' --header-lines 1
    )

    if [[ ${tryAgain} == 'Yes' ]]; then
      playlistSelection "$@"
    elif [[ ${tryAgain} == 'No'* ]]; then
      assertSuccess "Continue without modifiers\n"
    else
      assertMissing 'Aborted by user'
      exit 1
    fi

  else
    local playlistModifiers
    playlistModifiers=$(
      awk '
        END{print "--playlist-end "$1}
        NR==1{print "--playlist-start "$1}
      ' <<<"${playlistItems}"
    )

    if [[ $(awk '{print NR}' <<<"${playlistItems}") == 1 ]]; then
      confirmModifiers "${indexFile}" 1 'a modifier' "${playlistModifiers}"
    else
      local range
      range=$(paste -sd '-' - <<<"${playlistItems}")
      playlistModifiers="${playlistModifiers}\n--playlist-items ${range}"
      confirmModifiers "${indexFile}" 2 'one or two modifiers' \
        "${playlistModifiers}"
    fi
  fi
}

outputTemplate() {
  local templateSelection
  if ! templateSelection=${DEFAULT_SEASON_NO:-$(
    assertSelection '
      Select output template season number preset
      Single season
      Multi seasons
      Custom season
      Skip
    ' --header-lines 1
  )}; then
    assertTryAgain outputTemplate
  else

    local seriesName
    if [[ ${YTD_SERIES} != 1 ]]; then
      seriesName="${SERIES}"
    else
      seriesName='%(series)s'
    fi

    local seriesSeasonNumber
    if [[ ${templateSelection} == [Ss]ingle* ]]; then
      seriesSeasonNumber='1'
    elif [[ ${templateSelection} == [Mm]ulti* ]]; then
      seriesSeasonNumber='%(season_number)1d'
    elif [[ ${templateSelection} != 'Skip' ]]; then
      assertTask 'Awaiting user input for custome season number...'
      readHeader 'Modify season number below (then press [ENTER])'
      seriesSeasonNumber=$(readPrompt '' '0')
    else
      assertMissing "Skipped output template\n"
      return
    fi

    local templateBlocks="
      ${seriesName}${NAME_SUFFIX}
      ${SEASON_PREFIX}${seriesSeasonNumber}${SEASON_SUFFIX}
      ${EPISODE_PREFIX}%(episode_number)${EPISODE_SUFFIX}
      %(episode)s.%(ext)s
    "

    local template
    template=$(
      echo "${templateBlocks}" | sed 's/^[[:space:]]*//' | tr -d '\n'
    )

    echo "-o \"${template}\"" >>"${SERIES_CONFIG}"
    assertSuccess 'Output template:' "${template}\n"
  fi
}

parsePlaylistIndex() {
  local indexFile=$1

  assertTask 'Parsing series playlist with youtube-dl...'
  assertWarning \
    'youtube-dl may take several minutes to parse long playlists'

  local format
  format=$(
    grep -E '^--format ' "${SERIES_CONFIG}" ||
      grep -E '^--format ' "${CRUNCHYROLL_CONFIG}" |
      awk '{print $2}' |
        sed -e "s/'//g" -e 's/"//g'
  )

  if [[ ${format} ]]; then
    assertSuccess 'Format:' "${format}"
  else
    assertSuccess 'Format:' "Default to 'best'"
  fi

  assertSuccess 'Cache file:' "${indexFile/#$HOME/\~}"
  assertSuccess 'Data output:' 'INDEX | SEASON_NUMBER | TITLE'

  if youtube-dl "${SERIES_URL}" \
    --config-location <(
      cat "${USER_CONFIG}" "${CRUNCHYROLL_CONFIG}" 2>/dev/null
    ) \
    --dump-json \
    --match-title '.*' \
    --ignore-errors \
    --playlist-start "${PARSE_INDEX_START}" \
    --format "${format:-best}" |
    jq --unbuffered -cr \
      '[.playlist_index,.season_number,.title] | join(" | ")' |
    tee "${indexFile}" || [[ $? == 1 ]] && [[ -s ${indexFile} ]]; then

    assertSuccess "Parsing completed\n"
  else
    assertError 'failed to parse playlist'

    local tryAgainOrSkip
    tryAgainOrSkip=$(
      assertSelection '
        Try again
        Skip
        Abort
      '
    )

    if [[ ${tryAgainOrSkip} == 'Try'* ]]; then
      echo
      parsePlaylistIndex "$@"
    elif [[ ${tryAgainOrSkip} == 'Abort' ]]; then
      assertMissing 'Aborted by user'
      exit 1
    else
      assertMissing "Skipped by user\n"
    fi
  fi
}

playlistFormat() {
  local filter
  if ! filter=$(
    assertSelection '
      Select format filter
      Japanese audio (RAW)
      English audio (RAW)
      Custome filter
      No filter
    ' --header-lines 1
  ); then
    assertTryAgain playlistFormat
  else

    local format
    if [[ ${filter} == 'Japanese'* ]]; then
      format='[format_id*=jaJP][format_id!*=hardsub]'

    elif [[ ${filter} == 'English'* ]]; then
      format='[format_id*=enUS][format_id!*=hardsub]'

    elif [[ ${filter} == 'Custome'* ]]; then
      assertTask 'Awaiting user input for format filter...'
      readHeader 'Modify format template below (then press [ENTER])'
      format=$(readPrompt '' "${FORMAT_FILTER}")

    else
      format='best'
      assertSuccess 'Format:' "Default to 'best'\n"
      return
    fi

    assertSuccess 'Format:' "${format}"
  fi

  if [[ ${format} != 'best' ]]; then
    echo "--format '${format}'" >>"${SERIES_CONFIG}"
    echo
  else
    assertSuccess \
      "No need to add this format to config file. It is used by default!\n"
  fi
}

ytdlConfOptions() {
  assertSelection '
    Select one or more youtube-dl options
    --format FORMAT
    --playlist-(start|end) NUMBER || --playlist-items ITEM_SPEC
    --output TEMPLATE
  ' --header-lines 1 -m || assertTryAgain ytdlConfOptions
}

customizeConfigFile() {
  assertTask 'Customizing config file...'

  local useConfigWizard
  useConfigWizard=$(
    assertSelection '
      Use Config Wizard
      Add youtube-dl options manually
    '
  )

  if [[ ${useConfigWizard} != *'Wizard' ]]; then
    ${EDITOR:-vi} "${SERIES_CONFIG}"

    if [[ -s ${SERIES_CONFIG} ]]; then
      assertSuccess "Customized youtube-dl options manually\n"
    else
      assertMissing "Config file is empty!\n"
    fi

    return
  fi

  local configOptions
  configOptions=$(ytdlConfOptions)

  if grep -q '^--format' <<<"${configOptions}"; then
    assertTask 'Awaiting user selection for format filter...'
    playlistFormat
  fi

  createIndexFile() {
    [[ -d ${INDEX_DIR} ]] ||
      if ! mkdir -p "${INDEX_DIR}"; then
        assertError 'could not create index directory in path:' "${INDEX_DIR}"
        exit 1
      fi

    echo "${INDEX_DIR}/$(date '+%Y-%m-%d') - ${SERIES}.txt"
  }

  selectIndexFile() {
    if ! find "${INDEX_DIR}"/*"${SERIES}"* |
      fzf --header 'Select a playlist index file' \
        --tac \
        --with-nth 7.. \
        --delimiter '/' \
        --preview 'cat {} 2>/dev/null | head -200'; then
      assertMissing 'No playlist index file was selected'
      assertTryAgain selectIndexFile
    fi
  }

  if grep -q '^--playlist' <<<"${configOptions}"; then
    local indexFile
    assertTask 'Finding local playlist index...'

    if compgen -G "${INDEX_DIR}/*${SERIES}*" >/dev/null; then
      assertSuccess "Found one or more playlist index locally\n"

      local playlistIndexPrompt
      playlistIndexPrompt=$(
        assertSelection '
          Do you want to use existing playlist index?
          Yes
          No, create a new playlist index with youtube-dl
        ' --header-lines 1
      )

      if [[ ${playlistIndexPrompt} == 'Yes' ]]; then
        assertTask 'Awaiting user selection for playlist index file...'
        indexFile=$(selectIndexFile)
        assertSuccess 'Playlist index file:' "${indexFile/#$HOME/\~}\n"
      else
        indexFile=$(createIndexFile)
        parsePlaylistIndex "${indexFile}"
      fi

    else
      assertMissing "No playlist index found locally\n"
      indexFile=$(createIndexFile)
      parsePlaylistIndex "${indexFile}"
    fi

    assertTask 'Awaiting user selection for playlist modifiers...'
    playlistSelection "${indexFile}"
  fi

  if grep -q '^--output' <<<"${configOptions}"; then
    assertTask 'Awaiting user selection for output template...'
    outputTemplate
  fi

  [[ -s ${SERIES_CONFIG} ]] && ${EDITOR:-vi} "${SERIES_CONFIG}"

  assertTask 'Saving config file...'
  if [[ -s ${SERIES_CONFIG} ]]; then
    assertSuccess 'Config file:' "${SERIES_CONFIG/#$HOME/\~}\n"
  else
    assertMissing "Config file is empty!\n"
  fi
}

getConfigFilename() {
  readHeader \
    'Append text to series title or leave it as is (then press [ENTER])'

  local textInput
  textInput=$(readPrompt "${SERIES}")

  local confFilename
  confFilename=$(safeFilename <<<"${SERIES}${textInput}").conf

  while [[ -f ${CONFIG_DIR}/${confFilename} ]]; do
    assertWarning 'Filename already exists'

    local conflictPrompt
    conflictPrompt=$(
      assertSelection '
        Would you like to try a different filename?
        Yes
        No, use existing config file
        Abort
      ' --header-lines 1
    )

    if [[ ${conflictPrompt} == 'Yes' ]]; then
      textInput=$(readPrompt "${SERIES}" "${textInput}")
      confFilename=$(safeFilename <<<"${SERIES}${textInput}").conf
    elif [[ ${conflictPrompt} == 'No'* ]]; then
      break
    else
      assertMissing 'Aborted by user'
      exit 1
    fi

  done

  local confirmConfFile
  confirmConfFile=$(
    assertSelection "
      Confirm config filename?
      $(assertSuccess "Config filename: '${confFilename}'")
      Yes, continue
      No, rename it
    " --header-lines 2
  )

  if [[ ${confirmConfFile} == 'Yes'* ]]; then
    SERIES_CONFIG="${CONFIG_DIR}/${confFilename}"
    assertSuccess 'Config filename:' "${confFilename}\n"
  else
    getConfigFilename
  fi
}

createConfigFile() {
  assertTask 'Awaiting user input for config filename...'
  getConfigFilename
  customizeConfigFile
}

selectConfigFile() {
  if ! SERIES_CONFIG=$(
    find "${CONFIG_DIR}/${SERIES}"* |
      fzf --header 'Select a config file' \
        --with-nth 6.. \
        --delimiter '/' \
        --preview 'cat {} 2>/dev/null | head -200'
  ); then
    assertMissing 'No config file was selected'
    assertTryAgain selectConfigFile
  else

    local confFilename
    confFilename=$(basename "${SERIES_CONFIG}")

    local isCustom
    isCustom=$(
      assertSelection "
        Do you want to customize this config file?
        $(assertSuccess "Config file: '${confFilename}'")
        No
        Yes
      " --header-lines 2 \
        --preview "cat \"${SERIES_CONFIG}\" 2>/dev/null | head -200"
    )

    if [[ ${isCustom} == 'Yes' ]]; then
      assertSuccess 'Config file:' "${SERIES_CONFIG/#$HOME/\~}\n"
      customizeConfigFile
    else
      if [[ -s ${SERIES_CONFIG} ]]; then
        assertSuccess 'Config file:' "${SERIES_CONFIG/#$HOME/\~}\n"
      else
        assertMissing "Config file is empty!\n"
      fi
    fi
  fi
}

preSelectedSeries() {
  assertTask 'Parsing series title with youtube-dl...'

  local json
  json=$(
    youtube-dl "${SERIES_URL}" \
      --config-location <(
        cat "${USER_CONFIG}" "${CRUNCHYROLL_CONFIG}" 2>/dev/null
      ) \
      --dump-json \
      --max-download 1 \
      --all-formats \
      --match-title '.*' \
      --no-warnings \
      --ignore-errors
  )

  if [[ ${json} ]]; then
    SERIES=$(jq -cr '.series' <<<"${json}" | safeFilename)
    EXTRACTOR=$(jq -cr '.extractor' <<<"${json}")
  fi

  if [[ ${SERIES} ]]; then
    if [[ ! ${EXTRACTOR} ]]; then
      assertError 'could not parse extractor name!'
      exit 1
    fi
    assertSuccess 'Exractor:' "${EXTRACTOR}"
    assertSuccess 'Series:' "${SERIES}"
    return
  fi

  assertError 'could not parse series title!'
  exit 1
}

addToWatchList() {
  if ! grep -qF "${SERIES}" "${LIST_JSON}" 2>/dev/null; then
    local confirmAddToWatchList
    confirmAddToWatchList=$(
      assertSelection '
        Do you want to add this series to watching list?
        Yes
        No
      ' --header-lines 1
    )

    if [[ ${confirmAddToWatchList} == 'Yes' ]]; then
      [[ -s $LIST_JSON ]] || echo '{ "watching": [] }' >"${LIST_JSON}"
      local list
      list=$(cat "${LIST_JSON}")

      jq \
        --arg url "${SERIES_URL}" \
        --arg title "${SERIES}" \
        --arg extractor "${EXTRACTOR}" \
        '.watching += [{ $url, $title, $extractor }]' <<<"${list}" \
        >"${LIST_JSON}"

      assertSuccess 'Series added to watching list'
      assertSuccess 'List path:' "${LIST_JSON/#$HOME/\~}\n"
    else
      echo
      return
    fi

  else
    assertSuccess "Series is in watching list"
    assertSuccess 'List path:' "${LIST_JSON/#$HOME/\~}\n"
  fi
}

findConfig() {
  assertTask 'Finding custom config file for this series...'
  if compgen -G "${CONFIG_DIR}/${SERIES}*" >/dev/null; then
    assertSuccess "Found one or more youtube-dl config files for this series"
    return 0
  else
    assertMissing "No config file found\n"
    return 1
  fi
}

processConfig() {
  if findConfig; then
    local useExistingConf
    useExistingConf=$(
      assertSelection '
        Select a config file
        Create a new config file
        Skip
      '
    )

    if [[ ${useExistingConf} == 'Select'* ]]; then
      echo
      assertTask 'Awaiting user selection for config file...'
      selectConfigFile
    elif [[ ${useExistingConf} == 'Create'* ]]; then
      echo
      createConfigFile
    else
      assertMissing "No config file selected for this series!\n"
    fi

  else
    local createNewConf
    createNewConf=$(
      assertSelection '
        Do you want to create a custom youtube-dl config file for this series?
        Yes
        No
      ' --header-lines 1
    )
    if [[ ${createNewConf} == 'Yes' ]]; then
      createConfigFile
    fi
  fi
}

stream() {
  assertTask 'Processing stream with MPV...'
  local mpvConf="${HOME}/.config/mpv/mpv.conf"

  if [[ ! -f ${mpvConf} ]]; then
    assertMissing "MPV config file not found!\n"
    assertTask 'Creating MPV config templates...'
    mkdir -p ~/.config/mpv
    cp -ir /usr/local/share/doc/mpv/ ~/.config/mpv/
    assertSuccess 'MPV config file:' "${mpvConf/#$HOME/\~}"
  fi

  local mpvArgs=(
    "--ytdl-raw-options-append=config-location=$1"
    "${@:2}"
  )

  if grep -qxF '[crunchyroll]' "${mpvConf}"; then
    assertSuccess 'Crunchyroll profile was found in MPV config file'
    mpvArgs=('--profile=crunchyroll' "${mpvArgs[@]}")
  fi

  local playUnicode="${BLUE_TXT}\u25B6${RESET}"
  echo -e "${playUnicode} Opening '${SERIES}' stream..."
  mpv "${mpvArgs[@]}"
}

# shellcheck disable=SC2016
#! Don't replace `uniq` command with `sort`.
#* It breaks renameSubtitles function for reversed playlist.
getVideoID() {
  local pattern='/^\[crunchyroll\]/{a=$0}/'"${*:-1}"'/{print a"\n"$0}'
  awk "${@:1:$#-1}" "${pattern}" "${DL_LOG}" |
    grep -F '[crunchyroll]' |
    awk '{print $1, $2}' |
    sed 's/[][]//g;s/://' |
    uniq
}

archiveVideoID() {
  local archivePath=$1
  local archiveExtra=$2

  if grep -qF 'requested format not available' "${DL_LOG}"; then
    echo
    assertTask 'Adding video-IDs with no matching format to archive...'
    local formatNotAvailableIDs
    formatNotAvailableIDs=$(getVideoID 'format not available')

    if [[ ${formatNotAvailableIDs} ]]; then
      echo "${formatNotAvailableIDs}" >>"${archiveExtra}" &&
        assertSuccess 'IDs saved to:' "${archiveExtra/#$HOME/\~}"

      echo "${formatNotAvailableIDs}" >>"${archivePath}" &&
        assertSuccess 'IDs saved to:' "${archivePath/#$HOME/\~}"
    else
      assertError 'could not parse IDs from download log file'
      exit 1
    fi

  fi
}

renameSubtitles() {
  if [[ ${ISO_SUB} != 0 ]]; then
    while pgrep -qP "$1"; do
      sleep 3

      local videoID
      local lastVideoID
      lastVideoID=$(getVideoID '[Vv]ideo subtitle' | sed '$!d')
      [[ ${lastVideoID} != "${videoID}" ]] || continue
      sleep 2

      for file in *[A-Z][A-Z].ass; do
        echo \
          "${CYAN_TXT}[${MAGENTA_BOLD_TXT}" \
          "rename subtitle to ISO 639-1" \
          "${CYAN_TXT}]${RESET}" \
          "$(mv -v -- "${file}" "${file%[A-Z][A-Z].ass}.ass")"
      done 2>/dev/null && videoID="${lastVideoID}"
    done
  fi
}

processFragmentedDownload() {
  local fragmentedDownload=$1
  local patterns=$2
  local archivePath=$3

  local line
  while IFS= read -r line; do
    if [[ $line != *'mp4'* ]]; then
      assertError 'invalid list of fragmented files!'
      exit 1
    fi
  done <<<"${fragmentedDownload}"

  local filesToDelete
  if [[ ${DELETE_FRAG} != 0 ]]; then
    filesToDelete=$(find -- "${fragmentedDownload%mp4}"*mp4* 2>/dev/null)
  else
    local header='Found more than one file. Select one or more files to delete:'
    filesToDelete=$(
      find -- "${fragmentedDownload%mp4}"*mp4* 2>/dev/null |
        fzf -m --no-select-1 --header "${header}"
    )
  fi

  if [[ ${filesToDelete} ]]; then
    local pluralFile
    pluralFile=$(isPlural "${filesToDelete}")
    assertTask "Deleting fragmented file${pluralFile} from disk..."
    local foundPattern
    foundPattern=$(grep -oE "${patterns}" "${DL_LOG}" | sort --unique)

    if [[ ${foundPattern} ]]; then
      local pattern
      while IFS= read -r pattern; do
        assertMissing 'Detected error:' "${pattern}"
      done <<<"${foundPattern}"
    fi

    local filesCount
    filesCount=$(wc -l <<<"${filesToDelete}")

    local deleteFragmentedFiles
    [[ ${DELETE_FRAG} == 0 ]] && deleteFragmentedFiles=$(
      assertSelection "
        Confirm permanently deleting the following file${pluralFile} from disk!
        ${RED_BOLD_TXT}${filesToDelete}${RESET}
        Yes
        No
      " --header-lines "$((filesCount + 1))"
    )

    local file
    if [[ ${deleteFragmentedFiles} == 'Yes' || ${DELETE_FRAG} != 0 ]]; then
      while IFS= read -r file; do
        rm -f -- "${PWD}/${file}" 2>/dev/null

        if [[ ! -f ${file} ]]; then
          assertSuccess 'Deleted:' "${file}"
        else
          assertMissing 'Could not delete:' "${file}"
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
    fragmentedID=$(getVideoID "${patterns}")

    if [[ ${fragmentedID} ]]; then
      if grep -qxF "${fragmentedID}" "${archivePath}" 2>/dev/null; then
        assertSuccess 'Backup:' "$(cp -v -- "${archivePath/#$HOME/\~}"{,.bak})"
        sed -ni "/^${fragmentedID}$/!p" "${archivePath}"

        if ! grep -qxF "${fragmentedID}" "${archivePath}"; then
          assertSuccess 'Removed ID:' "${fragmentedID}"
        else
          assertMissing 'Could not remove ID:' "${fragmentedID}"
          exit 1
        fi

      else
        assertSuccess 'No fragemented video-IDs found in archive'
      fi

    else
      assertError 'could not parse fragmented video-IDs'
      exit 1
    fi

  else
    assertMissing 'Canceled by user'
  fi
}

fragmentMonitor() {
  local patterns=$1
  local downloadPID=$2
  local ytdArgs=$3

  until grep -qE "${patterns}" "${DL_LOG}"; do
    sleep 1

    if ! pgrep -qP "${downloadPID}"; then
      #! This check is important!
      # In case youtube-dl was terminated before an error pattern was catched.
      grep -qE "${patterns}" "${DL_LOG}" && break
      return 0
    fi
  done

  pkill -f -- "youtube-dl ${ytdArgs}"
  while pgrep -qf -- "youtube-dl ${ytdArgs}"; do
    sleep 1
  done

  echo
  assertError 'fragment error detected!'
  echo
  assertTask 'Terminating download process...'
  kill -SIGTERM -- -"${downloadPID}" &>/dev/null

  while pgrep -qP "${downloadPID}"; do
    sleep 1
  done

  assertSuccess "Download process has been terminated\n"
  return 1
}

download() {
  if [[ ${DOWNLOAD_DIR} || ${MAKE_SUB_DIR} != 0 ]]; then
    assertTask 'Changing directory...'

    [[ ${DOWNLOAD_DIR} ]] && if ! cd "${DOWNLOAD_DIR}"; then
      assertError 'could not change to Clanime Downloads directory'
      exit 1
    fi

    if [[ ${MAKE_SUB_DIR} != 0 ]]; then
      [[ -d ${SERIES} ]] || mkdir "${SERIES}"
      if ! cd "${SERIES}"; then
        assertError 'could not change to series directory'
        exit 1
      fi
    fi

    assertSuccess 'Download directory:' "${PWD/#$HOME/\~}\n"
  fi

  #* Keep the following archive variables here.
  #* They must refer to the active directory
  local archivePath="${PWD}/archive.txt"
  local archiveDir
  archiveDir="$(dirname "${archivePath}")"
  local archiveExtra="${archivePath%.txt}-extra.txt"
  # --***-- #

  assertTask 'Downloading with youtube-dl...'
  assertSuccess 'Download log file:' "${DL_LOG/#$HOME/\~}"

  if [[ -w ${archiveDir} ]]; then
    if grep -q '.txt$' <<<"${archivePath}"; then
      assertSuccess 'Download archive:' "${archivePath/#$HOME/\~}"
    else
      assertMissing 'Download archive path:' "${archivePath/#$HOME/\~}"
      assertError "download archive file extension must be '.txt'"
      exit 1
    fi
  else
    assertMissing 'Download archive path:' "${archivePath/#$HOME/\~}"
    assertError 'invalid download archive path.' \
      'Make sure to set a valid path with writting permission!!!'
    exit 1
  fi

  local ytdArgs=(
    '--config-location' "$1"
    '--download-archive' "${archivePath}"
    "${@:2}"
  )

  [[ ! $* =~ '--autonumber-start ' ]] &&
    if grep -qF '%(autonumber)' "$1" 2>/dev/null; then
      assertError 'you are using "autonumber" in filename output.' \
        'Pass the next episode number with "--autonumber-start" option.'
      exit 1
    fi

  youtubeDl() {
    #! Keep the following command inside this function!
    #* Otherwise, user won't be able to interrupt download process with CTL+C.
    script -q "${DL_LOG}" youtube-dl "${ytdArgs[@]}"
  }

  local patterns
  patterns=$(trimWhiteSpace "${YTD_ERRORS}" | paste -sd '|' -)

  for retry in {1..11}; do
    youtubeDl &
    local youtubeDLPID=$!

    until pgrep -qf -- 'youtube-dl' "${ytdArgs[@]}"; do
      echo -ne \
        "${CYAN_TXT}[${MAGENTA_BOLD_TXT}" \
        'sleeping' \
        "${CYAN_TXT}]${RESET}" \
        'Waiting for youtube-dl process... \r'
      sleep 1
      pgrep -qP "${youtubeDLPID}" || break
    done

    renameSubtitles "${youtubeDLPID}" &
    local renameSubtitlesPID=$!

    if ! fragmentMonitor \
      "${patterns}" "${youtubeDLPID}" "${ytdArgs[@]}"; then
      local fragmentedDownload
      fragmentedDownload=$(
        awk \
          '/^\[download\] Destination/{a=$0}/'"${patterns}"'/{print a"\n"$0}' \
          "${DL_LOG}" |
          grep -F '[download] Destination' |
          awk -F ': ' '{print $2}' |
          sort --unique |
          tr -d '\r'
      )

      processFragmentedDownload \
        "${fragmentedDownload}" "${patterns}" "${archivePath}"
    fi

    wait "${youtubeDLPID}" "${renameSubtitlesPID}"
    archiveVideoID "${archivePath}" "${archiveExtra}"
    [[ ! ${fragmentedDownload} ]] && break
    unset fragmentedDownload
    unset youtubeDLPID
    unset renameSubtitlesPID

    [[ $* =~ '--autonumber-start ' ]] && break

    if [[ ${retry} -gt 10 ]]; then
      assertError 'maximum retry attempts reached. Try again later!'
      exit 1
    fi

    echo
    assertTask "Retrying attempt ${retry} of 10..."

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
  done
}

downloadOrStream() {
  streamOrDownload=${1:-$(
    assertSelection '
      Stream
      Download
    '
  )}

  local concatConf
  concatConf=$(mktemp -t clanime.conf)
  cat "${USER_CONFIG}" "${CRUNCHYROLL_CONFIG}" "${SERIES_CONFIG}" \
    >"${concatConf}" 2>/dev/null

  if [[ ${streamOrDownload} == 'Stream' ]]; then
    if [[ $* =~ '--playlist=' ]]; then
      stream "${concatConf}" "${@:2}"
    else
      stream "${concatConf}" "${@:2}" -- "${SERIES_URL}"
    fi

  elif [[ ${streamOrDownload} == 'Download' ]]; then
    if [[ $* =~ ('-a '|'--batch-file ') ]]; then
      download "${concatConf}" "${@:2}"
    else
      download "${concatConf}" "${@:2}" "${SERIES_URL}"
    fi

  else
    assertTryAgain downloadOrStream "$@"
  fi

  rm -f -- "${concatConf}" 2>/dev/null
}

selectFromWatchList() {
  local list
  list=$(cat "${LIST_JSON}")

  SERIES=$(
    jq -cr '.watching[].title' <<<"${list}" | fzf
  )

  SERIES_URL=$(
    jq --arg title "${SERIES}" -cr \
      '.watching[] | select(.title==$title).url' <<<"${list}"
  )

  if [[ ${SERIES} && ${SERIES_URL} ]]; then
    assertSuccess "Series: ${SERIES}"
    assertSuccess 'URL:' "${SERIES_URL}\n"
  else
    assertTryAgain selectFromWatchList
  fi
}

browse() {
  if [[ ! $1 ]]; then
    exit 1
  else
    assertTask 'Awaiting user selection from watching list...'
    selectFromWatchList
  fi
}

configProcessOptions() {
  local processOption
  processOption=$(
    assertSelection "
      Process configurations of a series from...
      ${BROWSE_LIST}
    " --header-lines 1
  )

  assertSuccess "Process series config from: ${processOption}\n"
  browse "$(awk '{print $1}' <<<"${processOption}")"

  while true; do
    processConfig

    local repeat
    repeat=$(
      assertSelection '
        Process another config file for selected series
        Cancel
      '
    )

    if [[ ${repeat} != 'Process'* ]]; then
      assertSuccess 'Done'
      break
    fi
  done
}

#* --{ Main workflow }-- *#
while [[ -n $1 ]]; do
  case "$1" in
  st | stream)
    if [[ ! ${SUB_COMMAND} ]]; then
      readonly SUB_COMMAND='Stream'
    else
      assertError 'subcommand conflict!' \
        'Pass either stream (st) or download (dl) as a subcommand.'
      exit 1
    fi
    ;;

  dl | download)
    if [[ ! ${SUB_COMMAND} ]]; then
      readonly SUB_COMMAND='Download'
    else
      assertError 'subcommand conflict!' \
        'Pass either stream (st) or download (dl) as a subcommand.'
      exit 1
    fi
    ;;

  --no-delete)
    readonly DELETE_FRAG=0
    ;;

  --here)
    readonly DOWNLOAD_DIR=
    ;;

  --no-sub-dir)
    readonly MAKE_SUB_DIR=0
    ;;

  --no-iso-sub)
    readonly ISO_SUB=0
    ;;

  --ytd-series)
    readonly YTD_SERIES=1
    ;;

  --season-template)
    if [[ $2 =~ ([Ss]ingle|[Mm]ulti|[Cc]ustom) ]]; then
      readonly DEFAULT_SEASON_NO=$2
      shift
    else
      assertError 'invalid season-template value!' \
        'Valid values: single, multi, or custom.'
      exit 1
    fi
    ;;

  --parse-index)
    if [[ $2 == +([0-9]) && (($2 -gt 0)) ]]; then
      readonly PARSE_INDEX_START=$2
      shift
    else
      assertError 'invalid parse-index value!' \
        'It must be an integer number that is greater than 0.'
      exit 1
    fi
    ;;

  --)
    ARGS=("${@:2}")
    for index in "${!ARGS[@]}"; do
      [[ ${ARGS[${index}]} ]] || unset "ARGS[${index}]"
    done
    readonly ARGS
    shift
    break
    ;;

  *)
    if [[ $1 == ${BASE_URL}* ]]; then
      readonly SERIES_URL="$1"
    elif [[ $1 == 'http'* ]]; then
      assertError 'invalid crunchyroll URL:' "$1"
      exit 1
    else
      assertError 'invalid option:' "$1"
      exit 1
    fi
    ;;
  esac
  shift
done

[[ ${DOWNLOAD_DIR} ]] && if [[ ! -d ${DOWNLOAD_DIR} ]]; then
  assertMissing 'Clanime Downloads directory:' "${DOWNLOAD_DIR}"
  assertError 'Clanime Downloads directory not found'
  exit 1
fi

if [[ ! -d ${CONFIG_DIR} ]]; then
  assertTask "Creating 'config' directory..."
  mkdir -p "${CONFIG_DIR}"
  assertSuccess 'Config directory:' "${CONFIG_DIR}\n"
fi

if [[ ! -d ${CACHE_DIR} ]]; then
  assertTask "Creating 'cache' directory..."
  mkdir -p "${CACHE_DIR}"
  assertSuccess 'Cache directory:' "${CACHE_DIR}\n"
fi

if [[ ${SERIES_URL} ]]; then
  readonly MAIN="${SERIES_URL}"

elif [[ ! -s ${LIST_JSON} ]]; then
  assertMissing 'Nothing is stored in your local list, yet!' \
    'Provide at least one URL.'

else
  assertTask 'Awaiting user selection from main options...'
  readonly MAIN=$(
    assertSelection "
      ${BROWSE_LIST}
      Process Configurations ${YELLOW_BOLD_TXT}ONLY${RESET}
    "
  )
fi

if [[ ! ${MAIN} ]]; then
  exit 1

elif [[ ${MAIN} == ${BASE_URL}* ]]; then
  preSelectedSeries
  addToWatchList
  processConfig
  downloadOrStream "${SUB_COMMAND}" "${ARGS[@]}"

elif [[ ${MAIN} != 'Process'* ]]; then
  assertSuccess "Browse: ${MAIN}\n"
  browse "$(awk '{print $1}' <<<"${MAIN}")"
  processConfig
  downloadOrStream "${SUB_COMMAND}" "${ARGS[@]}"

else
  configProcessOptions
fi

exit
