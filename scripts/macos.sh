#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

main() {
  log "Setup appearance"
  defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"
  defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 1

  log "Setup Control Center"
  defaults write com.apple.menuextra.battery ShowPercent -string "YES"
  defaults write com.apple.controlcenter "NSStatusItem Visible WiFi" -bool true
  defaults write com.apple.controlcenter "NSStatusItem Visible Bluetooth" -bool true

  log "Setup Desktop"
  defaults write com.apple.dock mru-spaces -bool false

  log "Setup Dock"
  defaults write com.apple.dock magnification -bool true
  defaults write com.apple.dock tilesize -int 40
  defaults write com.apple.dock largesize -int 70
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock show-recents -bool false
  defaults write com.apple.dock autohide-delay -float 0
  defaults write com.apple.dock autohide-time-modifier -float 0.5

  log "Setup Lock Screen"
  sudo pmset -b displaysleep 10

  log "Setup Keyboard"
  defaults write -g KeyRepeat -int 2
  defaults write -g InitialKeyRepeat -int 15
  defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSUserQuotesArray -array '"\""' '"\""' "\"'\"" "\"'\""
  defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

  log "Setup Trackpad"
  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -int 1
  defaults write -g com.apple.trackpad.scaling -float 3

  log "Setup Finder"
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  defaults write com.apple.finder FXPreferredViewStyle -string "clmv"
  chflags nohidden "${HOME}/Library"
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.Finder QuitMenuItem -bool true

  log "Setup Screenshot"
  mkdir -p "${HOME}/ScreenShot"
  defaults write com.apple.screencapture location "${HOME}/ScreenShot"

  log "Restart affected processes"
  killall Dock || true
  killall Finder || true
  killall SystemUIServer || true

  read -r -p "Some changes require a reboot. Reboot now? (y/N): " reply
  if [[ "${reply}" =~ ^[Yy]$ ]]; then
    sudo reboot
  else
    log "Reboot skipped"
  fi
}

main "$@"
