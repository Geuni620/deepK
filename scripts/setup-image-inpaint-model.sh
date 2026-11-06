#!/usr/bin/env bash
# Downloads only the public, pinned MI-GAN model and its licenses. No image/user input is accepted.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_ROOT="$PROJECT_ROOT/.build/image-translation-poc/models"
MODEL_REF=f81478c22b55c33a02dffee3fe2bf3caf1c5cc3c
MODEL_BASE="https://raw.githubusercontent.com/midagedev/mwoyeo/$MODEL_REF"
mkdir -p "$MODEL_ROOT"
download_model_file() {
  local model_relative="$1" model_expected="$2" model_destination="$3"
  mkdir -p "$(dirname "$model_destination")"
  if [[ -f "$model_destination" ]] && [[ "$(git hash-object --no-filters "$model_destination")" == "$model_expected" ]]; then return; fi
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --max-time 120 \
    "$MODEL_BASE/$model_relative" -o "$model_destination.part"
  [[ "$(git hash-object --no-filters "$model_destination.part")" == "$model_expected" ]] || { echo "Model integrity check failed." >&2; exit 1; }
  mv "$model_destination.part" "$model_destination"
}
PACKAGE="$MODEL_ROOT/MIGAN_512.mlpackage"
download_model_file tools/inpaint/models/LICENSE-MI-GAN-WEIGHTS 66247bb1c9e330a954d7edeb56f77d823e6f2fca "$MODEL_ROOT/LICENSE-MI-GAN-WEIGHTS"
download_model_file LICENSE 28f3da43ad71e49030ea19a440ab100ee72c4078 "$MODEL_ROOT/LICENSE-MWOYEO"
download_model_file tools/inpaint/models/MIGAN_512.mlpackage/Manifest.json 3da1a6cf667e0ffa27336cac35fdf34e4355c08b "$PACKAGE/Manifest.json"
download_model_file tools/inpaint/models/MIGAN_512.mlpackage/Data/com.apple.CoreML/model.mlmodel 54a8d0c52ffa11d6814945f4fd51658bee7b8fe0 "$PACKAGE/Data/com.apple.CoreML/model.mlmodel"
download_model_file tools/inpaint/models/MIGAN_512.mlpackage/Data/com.apple.CoreML/weights/weight.bin fc5d21aecd85aa9209a25ef58546c925b719fbbe "$PACKAGE/Data/com.apple.CoreML/weights/weight.bin"
mkdir -p "$MODEL_ROOT/compiled"
xcrun coremlcompiler compile "$PACKAGE" "$MODEL_ROOT/compiled"
echo "Pinned local MI-GAN model prepared (about 14 MB of source weights); no user content processed."
