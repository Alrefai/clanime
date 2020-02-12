#!/usr/bin/env bash

# Font styling and colors
boldText=$'\e[1m'
greenBoldText=$'\e[1;32m'
blueText=$'\e[34m'
redUnderlinedText=$'\e[4;31m'
reset=$'\e[0m'

assertTask() {
  echo -e "${blueText}==>${reset} ${boldText}$*${reset}"
}

assertSuccess() {
  checkMark="${greenBoldText}\u2714${reset}"
  echo -e "${checkMark} ${boldText}$1${reset}" "${@:2}"
}

assertError() {
  echo -n "${redUnderlinedText}Error${reset}: " >&2

  if [[ $# == 0 ]]; then
    echo 'Something wrong happened!' >&2
  else
    echo "$*" >&2
  fi
}

if [[ -f /usr/local/bin/brew ]]; then
  assertSuccess 'Homebrew package manager is installed'
else
  assertTask 'Installing Homebrew package manager for macOS...'
  /usr/bin/ruby -e "$(
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install
  )"
fi

assertTask "Installing dependencies..."
brew bundle check || brew bundle -v

# Make the app globally available
echo
assertTask 'Installing clanime...'

if cp -iv clanime.sh /usr/local/bin/clanime; then
  assertSuccess 'Done'
else
  assertError 'clanime was not installed globally'
  exit 1
fi

exit
