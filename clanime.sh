#!/usr/bin/env bash

set -o pipefail

#* --{ Settings with Environment Variables }-- *#
CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME}/.config}
CONFIG_DIR=${CONFIG_HOME}/clanime
USER_CONFIG=${YTDL_USER_CONFIG:-${CONFIG_HOME}/youtube-dl/config}
CRUNCHYROLL_CONFIG=${CRUNCHYROLL_CONFIG:-${CONFIG_DIR}/crunchyroll.conf}
LIST_JSON="${CONFIG_DIR}/list.json"
SERIES_DIR="${SERIES_DIR:-1}"
ANIME_DIR="${ANIME_DIR}"

## Playlist index options
PARSE_INDEX_START="${PARSE_INDEX_START:-1}"

## Format filer options
FORMAT_FILTER="${FORMAT_FILTER:-[format_id*=jaJP][format_id!*=hardsub]}"

## Output template options
SAFE_SERIES="${ANIME_SAFE_SERIES_NAME}"
NAME_SUFFIX="${ANIME_SERIES_NAME_SUFFIX:- - }"
SEASON_PREFIX="${ANIME_SERIES_SEASON_PREFIX}"
SEASON_SUFFIX="${ANIME_SERIES_SEASON_SUFFIX:-x}"
EPISODE_PREFIX="${ANIME_SERIES_EPISODE_PREFIX}"
EPISODE_SUFFIX="${ANIME_SERIES_EPISODE_SUFFIX:-03d - }"
OUTPUT_TEMPLATE="${ANIME_OUTPUT_TEMPLATE}"

## Renaming subtitles to ISO 639-1 code format option
ISO_SUB="${ANIME_ISO_SUB}"

#* End of Settings *#

baseURL='https://www.crunchyroll.com'
mainURL="${baseURL}/videos/anime"

seasonQuery='[href^="#/videos/anime/seasons/"]::attr(title)'
playlistQuery='a.portrait-element::attr(href)'
titlesQuery='a.portrait-element > span > img::attr(alt)'

# Font styling and colors
boldText=$'\e[1m'
greenBoldText=$'\e[1;32m'
redBoldText=$'\e[1;31m'
blueText=$'\e[34m'
redUnderlinedText=$'\e[4;31m'
cyanText=$'\e[36m'
magentaBoldText=$'\e[1;35m'
magentaBgBlackText=$'\e[45;30m'
yellowBoldText=$'\e[1;33m'
reset=$'\e[0m'

# shellcheck disable=SC2034
FZF_DEFAULT_OPTS="
  --bind J:down,K:up,ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all \
  --reverse \
  --ansi \
  --no-multi \
  --height 20% \
  --min-height 15 \
  --border \
  --select-1"

assertTask() {
  echo -e "${blueText}==>${reset} ${boldText}$*${reset}"
}

assertSuccess() {
  checkMark="${greenBoldText}\u2714${reset}"
  echo -e "${checkMark} ${boldText}$1${reset}" "${@:2}"
}

assertMissing() {
  missingMark="${redBoldText}\u2718${reset}"
  echo -e "${missingMark} ${boldText}$1${reset}" "${@:2}"
}

assertWarning() {
  echo -e "${yellowBoldText}WARNING${reset}${boldText}: $*${reset}"
}

