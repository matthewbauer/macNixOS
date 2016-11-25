#!/usr/bin/env sh

if [ -d /etc/paths.d ]; then
    echo "/nix/var/nix/profiles/default" > /etc/paths.d/nix
fi
