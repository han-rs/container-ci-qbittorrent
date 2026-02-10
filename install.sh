#!/bin/sh

set -e

# * Directories setting
# *
# * This should be kept in sync with the one in assets/qbt.container.
QUADLET_DIRECTORY="$HOME/.config/containers/systemd"
LOCAL_DIRECTORY="$HOME/.local/share/qBittorrent"
LOCAL_DIRECTORY_CONF="$LOCAL_DIRECTORY/config"
LOCAL_DIRECTORY_DATA="$LOCAL_DIRECTORY/data"

NC='\033[0m'

log_error() {
	RED='\033[0;31m'
	echo "${RED}$1${NC}"
}

log_success() {
	GREEN='\033[0;32m'
	echo "${GREEN}$1${NC}"
}

log_warning() {
	YELLOW='\033[1;33m'
	echo "${YELLOW}$1${NC}"
}

log_info() {
	BLUE='\033[0;34m'
	echo "${BLUE}$1${NC}"
}

# * Function to safely copy config file with backup
copy() {
	local src="$1"
	local dest="$2"

	# Check if source file or directory exists
	if [ ! -e "$src" ]; then
		log_error "Error: ${src} does not exist."
		exit 1
	fi

	# Check if config already exists
	if [ -e "$dest" ]; then
		log_warning "Warning: Existing ${dest} will be backed up"
		rm -rf "${dest}.bak"
		mv "$dest" "${dest}.bak"
	fi

	cp -rf "$src" "$dest"
}

# * Check if podman is installed
if ! command -v podman >/dev/null 2>&1; then
	log_error "Error: podman is not installed. Please install podman first."
	exit 1
fi

# * Check if is root, cannot run as root
if [ "$(id -u)" -eq 0 ]; then
	log_error "Error: This script is for rootless deployment. Please run as a regular user."
	exit 1
fi

# * Parse command line arguments
UPDATE_CONF=${UPDATE_CONF:-"false"}
UPGRADE=${UPGRADE:-"false"}
FULL_UPGRADE=${FULL_UPGRADE:-"false"}
NONINTERACTIVE=${NONINTERACTIVE:-"false"}

for arg in "$@"; do
	case $arg in
	--update-conf)
		UPDATE_CONF="true"
		shift
		;;
	--upgrade)
		UPGRADE="true"
		shift
		;;
	--full-upgrade)
		UPGRADE="true"
		FULL_UPGRADE="true"
		shift
		;;
	--noninteractive)
		NONINTERACTIVE="true"
		shift
		;;
	esac
done

log_info "All directories and configuration file paths are set to the following values:"
log_info "  - Quadlet configuration directory for current user: ${QUADLET_DIRECTORY}"
log_info "  - Directory for qBittorrent: ${LOCAL_DIRECTORY}"
log_info "    - Configuration: ${LOCAL_DIRECTORY_CONF}"
log_info "    - Data: ${LOCAL_DIRECTORY_DATA}"
log_info ""

if [ "$UPDATE_CONF" = "true" ]; then
	log_info "Updating configuration files..."

	copy ./assets/qBittorrent.conf "${LOCAL_DIRECTORY_CONF}/qBittorrent.conf"

	systemctl --user restart qbt

	log_success "Configuration files updated successfully."

	exit 0
fi

log_info "Pulling image..."

if ! podman pull ghcr.io/han-rs/container-ci-qbittorrent:latest; then
	log_error "Error: Failed to pull image."
	exit 1
fi

if [ "$UPGRADE" = "true" ]; then
	if [ "$FULL_UPGRADE" = "true" ]; then
		log_info "Overwriting existing configuration with defaults..."

		copy ./assets/qbt.container ~/.config/containers/systemd/qbt.container

		copy ./assets/qBittorrent.conf "${LOCAL_DIRECTORY_CONF}/qBittorrent.conf"

		systemctl --user daemon-reload
	fi

	log_info "Restarting qBittorrent service, this may take a while..."

	systemctl --user restart qbt

	log_success "Service restarted!"

	exit 0
fi

log_info "Setting up directories..."
mkdir -p "$LOCAL_DIRECTORY"

log_info "Copying default configuration files..."
mkdir -p "$LOCAL_DIRECTORY_CONF"
copy ./assets/qBittorrent.conf "${LOCAL_DIRECTORY_CONF}/qBittorrent.conf"

log_info "Prepare other directories..."
mkdir -p "$LOCAL_DIRECTORY_DATA"

log_info "Installing default quadlet configuration..."
mkdir -p "$QUADLET_DIRECTORY"
copy ./assets/qbt.container "${QUADLET_DIRECTORY}/qbt.container"

# * Edit if necessary (skip if --noninteractive is passed)
if [ "$NONINTERACTIVE" != "true" ]; then
	log_info "Editing configuration accordingly..."

	${EDITOR:-nano} "${QUADLET_DIRECTORY}/qbt.container"
	${EDITOR:-nano} "${LOCAL_DIRECTORY_CONF}/qBittorrent.conf"
else
	log_warning "Warning: Skipping configuration editing in non interactive mode."
	log_warning "Please edit the following files manually if needed:"
	log_warning "  - ${QUADLET_DIRECTORY}/qbt.container"
	log_warning "  - ${LOCAL_DIRECTORY_CONF}/qBittorrent.conf"
fi

# * Check if linger is already enabled
if ! loginctl show-user $USER --property=Linger | grep -q "Linger=yes"; then
	if [ "$NONINTERACTIVE" = "true" ]; then
		log_warning "Warning: Linger not enabled for user. Please run manually: sudo loginctl enable-linger $USER"
	else
		log_info "Enabling linger for user..."

		sudo loginctl enable-linger $USER
	fi
fi

log_info "Starting qBittorrent service..."

systemctl --user daemon-reload
systemctl --user start qbt

log_success "Done! Check service status with: systemctl --user status qbt"
