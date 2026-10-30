#!/usr/bin/env bash
set -euo pipefail

# Install DevEco official HarmonyOS skills into a DSH skills directory.
# Usage:
#   ./install-deveco-skills.sh                 # all 49 official skills
#   ./install-deveco-skills.sh --recommended   # selected 30 skills
#   ./install-deveco-skills.sh --dest DIR      # custom destination

DEST="${HOME}/.dsh/skills"
MODE="all"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all) MODE="all"; shift ;;
    --recommended) MODE="selected"; shift ;;
    --dest) DEST="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done

mkdir -p "$DEST"

if [ "$MODE" = "all" ]; then
  devecocli skills add --all --path "$DEST" --force
  exit 0
fi

SKILLS=(
  hmos-arkui-develop-skill
  hmos-arkts-syntax-checker
  hmos-arkts-knowledge-retriever
  hmos-arkts-deprecated-interface-checker
  hmos-arkui-mvvm-pattern
  hmos-arkui-statemgt-migration
  hmos-multidevice-scenario-entry
  hmos-multidevice-screen-window-size
  hmos-multidevice-avoid-areas
  hmos-multidevice-natural-orientation
  hmos-multidevice-interaction-methods
  hmos-multidevice-fold-state
  hmos-multidevice-hardware-access
  hmos-window-smart-orientation
  hmos-account-kit-login-api-client
  hmos-account-kit-login-button-client
  hmos-account-kit-quicklogin-client
  hmos-connect-api-cli-skill
  hmos-one-sdk-skill
  hmos-local-test
  hmos-instrument-test
  hmos-apifault-analysis
  hmos-jscrash-analysis
  hmos-appfreeze-analysis
  hmos-memleak-analysis
  hmos-arkui-longtake-transition
  hmos-arkui-kit-window-floatwindow
  hmos-design-visual-mobile
  hmos-runtime-fix-skill
  app-metadata-audit-skill
)

for skill in "${SKILLS[@]}"; do
  echo "installing: $skill"
  devecocli skills add --path "$DEST" --skill "$skill" --force
done
