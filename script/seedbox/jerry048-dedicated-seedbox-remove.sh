#!/bin/sh
tput sgr0; clear

## Load Seedbox Components for utility functions
source <(wget -qO- https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/seedbox_installation.sh)
# Check if Seedbox Components is successfully loaded
if [ $? -ne 0 ]; then
    echo "Component ~Seedbox Components~ failed to load"
    echo "Check connection with GitHub"
    exit 1
fi

## Load loading animation
source <(wget -qO- https://raw.githubusercontent.com/Silejonu/bash_loading_animations/main/bash_loading_animations.sh)
# Check if bash loading animation is successfully loaded
if [ $? -ne 0 ]; then
    fail "Component ~Bash loading animation~ failed to load"
    fail_exit "Check connection with GitHub"
fi
# Run BLA::stop_loading_animation if the script is interrupted
trap BLA::stop_loading_animation SIGINT

## Uninstall function
uninstall_() {
    info_2 "$2"
    BLA::start_loading_animation "${BLA_classic[@]}"
    $1 1> /dev/null 2> $3
    if [ $? -ne 0 ]; then
        warn "Failed: $2"
    else
        info_3 "Successful"
    fi
    BLA::stop_loading_animation
}

## Check root privilege
info "Checking for root privileges"
if [ $(id -u) -ne 0 ]; then 
    fail_exit "This script needs root permission to run"
fi

## Check if qBittorrent is installed
if ! command -v qbittorrent-nox >/dev/null 2>&1; then
    info "qBittorrent is not installed, nothing to uninstall"
    exit 0
fi

## Read input arguments
username=""
while getopts "u:h" opt; do
    case ${opt} in
        u ) # process option username
            username=${OPTARG}
            ;;
        h ) # process option help
            info "Help:"
            info "Usage: ./uninstall_qb_libtorrent.sh -u <username>"
            info "Example: ./uninstall_qb_libtorrent.sh -u jerry048"
            info "Options:"
            need_input "1. -u : Username of the qBittorrent user to remove"
            need_input "2. -h : Display help message"
            exit 0
            ;;
        \? ) 
            info "Help:"
            info_2 "Usage: ./uninstall_qb_libtorrent.sh -u <username>"
            info_2 "Example: ./uninstall_qb_libtorrent.sh -u jerry048"
            exit 1
            ;;
    esac
done

## Prompt for username if not provided
if [ -z "$username" ]; then
    warn "Username is not specified"
    need_input "Please enter the qBittorrent username to remove:"
    read username
fi

## Verify user exists
if ! id -u "$username" >/dev/null 2>&1; then
    fail_exit "User $username does not exist"
fi

## Stop qBittorrent service
info "Stopping qBittorrent service"
uninstall_ "systemctl stop qbittorrent@$username" "Stopping qBittorrent service" "/tmp/qb_stop_error"

## Disable and remove qBittorrent service
uninstall_ "systemctl disable qbittorrent@$username" "Disabling qBittorrent service" "/tmp/qb_disable_error"
uninstall_ "rm -f /etc/systemd/system/qbittorrent@.service" "Removing qBittorrent service file" "/tmp/qb_service_remove_error"
uninstall_ "systemctl daemon-reload" "Reloading systemd daemon" "/tmp/systemd_reload_error"

## Remove qBittorrent and libtorrent binaries
info "Removing qBittorrent and libtorrent binaries"
uninstall_ "apt-get purge -y qbittorrent-nox" "Removing qBittorrent package" "/tmp/qb_purge_error"
uninstall_ "apt-get purge -y libtorrent-rasterbar*" "Removing libtorrent package" "/tmp/libtorrent_purge_error"
uninstall_ "apt-get autoremove -y" "Cleaning up unused dependencies" "/tmp/autoremove_error"

## Remove user and home directory
info "Removing user $username and home directory"
uninstall_ "userdel -r $username" "Removing user $username" "/tmp/userdel_error"

## Remove qBittorrent configuration and temporary files
info "Cleaning up qBittorrent configurations"
uninstall_ "rm -rf /home/$username/.config/qBittorrent" "Removing qBittorrent config" "/tmp/qb_config_remove_error"
uninstall_ "rm -rf /home/$username/.local/share/qBittorrent" "Removing qBittorrent data" "/tmp/qb_data_remove_error"
uninstall_ "rm -f /tmp/qb_error" "Removing qBittorrent error log" "/tmp/qb_error_remove_error"

## Remove system tuning specific to qBittorrent (if applicable)
info "Reverting qBittorrent-specific system tuning"
# Note: Some tunings (e.g., txqueuelen, disk scheduler) are system-wide and not qBittorrent-specific.
# Reverting only those that can be safely reset without affecting other applications.
uninstall_ "sysctl -w net.core.rmem_max=262144 net.core.wmem_max=262144" "Resetting congestion window" "/tmp/congestion_reset_error"

## Finalize
info "qBittorrent and libtorrent uninstallation complete"
info "Please reboot the system to ensure all changes take effect"
exit 0
