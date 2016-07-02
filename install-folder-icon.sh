#!/usr/bin/env sh

dest="/nix"

Rez -append nix-mac-icon.rsrc -o $"$dest/Icon\r"
SetFile -a C $dest
SetFile -a V $"$dest/Icon\r"
