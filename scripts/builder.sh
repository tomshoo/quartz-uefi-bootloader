#!/usr/bin/env bash

OVMF_FD_DIR="${OVMF_FD_DIR:-/usr/share/ovmf/x64}"
__esp_dir_structure="EFI/BOOT"

function log() {
    loglevel=info

    case "$1" in
    -l=*) loglevel="${1#*=}"
          shift
          ;;
    esac

    case "$loglevel" in
    info|warn) printf "[%s]: %s\n" "$loglevel" "$*"     ;;
    error)     printf "[%s]: %s\n" "$loglevel" "$*" >&2 ;;
    *) echo "error: invalid loglevel: $loglevel" >&2
       return 1
       ;;
    esac
}

build=false
clear=false
run=false
imgfile=
noop=false
profile=release
espdir=esp

while getopts :cbrhndi:e: opt; do
    case "$opt" in
    c) clear=true ;;
    b) build=true ;;
    r) run=true   ;;
    n) noop=true  ;;
    i) imgfile="$(realpath "$OPTARG")";;
    e) espdir="$OPTARG" ;;
    d) profile=debug  ;;
    h) printf "Usage: %s [options]? \n" "$(basename "$0")"
       printf " -c remove the configured espdir               \n"
       printf " -b run cargo build                            \n"
       printf " -r run the uefi image using qemu              \n"
       printf " -n set noop=true (prevents copying to espdir) \n"
       printf " -i configure imgfile path                     \n"
       printf " -e configure espdir                           \n"
       printf " -d enable debug build                         \n"
       exit 0
       ;;
    ?) log -l=error "Invalid option -$OPTARG, try $(basename "$0") -h"
       exit 1
       ;;
    esac
done

if $build; then
    log "Building UEFI image..."

    if [ $profile = debug ]; then
         cargo build --target=x86_64-unknown-uefi
    else cargo build --release --target=x86_64-unknown-uefi; fi

    imgfile="$(realpath  ./target/x86_64-unknown-uefi/$profile/quartz.efi)"
fi

if ! $noop; then
    log "Copying $imgfile to $espdir/$__esp_dir_structure/BOOTX64.EFI"
    ! [ -d "$espdir/$__esp_dir_structure" ] && mkdir -p "$espdir/$__esp_dir_structure"
    cp "$imgfile" "$espdir/$__esp_dir_structure/BOOTX64.EFI"
fi

$run && log "Starting qemu with OVMF_FD_DIR=$OVMF_FD_DIR"
$run && qemu-system-x86_64 -enable-kvm                                       \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_FD_DIR/OVMF_CODE.fd" \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_FD_DIR/OVMF_VARS.fd" \
    -drive "format=raw,file=fat:rw:$espdir"

if $clear; then
    espdir=$(realpath "$espdir")
    log -l=warn "Removing $espdir"
    if [ -d "$espdir" ]; then rm -rf "$espdir";
    else log -l=warn "$espdir does not exist skipping..."
    fi
fi
