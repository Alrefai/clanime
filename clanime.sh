#!/usr/bin/env bash

set -o pipefail

CONFIG_DIR="${HOME}/.config/clanime"

baseURL='https://www.crunchyroll.com'
mainURL="${baseURL}/videos/anime"
seasonBaseURL="${mainURL}/seasons"

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
  confirmModifiers=$(
    assertSelection "
      Confirm playlist modifiers?
      $(assertSuccess "Playlist modifiers:\n${playlistModifier}")
      Yes, review config file in default text editor
      No, reselect index numbers
      Abort
    " --header-lines $((modifiersCount + 2))
  )

  if [[ ${confirmModifiers} == Yes* ]]; then
    assertSuccess "Playlist modifiers:" "\n${playlistModifier}\n"
  elif [[ ${confirmModifiers} == No* ]]; then
    playlistSelection
  else
    assertError 'Aborted by user'
    exit 1
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

  assertSuccess "Playlist index file:" "\n${playlistIndex/#$HOME/\~}\n"
}

playlistSelection() {
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

playlistFilter() {
  filter=$(
    assertSelection '
      Select format filter
      Japanese audio (softsub only)
      English audio (softsub only)
      Custome filter
      No filter
    ' --header-lines 1
  ) || assertTryAgain playlistFilter

  if [[ ${filter} == Japanese* ]]; then
    format='[format_id*=jaJP][format_id!*=hardsub]'
  elif [[ ${filter} == English* ]]; then
    format='[format_id*=enUS][format_id!*=hardsub]'
  elif [[ ${filter} == Custome* ]]; then
    assertTask 'Awaiting user input for format filter...'
    readHeader 'Modify format template below (then press [ENTER])'
    readPrompt '' '[format_id*=jaJP][format_id!*=hardsub]'
    format=${textInput}
  fi

  assertSuccess "Format: ${format:-Default to 'best'}"
}

parsePlaylistIndex() {
  [[ -d ${CONFIG_DIR}/playlist-index ]] ||
    mkdir -p "${CONFIG_DIR}/playlist-index"
  playlistFilter
  playlistIndexDIR="${CONFIG_DIR}/playlist-index"
  playlistIndex="${playlistIndexDIR}/$(date '+%Y-%m-%d') - ${seriesTitle}.txt"
  assertSuccess "Cache file:" "\n${playlistIndex/#$HOME/\~}"
  assertSuccess 'Data output: INDEX | SEASON_NUMBER | TITLE'

  if youtube-dl "${seriesURL}" \
    --netrc \
    --dump-json \
    --ignore-config \
    --ignore-errors \
    --format "${format:-best}" |
    jq --unbuffered -cr \
      '[.playlist_index,.season_number,.title] | join(" | ")' |
    tee "${playlistIndex}"; then

    assertSuccess "Parsing completed\n"
  else
    assertError 'Failed to parse playlist'
    assertTryAgain parsePlaylistIndex
  fi
}

customizeConfigFile() {
  selectRange=$(
    assertSelection "
      Do you want to specify --playlist-(start|end|items) options?
      This is useful for filtering dubbed episodes from playlist stream.
      Or for creating a config file for each season of the series.
      $(assertWarning \
      'youtube-dl may take several minutes to parse long playlists')
      Yes
      No, add other options to config file manually
    " --header-lines 4
  )

  if [[ ${selectRange} == Yes ]]; then
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

    if [[ -f ${confFile} ]]; then
      echo "${playlistModifier}" >>"${confFile}" &&
        ${EDITOR:-vi} "${confFile}"
    else
      ${EDITOR:-vi} "+w ${confFile}" <<<"${playlistModifier}"
    fi

  else
    assertSuccess "Add config options manually\n"
    ${EDITOR:-vi} "${confFile}"
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
    assertSuccess "Config filename:" "\n${confFilename}\n"
  else
    getConfigFilename
  fi
}

createConfigFile() {
  if [[ ! -d ${CONFIG_DIR} ]]; then
    assertTask "Creating 'config' directory..."
    mkdir -p "${CONFIG_DIR}"
    assertSuccess "Config directory:" "\n${CONFIG_DIR}\n"
  fi

  assertTask 'Awaiting user input for config filename...'
  getConfigFilename

  assertTask 'Customizing config file...'
  customizeConfigFile

  assertTask 'Saving new config file...'
  if [[ -f ${confFile} ]]; then
    configFound=true
    assertSuccess "Config file:" "\n${confFile/#$HOME/\~}\n"
  else
    assertError 'Config file not found!'
    exit 1
  fi
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
        Yes
        No
      " --header-lines 2
    )

    assertSuccess "Config file:" "\n${confFile/#$HOME/\~}\n"

    if [[ ${isCustom} == Yes ]]; then
      assertTask 'Finding local playlist index...'
      customizeConfigFile
    else
      return 1
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
    assertSuccess "URL:" "\n${seriesURL}\n"
  else
    assertError 'No title selected'
    handleSeriesError=$(
      assertSelection '
        Select another series
        Select another season
        Abort
    ' --phony
    )

    if [[ ${handleSeriesError} == *series ]]; then
      selectSeries
    elif [[ ${handleSeriesError} == *season ]]; then
      selectSeason
    else
      assertError 'Aborted by user'
      exit 1
    fi
  fi
}

createSeriesList() {
  seasonURL="${seasonBaseURL}/${season}"
  playlistHtmlDoc=$(downloadPage "${seasonURL}")

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

selectSeason() {
  assertTask 'Awaiting user selection from seasons list...'
  season=$(
    hxclean <<<"${seasonsHtmlDoc}" |
      hxselect -s '\n' -c "${seasonQuery}" 2>/dev/null |
      awk '{print tolower($1"-"$2)}' |
      fzf
  )

  if [[ ${season} ]]; then
    assertSuccess "Season: ${season^}\n"
    assertTask 'Creating series list...'
    createSeriesList
    assertTask 'Awaiting user selection from titles list...'
    selectSeries
  else
    assertError 'Failed to prase season'
    exit 1
  fi
}

fetchSeasons() {
  seasonsHtmlDoc=$(
    downloadPage ${mainURL} || assertError 'Failed to download HTML document'
  )

  [[ ${seasonsHtmlDoc} ]] || exit 1

  assertSuccess "Downloaded HTML document of seasons list\n"
  selectSeason
}

findConfig() {
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
    assertSuccess "MPV config file:" "\n${mpvConf/#$HOME/\~}\n"
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

  player=$(
    assertSelection '
      Choose a media player
      IINA
      MPV
      Abort
    ' --header-lines 1
  )

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
  fi

}

processStream() {
  processConfig
  if [[ ${confFile} ]]; then
    assertTask 'Streaming with custom youtube-dl config file...'
    stream --ytdl-raw-options=config-location="${confFile}" "$@"
  else
    assertTask 'Streaming with Crunchyroll profile in mpv config file...'
    stream "$@"
  fi
}

if [[ $1 =~ ^((--)?help|-h)$ ]]; then
  mpv --help
  exit
fi

assertTask 'Fetching series seasons list from crunchyroll.com...'
fetchSeasons
findConfig

main=$(
  assertSelection "
    Stream
    Process configurations ${yellowBoldText}ONLY${reset}
  " --phony
)

if [[ ${main} == Stream* ]]; then
  processStream "$@"
else
  while true; do
    processConfig
    repeat=$(
      assertSelection '
        Process another config file this series
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
