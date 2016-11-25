#!/usr/bin/env sh

NIX_PROFILE="$HOME"/.nix-profile
APP_DIR="$HOME"/Applications

# remove old links
for f in "$APP_DIR"/*; do
    link="$(readlink $f)"
    if [ ! -z "$link" ]; then
        if [[ "$link" == "$NIX_PROFILE/Applications/"* ]]; then
            rm "$f"
        fi
    fi
done

# link new ones
for f in "$NIX_PROFILE"/Applications/*; do
    app_name="$(basename "$f")"
    if [ ! -e "$APP_DIR/$app_name" ]; then
        ln -s "$f" "$APP_DIR"/
    fi
done
