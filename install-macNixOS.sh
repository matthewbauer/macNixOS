#!/usr/bin/env sh

set -e

# Run this script to turn your single-user MacOS into a multi-user
# setup. This is still untested but it has worked on at least one
# machine. This script must be run as root and single-user nix must be
# installed first.

# This is based off of:
# - @expipiplus1's instructions in https://gist.github.com/expipiplus1/e571ce88c608a1e83547c918591b149f.
# - Nix manual 6.2 at https://nixos.org/nix/manual/#ssec-multi-user.

dest=/nix
group=nixbld

if [ -z "$USER" ]; then
    echo "$0: \$USER is not set" >&2
    exit 1
fi

if ! [ "$(id -u)" -eq 0 ]; then
    echo "Must be root." >&2
    exit 1
fi

if ! [ -e "$dest" ]; then
    echo "Single-user Nix must already be installed" >&2
    exit 1
fi

echo "performing a multi-user installation of Nix..."

echo "Creating $group group"
dseditgroup -q -o create $group

gid=$(dscl -q . read /Groups/$group | awk '($1 == "PrimaryGroupID:") {print $2 }')

echo "Create $group users"
for i in $(seq 1 10); do
    user=/Users/$group$i
    uid="$((30000 + $i))"

    dscl -q . create $user
    dscl -q . create $user RealName "Nix build user $i"
    dscl -q . create $user PrimaryGroupID $gid
    dscl -q . create $user UserShell /usr/bin/false
    dscl -q . create $user NFSHomeDirectory /var/empty
    dscl -q . create $user UniqueID $uid

    dscl . -append /Groups/$group GroupMembership $group$i

    dseditgroup -q -o edit -a $group$i -t user $group
done

olduser=$(ls -ld $dest | awk '{print $3}')
if [ "$olduser" != root ]; then
    echo "Removing single-user artifacts"
    rm /Users/$olduser/.nix-profile
    rm -r /Users/$olduser/.nix-defexpr
    if ! [ -e $dest/var/nix/profiles/per-user/$olduser/profile ]; then
        ln -s $dest/var/nix/profiles/default $dest/var/nix/profiles/per-user/$olduser/profile
    fi

    echo "Setting ownership for $dest"
    chown -R root:nixbld $dest
fi

# extra stuff that shouldn't be necessary
chmod 1777 $dest/var/nix/profiles
chmod 1777 $dest/var/nix/profiles/per-user
mkdir -m 1777 -p $dest/var/nix/gcroots/per-user

echo "Setting up user profile permissions"
for profile in $dest/var/nix/profiles/per-user/*; do
    chown $(basename $profile):staff $profile
done

mkdir -p /etc/nix
echo "Adding build-users-group to /etc/nix/nix.conf."
echo "build-users-group = $group # added by macNixOS installer" >> /etc/nix/nix.conf

echo "Installing org.nixos.nix-daemon.plist in /Library/LaunchDaemons."
ln -fs $dest/var/nix/profiles/default/Library/LaunchDaemons/org.nixos.nix-daemon.plist /Library/LaunchDaemons/

echo "Starting nix-daemon."
launchctl load -F /Library/LaunchDaemons/org.nixos.nix-daemon.plist
launchctl start org.nixos.nix-daemon

echo "Installing nix profile."
cat <<"EOF" > /etc/nix/nix-profile.sh
# From https://gist.github.com/benley/e4a91e8425993e7d6668

# Heavily cribbed from the equivalent NixOS login script.
# This should work better with multi-user nix setups.

export NIX_USER_PROFILE_DIR="/nix/var/nix/profiles/per-user/$USER"
export NIX_PROFILES="/nix/var/nix/profiles/default $HOME/.nix-profile"
export NIX_PATH="/nix/var/nix/profiles/per-user/root/channels"

# Use the nix daemon for multi-user builds
if [ "$USER" != root -o ! -w /nix/var/nix/db ]; then
  export NIX_REMOTE=daemon
fi

# Set up the per-user profile.
mkdir -m 0755 -p "$NIX_USER_PROFILE_DIR"
if [ "$(ls -ld "$NIX_USER_PROFILE_DIR" | awk '{print $3}')" != "$USER" ]; then
    echo "WARNING: bad ownership on $NIX_USER_PROFILE_DIR" >&2
fi

if [ -w "$HOME" ]; then
  # Set the default profile.
  if ! [ -L "$HOME/.nix-profile" ]; then
    if [ "$USER" != root ]; then
      ln -s "$NIX_USER_PROFILE_DIR/profile" "$HOME/.nix-profile"
    else
      # Root installs in the system-wide profile by default.
      ln -s /nix/var/nix/profiles/default "$HOME/.nix-profile"
    fi
  fi

  # Create the per-user garbage collector roots directory.
  NIX_USER_GCROOTS_DIR=/nix/var/nix/gcroots/per-user/$USER
  mkdir -m 0755 -p "$NIX_USER_GCROOTS_DIR"
  if [ "$(ls -ld "$NIX_USER_GCROOTS_DIR" | awk '{print $3}')" != "$USER" ]; then
    echo "WARNING: bad ownership on $NIX_USER_GCROOTS_DIR" >&2
  fi

  # Set up a default Nix expression from which to install stuff.
  if [ ! -e "$HOME/.nix-defexpr" -o -L "$HOME/.nix-defexpr" ]; then
    rm -f "$HOME/.nix-defexpr"
    mkdir "$HOME/.nix-defexpr"
    if [ "$USER" != root ]; then
        ln -s /nix/var/nix/profiles/per-user/root/channels "$HOME/.nix-defexpr/channels_root"
    fi
  fi

  # Subscribe the to the Nixpkgs channel by default.
  if [ ! -e "$HOME/.nix-channels" ]; then
      echo "https://nixos.org/channels/nixpkgs-unstable nixpkgs" > "$HOME/.nix-channels"
  fi

  # Prepend ~/.nix-defexpr/channels/nixpkgs to $NIX_PATH so that
  # <nixpkgs> paths work when the user has fetched the Nixpkgs
  # channel.
  export NIX_PATH="nixpkgs=$HOME/.nix-defexpr/channels/nixpkgs${NIX_PATH:+:$NIX_PATH}"

  # Make sure nix-channel --update works
  SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
  CURL_CA_BUNDLE=$SSL_CERT_FILE
fi
EOF

. /etc/nix/nix-profile.sh
nix-channel --update
rm -f /nix/var/nix/profiles/.new_default
nix-env -p $dest/var/nix/profiles/default -f $HOME/.nix-defexpr/channels/nixpkgs/ -iA nix
nix-env -ri nix nss-cacert

p=/etc/nix/nix-profile.sh
fn=/etc/profile
if ! grep -q "$p" "$fn"; then
    echo "modifying $fn..." >&2
    echo "if [ -e $p ]; then . $p; fi # added by macNixOS installer" >> $fn
fi

# just automatically set hidden
echo "Hiding $dest directory."
chflags hidden $dest

# Rez, SetFile only in comamnd line tools
# if [ -f nix-mac-icon.rsrc ]; then
#     echo "Adding folder icon to /nix"
#     Rez -append nix-mac-icon.rsrc -o $"$dest/Icon\r"
#     SetFile -a C $dest
#     SetFile -a V $"$dest/Icon\r"
# fi

if [ -d /etc/paths.d ]; then
    echo "Adding /etc/paths.d/nix."
    echo $dest/var/nix/profiles/default/bin > /etc/paths.d/nix
fi

cat >&2 <<EOF
Installation finished!

To use on a currently logged in user, run:

. /etc/nix/nix-profile.sh

EOF
