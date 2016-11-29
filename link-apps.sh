#!/usr/bin/env sh

NIX_PROFILE="$HOME"/.nix-profile
APP_DIR="$HOME"/Applications

# remove broken links
for f in "$APP_DIR"/*; do
    if [ -L "$f" ] && [ ! -e "$f" ]; then
        rm "$f"
    fi
done

# link new ones
for f in "$NIX_PROFILE"/Applications/*; do
    app_name="$(basename "$f")"
    if [ ! -e "$APP_DIR/$app_name" ]; then
        ln -s "$f" "$APP_DIR"/
    fi
done
