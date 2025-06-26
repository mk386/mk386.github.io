#!/usr/bin/env bash

trap_exit() {
    if [[ ! -o xtrace ]]; then
        rm -rf "$tmp"
    fi
}

tmp=$(mktemp -dt)

trap 'trap_exit' EXIT

cd "$tmp"

curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
unzip rclone-current-linux-amd64.zip

cd rclone-*-linux-amd64

mkdir -p ~/.local/bin/
cp rclone ~/.local/bin/

mkdir -p ~/.local/share/man/man1
cp rclone.1 ~/.local/share/man/man1