assertError() {
  echo -n "${redUnderlinedText}Error${reset}: " >&2

  if [[ $# == 0 ]]; then
    echo 'Something wrong happened!' >&2
  else
    echo "$*" >&2
  fi
}

trimWhiteSpace() {
  echo -e "$1" | grep "\S" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

assertSelection() {
  trimWhiteSpace "$1" | fzf "${@:2}"
}

assertTryAgain() {
  tryAgain=$(
    assertSelection '
      Would you like to try again?
      Yes
      Abort
    ' --header-lines 1
  )
  if [[ ${tryAgain} == Yes ]]; then
    "$@"
  else
    assertError 'Aborted by user'
    exit 1
  fi
}

downloadPage() {
  wget -qO- "$1" --max-redirect 0 --level 1
}

safeFilename() {
  perl -pe "s/^\W+|(?!(?:COM[0-9]|CON|LPT[0-9]|NUL|PRN|AUX|com[0-9]|con|lpt[0-9]|nul|prn|aux)|[\s\.])[\/:*\"?<>|~\\\\;]{1,254}/_/g"
}

readHeader() {
  echo "${magentaBgBlackText} $1 ${reset}"
}

readPrompt() {
  prefix=$1
  suffix=$2
  IFS= read \
    -erp "${cyanText}Text input ${magentaBoldText}->${reset} ${prefix}" \
    -i "${suffix}" textInput
}

selectModifiers() {
  if ! playlistModifier=$(
    assertSelection "
      Select $2
      ${playlistModifiers}
    " -m "$1" --header-lines 1
  ); then

    assertError 'No modifier selected!'
    assertTryAgain selectModifiers "$@"
  elif grep -qE '^--playlist-items' <<<"${playlistModifier}" &&
    grep -qE '^--playlist-(start|end)' <<<"${playlistModifier}"; then
    assertError 'Do not use --playlist-item with --playlist-(start|end)'
    assertTryAgain selectModifiers "$@"
  fi
}

confirmModifiers() {
  selectModifiers "$@"
  modifiersCount=$(wc -l <<<"${playlistModifier}")
  if ! confirmModifiers=$(
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

    if [[ ${confirmModifiers} == Yes* ]]; then
      assertSuccess 'Playlist modifiers:' "\n${playlistModifier}\n"
      echo "${playlistModifier}" >>"${confFile}"
    elif [[ ${confirmModifiers} == No* ]]; then
      playlistSelection
    else
      assertMissing "Skipped by user\n"
    fi
  fi
}

selectPlaylistIndex() {
  assertTask 'Awaiting user selection for playlist index file...'
  if ! playlistIndex=$(
    find "${CONFIG_DIR}"/playlist-index/*"${seriesTitle}"* |
      fzf --header 'Select a playlist index file' \
        --tac \
        --with-nth 7.. \
        --delimiter '/' \
        --preview 'cat {} 2>/dev/null | head -200'
  ); then
    assertError 'No playlist index file was selected'
    assertTryAgain selectPlaylistIndex
  fi

  assertSuccess "Playlist index file:" "${playlistIndex/#$HOME/\~}\n"
}

playlistSelection() {
  if [[ ! -s ${playlistIndex} ]]; then
    assertMissing "No items in playlist index file\n"
    return
  fi

  fzfHeader='Select one or two items from the list'
  if ! playlistItems=$(
    fzf --exact --no-sort -m 2 --header "${fzfHeader}" <"${playlistIndex}" |
      awk '{print $1}'
  ); then

    tryAgain=$(
      assertSelection '
        Would you like to try again?
        Yes
        No, continue without modifiers
        Abort
      ' --header-lines 1
    )

    if [[ ${tryAgain} == Yes ]]; then
      playlistSelection
    elif [[ ${tryAgain} == No* ]]; then
      assertSuccess "Continue without modifiers\n"
    else
      assertError 'Aborted by user'
      exit 1
    fi

  else
    playlistModifiers=$(
      awk '
        END{print "--playlist-end "$1}
        NR==1{print "--playlist-start "$1}
      ' <<<"${playlistItems}"
    )

    if [[ $(awk '{print NR}' <<<"${playlistItems}") == 1 ]]; then
      confirmModifiers 1 'a modifier'
    else
      range=$(paste -sd "-" - <<<"${playlistItems}")
      playlistModifiers="${playlistModifiers}\n--playlist-items ${range}"
      confirmModifiers 2 'one or two modifiers'
    fi
  fi
}

outputTemplate() {
  if ! templateSelection=${OUTPUT_TEMPLATE:-$(
    assertSelection '
      Select output template season number preset
      Single season
      Multi seasons
      Custome season
      Skip
    ' --header-lines 1
  )}; then
    assertTryAgain outputTemplate
  else

    if [[ ${SAFE_SERIES} != 0 ]]; then
      seriesName="${seriesTitle}"
    else
      seriesName='%(series)s'
    fi

    if [[ ${templateSelection} == Single* ]]; then
      seriesSeasonNumber='1'
    elif [[ ${templateSelection} == Multi* ]]; then
      seriesSeasonNumber='%(season_number)1d'
    elif [[ ${templateSelection} != Skip ]]; then
      assertTask 'Awaiting user input for custome season number...'
      readHeader 'Modify season number below (then press [ENTER])'
      readPrompt '' '0'
      seriesSeasonNumber=${textInput}
    else
      assertMissing "Skipped output template\n"
      return
    fi

    template="${seriesName}${NAME_SUFFIX}${SEASON_PREFIX}${seriesSeasonNumber}${SEASON_SUFFIX}${EPISODE_PREFIX}%(episode_number)${EPISODE_SUFFIX}%(episode)s.%(ext)s"
    echo "-o '${template}'" >>"${confFile}"
    assertSuccess 'Output template:' "${template}\n"
  fi
}

playlistFilter() {
  if ! filter=$(
    assertSelection '
      Select format filter
      Japanese audio (RAW)
      English audio (RAW)
      Custome filter
      No filter
    ' --header-lines 1
  ); then
    assertTryAgain playlistFilter
  else

    if [[ ${filter} == Japanese* ]]; then
      format='[format_id*=jaJP][format_id!*=hardsub]'
    elif [[ ${filter} == English* ]]; then
      format='[format_id*=enUS][format_id!*=hardsub]'
    elif [[ ${filter} == Custome* ]]; then
      assertTask 'Awaiting user input for format filter...'
      readHeader 'Modify format template below (then press [ENTER])'
      readPrompt '' "${FORMAT_FILTER}"
      format=${textInput}
    else
      format='best'
      assertSuccess 'Format:' "Default to 'best'"
      return
    fi

    assertSuccess 'Format:' "${format}"
  fi
}

parsePlaylistIndex() {
  [[ -d ${CONFIG_DIR}/playlist-index ]] ||
    mkdir -p "${CONFIG_DIR}/playlist-index"

  if [[ ${format} == best ]]; then
    assertSuccess 'Format:' "Default to 'best'"
  elif [[ ${format} ]]; then
    assertSuccess 'Format:' "${format}"
  else
    playlistFilter
  fi

  playlistIndexDIR="${CONFIG_DIR}/playlist-index"
  playlistIndex="${playlistIndexDIR}/$(date '+%Y-%m-%d') - ${seriesTitle}.txt"
  assertSuccess 'Cache file:' "${playlistIndex/#$HOME/\~}"
  assertSuccess 'Data output:' 'INDEX | SEASON_NUMBER | TITLE'

  if youtube-dl "${seriesURL}" \
    --config-location <(
      cat "${USER_CONFIG}" "${CRUNCHYROLL_CONFIG}" 2>/dev/null
    ) \
    --dump-json \
    --ignore-errors \
    --playlist-start "${PARSE_INDEX_START}" \
    --format "${format:-best}" |
    jq --unbuffered -cr \
      '[.playlist_index,.season_number,.title] | join(" | ")' |
    tee "${playlistIndex}" || [[ $? == 1 ]] && [[ -s ${playlistIndex} ]]; then

    assertSuccess "Parsing completed\n"
  else
    assertError 'Failed to parse playlist'
    tryAgainOrSkip=$(
      assertSelection "
        Try again
        Skip
        Abort
      "
    )

    if [[ ${tryAgainOrSkip} == Try* ]]; then
      parsePlaylistIndex
    elif [[ ${tryAgainOrSkip} == Abort ]]; then
      assertError 'Aborted by user'
      exit 1
    else
      assertMissing "Skipped by user\n"
    fi
  fi
}

ytdlConfOptions() {
  configOptions=$(
    assertSelection "
      Select one or more youtube-dl options
      --format FORMAT
      --playlist-(start|end) NUMBER || --playlist-items ITEM_SPEC
      --output TEMPLATE
    " --header-lines 1 -m
  ) || assertTryAgain ytdlConfOptions
}

customizeConfigFile() {
  assertTask 'Customizing config file...'
  useConfigWizard=$(
    assertSelection "
      Use Config Wizard
      Add youtube-dl options manually
    "
  )

  if [[ ${useConfigWizard} != *Wizard ]]; then
    ${EDITOR:-vi} "${confFile}"

    if [[ -s ${confFile} ]]; then
      assertSuccess "Customized youtube-dl options manually\n"
    else
      assertMissing "No youtube-dl options found!\n"
    fi

    return
  fi

  ytdlConfOptions
  if grep -qE '^--format' <<<"${configOptions}"; then
    assertTask 'Awaiting user selection for format filter...'
    playlistFilter
    if [[ ${format} != best ]]; then
      echo "--format '${format}'" >>"${confFile}"
      echo
    else
      assertSuccess \
        "No need to add this format to config file. It is used by default!\n"
    fi
  fi

  if grep -qE '^--playlist' <<<"${configOptions}"; then
    assertTask 'Finding local playlist index...'
    playlistIndexQuery="${CONFIG_DIR}/playlist-index/*${seriesTitle}*"
    if compgen -G "${playlistIndexQuery}" >/dev/null; then
      assertSuccess "Found one or more playlist index locally\n"

      playlistIndexPrompt=$(
        assertSelection "
          Do you want to use existing playlist index?
          Yes
          No, create a new playlist index with youtube-dl
        " --header-lines 1
      )

      if [[ ${playlistIndexPrompt} == Yes ]]; then
        selectPlaylistIndex
      else
        assertTask 'Parsing series playlist with youtube-dl...'
        assertWarning \
          'youtube-dl may take several minutes to parse long playlists'
        parsePlaylistIndex
      fi

    else
      assertMissing "No playlist index found locally\n"
      assertTask 'Parsing series playlist with youtube-dl...'
      parsePlaylistIndex
    fi

    assertTask 'Awaiting user selection for playlist modifiers...'
    playlistSelection
  fi

  if grep -qE '^--output' <<<"${configOptions}"; then
    assertTask 'Awaiting user selection for output template...'
    outputTemplate
  fi

  [[ -s ${confFile} ]] && ${EDITOR:-vi} "${confFile}"

  assertTask 'Saving config file...'
  if [[ -s ${confFile} ]]; then
    configFound=true
    assertSuccess "Config file:" "${confFile/#$HOME/\~}\n"
  else
    assertMissing "No youtube-dl options found!\n"
  fi
}

getConfigFilename() {
  readHeader \
    "Append text to series title or leave it as is (then press [ENTER])"
  readPrompt "${seriesTitle}"
  confFilename=$(safeFilename <<<"${seriesTitle}${textInput}").conf

  while [[ -f ${CONFIG_DIR}/${confFilename} ]]; do
    assertWarning 'A file with the same name already exists'
    conflictPrompt=$(
      assertSelection '
        Would you like to try a different filename?
        Yes
        No, use existing config file
        Abort
      ' --header-lines 1
    )

    if [[ ${conflictPrompt} == Yes ]]; then
      readPrompt "${seriesTitle}" "${textInput}"
      confFilename=$(safeFilename <<<"${seriesTitle}${textInput}").conf
    elif [[ ${conflictPrompt} == No* ]]; then
      break
    else
      assertError 'Aborted by user'
      exit 1
    fi

  done

  confirmConfFile=$(
    assertSelection "
      Confirm config filename?
      $(assertSuccess "Config filename: '${confFilename}'")
      Yes, continue
      No, rename it
    " --header-lines 2
  )

  if [[ ${confirmConfFile} == Yes* ]]; then
    confFile="${CONFIG_DIR}/${confFilename}"
    assertSuccess "Config filename:" "${confFilename}\n"
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
  assertTask 'Awaiting user selection for config file...'
  if ! confFile=$(
    find "${CONFIG_DIR}/${seriesTitle}"* |
      fzf --header 'Select a config file' \
        --with-nth 6.. \
        --delimiter '/' \
        --preview 'cat {} 2>/dev/null | head -200'

  ); then
    assertError 'No config file was selected'
    assertTryAgain selectConfigFile
  else
    confFilename=$(basename "${confFile}")
    isCustom=$(
      assertSelection "
        Do you want to customize this config file?
        $(assertSuccess "Config file: '${confFilename}'")
        No
        Yes
      " --header-lines 2 \
        --preview "cat \"${confFile}\" 2>/dev/null | head -200"

    )

    if [[ ${isCustom} == Yes ]]; then
      assertSuccess "Config file:" "${confFile/#$HOME/\~}\n"
      customizeConfigFile
    else
      if [[ -s ${confFile} ]]; then
        assertSuccess "Config file:" "${confFile/#$HOME/\~}\n"
      else
        assertMissing "No youtube-dl options found!\n"
      fi
    fi
  fi
}

selectSeries() {
  series=$(cat -n <<<"${seriesTitles}" | fzf --with-nth 2..)

  if [[ ${series} ]]; then
    seriesIndex=$(awk '{print $1}' <<<"${series}")
    seriesTitle=$(awk -F '\t' '{print $2}' <<<"${series}")
    seriesURL=$(sed "${seriesIndex}q;d" <<<"${seriesList}")
    assertSuccess "Series: ${seriesTitle}"
    assertSuccess "URL:" "${seriesURL}"
  else
    assertError 'No title selected'
    handleSeriesError=$(
      assertSelection "
        Try again
        $([[ $1 == Seasons ]] && echo 'Select different season')
        Abort
      "
    )

    if [[ ${handleSeriesError} == Try* ]]; then
      selectSeries "$1"
    elif [[ ${handleSeriesError} == *season ]]; then
      echo
      selectSeason
      processSeriesList "$1"
    else
      assertError 'Aborted by user'
      exit 1
    fi
  fi
}

createSeriesList() {
  playlistHtmlDoc=$(downloadPage "${seriesListURL}")

  seriesList=$(
    hxclean <<<"${playlistHtmlDoc}" |
      hxselect -s '\n' -c "${playlistQuery}" 2>/dev/null |
      awk -v baseURL=${baseURL} '{print baseURL$0}'
  )

  if [[ ${seriesList} ]]; then
    assertSuccess "Series list:" "\n${seriesList}\n"
  else
    assertError 'Could not parse URLs from series list HTML document'
    exit 1
  fi

  seriesTitles=$(
    hxclean <<<"${playlistHtmlDoc}" |
      hxselect -s '\n' -c "${titlesQuery}" 2>/dev/null |
      safeFilename |
      sed "s/&#039_/'/g" |
      sed "s/&amp_/\&/g" |
      sed "s/  / /g" |
      sed "s/[[:space:]]*$//"
  )

  if [[ ! ${seriesTitles} ]]; then
    assertError 'Could not parse titles from series list HTML document'
    exit 1
  fi
}

addToWatchList() {
  if ! grep -q "${seriesTitle}" "${LIST_JSON}" 2>/dev/null; then
    confirmAddToWatchList=$(
      assertSelection '
      Do you want to add this series to watching list?
      Yes
      No
    ' --header-lines 1
    )

    if [[ ${confirmAddToWatchList} == Yes ]]; then
      [[ -s $LIST_JSON ]] || echo '{ "watching": [] }' >"${LIST_JSON}"
      list="$(cat "${LIST_JSON}")"

      jq --arg url "${seriesURL}" --arg title "${seriesTitle}" \
        '.watching += [{ $url, $title }]' <<<"${list}" >"${LIST_JSON}"

      assertSuccess "Series added to watching list\n"
    else
      echo
      return
    fi

  else
    assertSuccess "Series is in watching list\n"
  fi
}

selectSeason() {
  assertTask 'Awaiting user selection from seasons list...'
  season=$(
    hxclean <<<"${mainHtmlDoc}" |
      hxselect -s '\n' -c "${seasonQuery}" 2>/dev/null |
      awk '{print tolower($1"-"$2)}' |
      fzf
  )

  if [[ ${season} ]]; then
    seriesListURL="${seriesListBaseURL}/${season}"
    assertSuccess "Season: ${season^}\n"
  else
    assertError 'Failed to prase season'
    exit 1
  fi
}

processSeriesList() {
  assertTask 'Creating series list...'
  createSeriesList
  assertTask 'Awaiting user selection from titles list...'
  selectSeries "$1"
}

processSeriesOptions() {
  seriesListBaseURL="${mainURL}/${1,,}"
  assertTask "Fetching ${1,,} list from crunchyroll.com..."

  if [[ $1 == Seasons ]]; then
    mainHtmlDoc=$(
      downloadPage ${mainURL} || assertError 'Failed to download HTML document'
    )

    [[ ${mainHtmlDoc} ]] || exit 1
    selectSeason

  else
    seriesListURL="${seriesListBaseURL}"
  fi

  processSeriesList "$1"
  addToWatchList
}

findConfig() {
  if [[ ! ${seriesTitle} ]]; then
    assertError 'No series selected'
    exit 1
  fi

  assertTask 'Finding custom config file for this series...'
  if compgen -G "${CONFIG_DIR}/${seriesTitle}*" >/dev/null; then
    assertSuccess "Found one or more youtube-dl config files for this series\n"
    configFound=true
  else
    assertMissing "No config file found\n"
  fi
}

processConfig() {
  if [[ ${configFound} ]]; then
    useExistingConf=$(
      assertSelection '
        Select a config file
        Create a new config file
        Cancel!
      ' --phony
    )

    if [[ ${useExistingConf} == Select* ]]; then
      selectConfigFile
    elif [[ ${useExistingConf} == Create* ]]; then
      createConfigFile
    fi

  else
    createNewConf=$(
      assertSelection '
        Do you want to create a custom youtube-dl config file for this series?
        Yes
        No
      ' --header-lines 1
    )
    if [[ ${createNewConf} == Yes ]]; then
      createConfigFile
    fi
  fi
}

stream() {
  mpvConf="${HOME}/.config/mpv/mpv.conf"

  if [[ ! -f ${mpvConf} ]]; then
    assertMissing 'MPV config file not found!'
    assertTask 'Creating MPV config templates...'
    mkdir -p ~/.config/mpv
    cp -r /usr/local/share/doc/mpv/ ~/.config/mpv/
    assertSuccess "MPV config file:" "${mpvConf/#$HOME/\~}\n"
  fi

  if ! grep -q '\[crunchyroll\]' "${mpvConf}"; then
    assertMissing "Crunchyroll profile was not found in MPV config file\n"
    assertTask 'Appending Crunchyroll profile to MPV config file...'

    mpvProfile="
     [crunchyroll]
     fs=yes
     ytdl-format='[format_id*=jaJP][format_id!*=hardsub]'
     ytdl-raw-options=netrc=
    "

    trimWhiteSpace "${mpvProfile}" >>"${mpvConf}"
    assertSuccess "Appended Crunchyroll profile to MPV config file\n"

    reviewConf=$(
      assertSelection '
        Do you want to review or edit MPV config file?
        Yes
        No
      ' --header-lines 1
    )
    [[ ${reviewConf} == Yes ]] && ${EDITOR:-vi} "${mpvConf}"
  fi

  command -v iina >/dev/null 2>&1 || ANIME_PLAYER=MPV

  player=${ANIME_PLAYER:-$(
    assertSelection '
      Choose a media player
      IINA
      MPV
      Abort
    ' --header-lines 1
  )}

  streamMessage() {
    assertSuccess "Enjoy watching high quality stream\n"
    playUnicode="${blueText}\u25B6${reset}"
    echo -e "${playUnicode} Opening '${seriesTitle}' stream in ${player}..."
  }

  if [[ ${player} == IINA ]]; then
    streamMessage
    iina "${seriesURL}" -- --profile=crunchyroll "$@"
  elif [[ ${player} == MPV ]]; then
    streamMessage
    mpv --profile=crunchyroll "$@" -- "${seriesURL}"
  else
    assertError 'Aborted by user'
    exit 1
  fi
}

processStream() {
  if [[ -s ${confFile} ]]; then
    assertTask 'Streaming with custom youtube-dl config file...'
    stream --ytdl-raw-options=config-location="${confFile}" "$@"
  else
    assertTask 'Streaming with Crunchyroll profile in mpv config file...'
    stream "$@"
  fi
}

download() {
  if [[ ${ANIME_DIR} || ! ${SERIES_DIR} == 0 ]]; then
    assertTask 'Changing directory...'

    [[ ${ANIME_DIR} ]] && if ! cd "${ANIME_DIR}"; then
      assertError 'Could not change to Anime home directory'
      exit 1
    fi

    if [[ ! ${SERIES_DIR} == 0 ]]; then
      [[ -d ${seriesTitle} ]] || mkdir "${seriesTitle}"
      if ! cd "${seriesTitle}"; then
        assertError 'Could not change to series directory'
        exit 1
      fi
    fi

    assertSuccess 'Download directory:' "${PWD/#$HOME/\~}\n"
  fi

  if [[ -s ${confFile} ]]; then
    assertTask 'Downloading with custom youtube-dl config file...'
    youtube-dl "${seriesURL}" --config-location <(
      cat "${USER_CONFIG}" "${CRUNCHYROLL_CONFIG}" "${confFile}" 2>/dev/null
    ) "$@"

  else
    assertTask 'Downloading with youtube-dl...'
    youtube-dl "${seriesURL}" --config-location <(
      cat "${USER_CONFIG}" "${CRUNCHYROLL_CONFIG}" 2>/dev/null
    ) "$@"
  fi

  if [[ ${ISO_SUB} != 0 ]]; then
    echo
    assertTask 'Renaming subtitles to ISO 639-1 code format...'
    if ! for file in *[A-Z][A-Z].ass; do
      mv -v -- "${file}" "${file%[A-Z][A-Z].ass}.ass"
    done 2>/dev/null; then
      assertMissing "No matching subtitles were found that require renaming\n"
    fi
  fi
}

downloadOrStream() {
  streamOrDownload=$(
    assertSelection "
      Stream
      Download
    " --phony
  )

  if [[ ${streamOrDownload} == Stream ]]; then
    processStream "$@"
  elif [[ ${streamOrDownload} == Download ]]; then
    download "$@"
  else
    assertTryAgain downloadOrStream "$@"
  fi
}

selectFromWatchList() {
  list="$(cat "${LIST_JSON}")"

  seriesTitle="$(
    jq -cr '.watching[].title' <<<"${list}" | fzf
  )"

  seriesURL="$(
    jq --arg title "${seriesTitle}" -cr \
      '.watching[] | select(.title==$title).url' <<<"${list}"
  )"

  if [[ ${seriesTitle} && ${seriesURL} ]]; then
    assertSuccess "Series: ${seriesTitle}"
    assertSuccess "URL:" "${seriesURL}\n"
  else
    assertTryAgain selectFromWatchList
  fi
}

browse() {
  if [[ ! $1 ]]; then
    exit 1
  elif [[ $1 == "Watching" ]]; then
    assertTask 'Awaiting user selection from watching list...'
    selectFromWatchList
  else
    processSeriesOptions "$1"
  fi

  findConfig
}

#* --{ Main workflow }-- *#
if [[ $1 =~ ^((--)?help|-h)$ ]]; then
  mpv --help
  exit
fi

[[ ${ANIME_DIR} ]] && if [[ ! -d ${ANIME_DIR} ]]; then
  assertMissing 'Anime home directory:' "${ANIME_DIR}"
  assertError 'Anime home directory not found'
  exit 1
fi

if [[ ! -d ${CONFIG_DIR} ]]; then
  assertTask "Creating 'config' directory..."
  mkdir -p "${CONFIG_DIR}"
  assertSuccess "Config directory:" "${CONFIG_DIR}\n"
fi

browsingList="
  $([[ -s $LIST_JSON ]] && echo "Watching List")
  Popular List
  Simulcasts List
  Updated List
  Seasons List
"

assertTask "Awaiting user selection from main options..."
main=$(
  assertSelection "
    ${browsingList}
    Process Configurations ${yellowBoldText}ONLY${reset}
  "
)

if [[ ! ${main} ]]; then
  exit 1
elif [[ ${main} != Process* ]]; then
  assertSuccess "Browse: ${main}\n"
  browse "$(awk '{print $1}' <<<"${main}")"
  processConfig
  downloadOrStream "$@"

else
  processOption="$(
    assertSelection "
      Process configurations of a series from...
      ${browsingList}
    " --header-lines 1
  )"

  assertSuccess "Process series config from: ${processOption}\n"
  browse "$(awk '{print $1}' <<<"${processOption}")"

  while true; do
    processConfig
    repeat=$(
      assertSelection '
        Process another config file for selected series
        Cancel
      ' --phony
    )
    if [[ ${repeat} != Process* ]]; then
      assertSuccess 'Done'
      break
    fi
  done
fi

exit
