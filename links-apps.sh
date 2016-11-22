#!/usr/bin/env sh

NIX_PROFILE="$HOME"/.nix-profile
APP_DIR="$HOME"/Applications

for f in "$NIX_PROFILE"/Applications/*; do
    app_name="$(basename "$f")"
    if [ ! -e "$APP_DIR/$app_name" ]; then
        ln -s "$f" "$APP_DIR"/
    fi
done
