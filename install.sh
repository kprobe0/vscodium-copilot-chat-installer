#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_RAW_BASE_URL="https://raw.githubusercontent.com/kprobe0/vscodium-copilot-chat-installer/main"
raw_base_url="${VSCODIUM_COPILOT_INSTALLER_RAW_BASE_URL:-$DEFAULT_RAW_BASE_URL}"

bootstrap_log() {
	printf '[bootstrap] %s\n' "$*"
}

bootstrap_die() {
	printf '[bootstrap:error] %s\n' "$*" >&2
	exit 1
}

resolve_fetcher() {
	if command -v curl >/dev/null 2>&1; then
		printf 'curl\n'
		return 0
	fi
	if command -v wget >/dev/null 2>&1; then
		printf 'wget\n'
		return 0
	fi
	return 1
}

download_file() {
	local fetcher="$1"
	local url="$2"
	local destination="$3"

	case "$fetcher" in
		curl)
			curl -fsSL "$url" -o "$destination"
			;;
		wget)
			wget -qO "$destination" "$url"
			;;
		*)
			bootstrap_die "Unsupported downloader: $fetcher"
			;;
	esac
}

main() {
	local source_path="${BASH_SOURCE[0]:-}"
	local bootstrap_dir=""
	local local_installer=""
	local remote_installer_url=""
	local temp_dir=""
	local fetcher=""
	local -a args=("$@")

	if [[ ${#args[@]} -eq 1 && ( "${args[0]}" == "--menu" || "${args[0]}" == "--interactive" ) ]]; then
		args=()
	fi

	if [[ ${#args[@]} -eq 0 ]]; then
		bootstrap_log "No arguments supplied. Running the recommended install path (--download-latest). Use --menu for the interactive installer."
		args=(--download-latest)
	fi

	if [[ -n "$source_path" ]] && bootstrap_dir="$(cd -- "$(dirname -- "$source_path")" 2>/dev/null && pwd)"; then
		local_installer="$bootstrap_dir/scripts/install_vscodium_copilot_chat.sh"
		if [[ -f "$local_installer" ]]; then
			bash "$local_installer" "${args[@]}"
			exit $?
		fi
	fi

	fetcher="$(resolve_fetcher)" || bootstrap_die 'curl or wget is required to download the installer.'
	temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/vscodium-copilot-bootstrap.XXXXXX")" || bootstrap_die 'Failed to create a temporary directory.'
	trap 'rm -rf "$temp_dir"' EXIT

	remote_installer_url="$raw_base_url/scripts/install_vscodium_copilot_chat.sh"
	bootstrap_log "Fetching installer from GitHub"
	download_file "$fetcher" "$remote_installer_url" "$temp_dir/install_vscodium_copilot_chat.sh" || bootstrap_die "Failed to download installer from $remote_installer_url"
	chmod +x "$temp_dir/install_vscodium_copilot_chat.sh"
	bash "$temp_dir/install_vscodium_copilot_chat.sh" "${args[@]}"
}

main "$@"