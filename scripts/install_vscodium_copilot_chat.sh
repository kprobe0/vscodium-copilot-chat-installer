#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
original_arg_count=$#

dry_run=0
allow_running=0
skip_install=0
uninstall_mode=0
install_copilot=0
include_copilot=0
download_latest=0
chat_vsix=""
copilot_vsix=""
download_root=""
download_root_created=0
curl_bin=""
code_version_override="${VSCODIUM_CODE_VERSION:-}"
resolved_code_version=""
user_data_dir="${VSCODIUM_USER_DATA_DIR:-}"
extensions_dir="${VSCODIUM_EXTENSIONS_DIR:-}"
codium_bin="${VSCODIUM_BIN:-}"
# SYNC: keep in sync with $script:RequiredProposals in install_vscodium_copilot_chat.ps1 and the required sets in validate-installers.yml
required_proposals=(
	chatDebug
	chatHooks
	languageModelToolSupportsModel
	findFiles2
	chatParticipantAdditions
	defaultChatParticipant
	aiTextSearchProvider
	chatParticipantPrivate
	chatProvider
	chatSessionsProvider
)
required_proposals_csv="$(IFS=,; printf '%s' "${required_proposals[*]}")"
ui_reset=""
ui_bold=""
ui_dim=""
ui_blue=""
ui_cyan=""
ui_green=""
ui_yellow=""
ui_red=""
ui_gray=""

cleanup_download_root() {
	if [[ $download_root_created -eq 1 && -n "$download_root" && -d "$download_root" ]]; then
		rm -rf "$download_root"
	fi
}

trap cleanup_download_root EXIT

supports_color() {
	[[ -t 1 ]] || return 1
	[[ -z "${NO_COLOR:-}" ]] || return 1
	case "${TERM:-}" in
		""|dumb)
			return 1
			;;
	esac
	return 0
}

init_terminal_style() {
	local colors=""

	if ! supports_color; then
		return 0
	fi

	if command -v tput >/dev/null 2>&1; then
		colors="$(tput colors 2>/dev/null || printf '0')"
		if [[ "$colors" =~ ^[0-9]+$ ]] && (( colors >= 8 )); then
			ui_reset="$(tput sgr0)"
			ui_bold="$(tput bold)"
			ui_dim="$(tput dim 2>/dev/null || printf '')"
			ui_blue="$(tput setaf 4)"
			ui_cyan="$(tput setaf 6)"
			ui_green="$(tput setaf 2)"
			ui_yellow="$(tput setaf 3)"
			ui_red="$(tput setaf 1)"
			ui_gray="$(tput setaf 7)"
			return 0
		fi
	fi

	ui_reset=$'\033[0m'
	ui_bold=$'\033[1m'
	ui_dim=$'\033[2m'
	ui_blue=$'\033[34m'
	ui_cyan=$'\033[36m'
	ui_green=$'\033[32m'
	ui_yellow=$'\033[33m'
	ui_red=$'\033[31m'
	ui_gray=$'\033[37m'
}

print_menu_option() {
	local number="$1"
	local color="$2"
	local label="$3"
	printf '  %s%s)%s %s\n' "$color" "$number" "$ui_reset" "$label"
}

log() {
	printf '%s[info]%s %s\n' "$ui_cyan" "$ui_reset" "$*"
}

warn() {
	printf '%s[warn]%s %s\n' "$ui_yellow" "$ui_reset" "$*" >&2
}

die() {
	printf '%s[error]%s %s\n' "$ui_red" "$ui_reset" "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage: ./scripts/install_vscodium_copilot_chat.sh [options]

Run with no arguments in an interactive terminal to open a menu for install, patch-only, or uninstall actions.

Installs and patches GitHub Copilot Chat for VSCodium by:
	1. Detecting local GitHub Copilot and Copilot Chat VSIX files, or downloading the newest marketplace builds compatible with the target VSCodium version.
	2. Extracting the VSIX files directly into the VSCodium extensions directory.
	3. Stripping version suffixes from enabledApiProposals in installed Copilot Chat manifests.
	4. Verifying core Copilot proposal names such as chatDebug and chatHooks are present after patching.
	5. Clearing VSCodium extension caches so the next launch rescans the patched extension.

By default, the Bash installer installs Copilot Chat only. The deprecated base GitHub Copilot extension is optional and must be requested explicitly.

Options:
	--chat-vsix PATH       Use a specific Copilot Chat VSIX.
	--with-copilot         Also install the deprecated base GitHub Copilot extension.
	--copilot-vsix PATH    Use a specific base GitHub Copilot VSIX and enable base install.
	--download-latest      Skip local VSIX detection and download the newest compatible Copilot packages.
	--code-version VER     Override the target VSCodium version for marketplace compatibility checks.
	--codium-bin PATH      Path to the VSCodium CLI binary.
	--user-data-dir PATH   Override the VSCodium user data directory.
	--extensions-dir PATH  Override the VSCodium extensions directory.
	--uninstall            Remove installed GitHub Copilot Chat files and registry entries.
	--include-copilot      With --uninstall, also remove the base GitHub Copilot extension.
	--skip-install         Do not install a VSIX, only patch existing installed copies.
	--allow-running        Do not stop if VSCodium is currently running.
	--dry-run              Print actions without changing anything.
	-h, --help             Show this help text.
EOF
}

confirm_prompt() {
	local prompt="$1"
	local response
	printf '%s%s [y/N]: %s' "$ui_bold$ui_cyan" "$prompt" "$ui_reset"
	read -r response
	[[ "$response" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}

show_interactive_menu() {
	local selection
	local target_code_version=""
	local local_chat_vsix=""
	local local_copilot_vsix=""

	if [[ $original_arg_count -ne 0 || ! -t 0 || ! -t 1 ]]; then
		return
	fi

	if target_code_version="$(resolve_target_code_version 2>/dev/null)"; then
		:
	else
		target_code_version="unknown"
	fi

	if local_chat_vsix="$(detect_vsix_for_extension 'github.copilot-chat' 2>/dev/null)"; then
		:
	else
		local_chat_vsix=""
	fi

	if local_copilot_vsix="$(detect_vsix_for_extension 'github.copilot' 2>/dev/null)"; then
		:
	else
		local_copilot_vsix=""
	fi

	while true; do
		printf '\n%s%sVSCodium Copilot Chat%s\n' "$ui_blue" "$ui_bold" "$ui_reset"
		printf '  %sTarget Code version:%s %s\n' "$ui_dim" "$ui_reset" "$target_code_version"
		printf '  %sDefault install:%s newest compatible Copilot Chat from the marketplace\n' "$ui_dim" "$ui_reset"
		printf '  %sBase GitHub Copilot:%s optional and deprecated\n' "$ui_dim" "$ui_reset"
		if [[ -n "$local_chat_vsix" ]]; then
			printf '  %sLocal Chat VSIX:%s %s\n' "$ui_dim" "$ui_reset" "$(basename -- "$local_chat_vsix")"
		fi
		if [[ -n "$local_copilot_vsix" ]]; then
			printf '  %sLocal Copilot VSIX:%s %s\n' "$ui_dim" "$ui_reset" "$(basename -- "$local_copilot_vsix")"
		fi
		printf '  %s----------------------------------------%s\n' "$ui_gray" "$ui_reset"
		print_menu_option 1 "$ui_green$ui_bold" 'Install latest compatible Copilot Chat (recommended)'
		print_menu_option 2 "$ui_yellow" 'Install latest compatible Copilot Chat + deprecated GitHub Copilot'
		print_menu_option 3 "$ui_cyan" 'Install Copilot Chat using local VSIX detection'
		print_menu_option 4 "$ui_cyan" 'Patch existing install'
		print_menu_option 5 "$ui_red" 'Uninstall Copilot Chat'
		print_menu_option 6 "$ui_red" 'Uninstall Copilot Chat and GitHub Copilot'
		print_menu_option 7 "$ui_blue" 'Dry-run latest compatible Copilot Chat'
		print_menu_option 8 "$ui_blue" 'Show help'
		print_menu_option 9 "$ui_gray" 'Exit'
		printf '\n%sChoose an option [1-9]: %s' "$ui_bold$ui_cyan" "$ui_reset"
		read -r selection

		case "$selection" in
			1)
				download_latest=1
				break
				;;
			2)
				download_latest=1
				install_copilot=1
				break
				;;
			3)
				if [[ -z "$local_chat_vsix" ]]; then
					warn 'No local Copilot Chat VSIX was detected. Use option 1 to download the newest compatible build.'
					continue
				fi
				break
				;;
			4)
				skip_install=1
				break
				;;
			5)
				uninstall_mode=1
				break
				;;
			6)
				uninstall_mode=1
				include_copilot=1
				break
				;;
			7)
				download_latest=1
				dry_run=1
				break
				;;
			8)
				usage
				;;
			9|q|Q|exit)
				log "Cancelled."
				exit 0
				;;
			*)
				warn "Invalid selection: $selection"
				;;
		esac
	done

	if [[ $uninstall_mode -eq 1 ]]; then
		if ! confirm_prompt 'This will remove installed Copilot extension files. Continue?'; then
			log 'Cancelled.'
			exit 0
		fi
	fi

	if [[ $dry_run -eq 0 && $allow_running -eq 0 ]] && is_vscodium_running; then
		if confirm_prompt 'VSCodium appears to be running. Continue anyway?'; then
			allow_running=1
		else
			die 'Close all VSCodium windows and rerun, or confirm the prompt to continue.'
		fi
	fi
}

run_cmd() {
	if [[ $dry_run -eq 1 ]]; then
		printf '[dry-run]'
		for arg in "$@"; do
			printf ' %q' "$arg"
		done
		printf '\n'
		return 0
	fi
	"$@"
}

require_python() {
	local candidate
	for candidate in python3 python; do
		if ! command -v "$candidate" >/dev/null 2>&1; then
			continue
		fi
		if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info.major >= 3 else 1)' 2>/dev/null; then
			printf '%s\n' "$(command -v "$candidate")"
			return 0
		fi
	done
	die "Python 3 is required for JSON patching."
}

resolve_command() {
	local candidate
	for candidate in "$@"; do
		if [[ -n "$candidate" ]] && command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return 0
		fi
	done
	return 1
}

detect_vsix_for_extension() {
	local extension_id="$1"
	"$python_bin" - "$extension_id" "$PWD" "$SCRIPT_DIR" "$REPO_DIR" <<'PY'
import pathlib
import json
import sys
import zipfile

target_id = sys.argv[1].lower()
roots = [pathlib.Path(item) for item in sys.argv[2:] if item]
candidates = []
seen = set()

for root in roots:
	if not root.exists() or not root.is_dir():
		continue

	for path in root.glob('*.vsix'):
		resolved = str(path.resolve())
		if resolved in seen:
			continue
		seen.add(resolved)

		try:
			with zipfile.ZipFile(path) as archive:
				manifest = json.loads(archive.read('extension/package.json'))
		except Exception:
			continue

		publisher = str(manifest.get('publisher', '')).lower()
		name = str(manifest.get('name', '')).lower()
		version_text = str(manifest.get('version', '0'))
		current_id = f'{publisher}.{name}'
		if current_id != target_id:
			continue

		try:
			version_key = tuple(int(part) for part in version_text.split('.'))
		except ValueError:
			version_key = (0,)

		candidates.append((version_key, resolved))

if not candidates:
    sys.exit(1)

print(max(candidates)[1])
PY
}

resolve_target_code_version() {
	local version_line

	if [[ -n "$resolved_code_version" ]]; then
		printf '%s\n' "$resolved_code_version"
		return 0
	fi

	if [[ -n "$code_version_override" ]]; then
		resolved_code_version="$code_version_override"
		printf '%s\n' "$resolved_code_version"
		return 0
	fi

	[[ -n "$codium_bin" ]] || die "Unable to determine the target VSCodium version for marketplace downloads. Pass --code-version or --codium-bin."
	version_line="$("$codium_bin" --version 2>/dev/null | awk 'NR==1 {print $1; exit}')"
	[[ -n "$version_line" ]] || die "Failed to read the VSCodium version from $codium_bin"

	resolved_code_version="$version_line"
	printf '%s\n' "$resolved_code_version"
}

ensure_download_root() {
	if [[ -n "$download_root" ]]; then
		return 0
	fi

	download_root="$(mktemp -d "${TMPDIR:-/tmp}/vscodium-copilot-downloads.XXXXXX")"
	download_root_created=1
}

download_marketplace_vsix() {
	local extension_id="$1"
	local result_var_name="$2"
	local download_target_root payload metadata_json result version asset_url target_path engine_spec target_code_version
	local -a result_lines=()

	if [[ -z "$curl_bin" ]]; then
		curl_bin="$(resolve_command curl)" || die "curl is required to download Copilot VSIX files from the marketplace."
	fi

	target_code_version="$(resolve_target_code_version)"
	ensure_download_root
	download_target_root="$download_root"
	printf -v payload '{"filters":[{"criteria":[{"filterType":7,"value":"%s"}],"pageNumber":1,"pageSize":1,"sortBy":0,"sortOrder":0}],"assetTypes":[],"flags":103}' "$extension_id"
	metadata_json="$("$curl_bin" -fsSL --connect-timeout 20 --max-time 120 \
		-H 'Content-Type: application/json' \
		-H 'Accept: application/json;api-version=7.2-preview.1' \
		-H 'X-Market-Client-Id: VSCode 1.0' \
		--data "$payload" \
		'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery')"
	result="$(VSCODIUM_INSTALLER_MARKETPLACE_JSON="$metadata_json" \
		"$python_bin" - "$extension_id" "$download_target_root" "$target_code_version" <<'PY'
import json
import os
import pathlib
import sys
import urllib.request

extension_id = sys.argv[1]
download_root = pathlib.Path(sys.argv[2]).expanduser()
target_code_version = sys.argv[3]
body = json.loads(os.environ['VSCODIUM_INSTALLER_MARKETPLACE_JSON'])

def parse_version(text):
    text = str(text).strip().lstrip('v')
    parts = []
    for raw in text.split('.'):
        digits = ''.join(ch for ch in raw if ch.isdigit())
        parts.append(int(digits or '0'))
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])

def upper_for_caret(base):
    if base[0] != 0:
        return (base[0] + 1, 0, 0)
    if base[1] != 0:
        return (0, base[1] + 1, 0)
    return (0, 0, base[2] + 1)

def upper_for_tilde(base):
    return (base[0], base[1] + 1, 0)

def wildcard_range(token):
    token = token.strip()
    if token in {'*', 'x', 'X'}:
        return (0, 0, 0), None
    parts = token.split('.')
    normalized = []
    wildcard_index = None
    for index, part in enumerate(parts):
        if part in {'*', 'x', 'X'}:
            wildcard_index = index
            break
        normalized.append(int(''.join(ch for ch in part if ch.isdigit()) or '0'))
    if wildcard_index is None:
        return None
    while len(normalized) < 3:
        normalized.append(0)
    lower = tuple(normalized[:3])
    if wildcard_index == 0:
        upper = None
    elif wildcard_index == 1:
        upper = (lower[0] + 1, 0, 0)
    else:
        upper = (lower[0], lower[1] + 1, 0)
    return lower, upper

def satisfies_token(token, target):
    token = token.strip()
    if not token or token in {'*', 'x', 'X'}:
        return True
    if token.startswith('^'):
        base = parse_version(token[1:])
        return base <= target < upper_for_caret(base)
    if token.startswith('~'):
        base = parse_version(token[1:])
        return base <= target < upper_for_tilde(base)
    for prefix in ('>=', '<=', '>', '<', '='):
        if token.startswith(prefix):
            version = parse_version(token[len(prefix):])
            if prefix == '>=':
                return target >= version
            if prefix == '<=':
                return target <= version
            if prefix == '>':
                return target > version
            if prefix == '<':
                return target < version
            return target == version
    wildcard = wildcard_range(token)
    if wildcard is not None:
        lower, upper = wildcard
        if upper is None:
            return True
        return lower <= target < upper
    return target == parse_version(token)

def is_compatible(spec, target):
    for group in str(spec).split('||'):
        tokens = [token for token in group.replace(',', ' ').split() if token]
        if all(satisfies_token(token, target) for token in tokens):
            return True
    return False

target = parse_version(target_code_version)
results = body.get('results') or []
extensions = results[0].get('extensions') if results else []
if not extensions:
    print(f'error: extension not found in marketplace: {extension_id}', file=sys.stderr)
    sys.exit(1)

extension = extensions[0]
versions = extension.get('versions') or []
if not versions:
    print(f'error: extension has no versions in marketplace: {extension_id}', file=sys.stderr)
    sys.exit(1)

publisher = str(extension.get('publisher', {}).get('publisherName') or extension_id.split('.', 1)[0]).lower()
name = str(extension.get('extensionName') or extension_id.split('.', 1)[1]).lower()

for version_entry in versions:
    version = str(version_entry.get('version', '')).strip()
    if not version:
        continue
    files = version_entry.get('files') or []
    manifest_url = ''
    asset_url = ''
    for asset in files:
        asset_type = asset.get('assetType')
        source = str(asset.get('source', '')).strip()
        if asset_type == 'Microsoft.VisualStudio.Code.Manifest':
            manifest_url = source
        elif asset_type == 'Microsoft.VisualStudio.Services.VSIXPackage':
            asset_url = source
    if not manifest_url or not asset_url:
        continue
    with urllib.request.urlopen(manifest_url, timeout=60) as response:
        manifest = json.load(response)
    engine_spec = str(manifest.get('engines', {}).get('vscode', '')).strip()
    if not engine_spec:
        continue
    if not is_compatible(engine_spec, target):
        continue
    target_path = download_root / f'{publisher}.{name}-{version}.vsix'
    print(version)
    print(asset_url)
    print(target_path)
    print(engine_spec)
    break
else:
    print(f'error: no compatible marketplace version found for {extension_id} and Code {target_code_version}', file=sys.stderr)
    sys.exit(1)
PY
)"
	mapfile -t result_lines <<<"$result"
	version="${result_lines[0]:-}"
	asset_url="${result_lines[1]:-}"
	target_path="${result_lines[2]:-}"
	engine_spec="${result_lines[3]:-}"

	[[ -n "$target_path" ]] || die "Failed to resolve a marketplace download path for $extension_id"

	mkdir -p "$download_target_root"
	if [[ $dry_run -eq 1 ]]; then
		printf '[info] Downloading %s@%s compatible with Code %s (%s) to a temporary path for dry-run verification\n' "$extension_id" "$version" "$target_code_version" "$engine_spec" >&2
	else
		printf '[info] Downloading %s@%s compatible with Code %s (%s) from the Visual Studio Marketplace\n' "$extension_id" "$version" "$target_code_version" "$engine_spec" >&2
	fi
	"$curl_bin" -fsSL --retry 3 --connect-timeout 20 --max-time 600 -H 'User-Agent: VSCodium Copilot Installer' -o "$target_path" "$asset_url"
	printf '[info] Downloaded %s@%s to %s\n' "$extension_id" "$version" "$target_path" >&2

	printf -v "$result_var_name" '%s' "$target_path"
}

patch_manifest() {
	local manifest_path="$1"
	"$python_bin" - "$manifest_path" "$dry_run" "$required_proposals_csv" <<'PY'
import json
import pathlib
import re
import sys

manifest_path = pathlib.Path(sys.argv[1])
dry_run = sys.argv[2] == '1'
required = [item for item in sys.argv[3].split(',') if item]

data = json.loads(manifest_path.read_text(encoding='utf-8'))
proposals = data.get('enabledApiProposals')

if not isinstance(proposals, list):
	print(f'error:{manifest_path}: enabledApiProposals is not a list', file=sys.stderr)
	sys.exit(1)

changed = False
patched = []
for item in proposals:
	if not isinstance(item, str):
		print(f'error:{manifest_path}: enabledApiProposals contains a non-string entry {item!r}', file=sys.stderr)
		sys.exit(1)
	new_item = re.sub(r'@\d+$', '', item)
	if new_item != item:
		changed = True
	patched.append(new_item)

patched_set = set(patched)
remaining_versioned = sorted(item for item in patched if re.search(r'@\d+$', item))
missing_expected = [item for item in required if item not in patched_set]

if remaining_versioned:
	print(f'error:{manifest_path}: version-pinned proposals remain after normalization: {", ".join(remaining_versioned)}', file=sys.stderr)
if missing_expected:
	print(f'error:{manifest_path}: missing required proposals after normalization: {", ".join(missing_expected)}', file=sys.stderr)
if remaining_versioned or missing_expected:
	sys.exit(1)

data['enabledApiProposals'] = patched
output = json.dumps(data, ensure_ascii=False, indent='\t') + '\n'

status = 'unchanged'
if changed:
	status = 'would-patch' if dry_run else 'patched'

if dry_run:
	print(f'{status}:{manifest_path}')
else:
	if changed:
		manifest_path.write_text(output, encoding='utf-8')
	print(f'{status}:{manifest_path}')

print(f'verified:{manifest_path}: required proposals present and unpinned')
PY
}

is_vscodium_running() {
	pgrep -x codium >/dev/null 2>&1 || pgrep -x VSCodium >/dev/null 2>&1
}

install_vsix() {
	local extension_vsix="$1"
	[[ -n "$extension_vsix" ]] || return 0
	log "Installing $(basename -- "$extension_vsix") into the VSCodium extensions directory"
	"$python_bin" - "$extension_vsix" "$extensions_dir" "$dry_run" <<'PY'
import json
import pathlib
import shutil
import sys
import tempfile
import time
import zipfile

vsix_path = pathlib.Path(sys.argv[1]).expanduser().resolve()
extensions_dir = pathlib.Path(sys.argv[2]).expanduser().resolve()
dry_run = sys.argv[3] == '1'

with zipfile.ZipFile(vsix_path) as archive:
	try:
		manifest = json.loads(archive.read('extension/package.json'))
	except KeyError as exc:
		print(f'error:{vsix_path}: VSIX is missing extension/package.json ({exc})', file=sys.stderr)
		sys.exit(1)

publisher = str(manifest.get('publisher', '')).lower()
name = str(manifest.get('name', '')).lower()
version = str(manifest.get('version', ''))

if not publisher or not name or not version:
	print(f'error:{vsix_path}: VSIX manifest is missing publisher, name, or version', file=sys.stderr)
	sys.exit(1)

extension_id = f'{publisher}.{name}'
relative_location = f'{extension_id}-{version}'
target_dir = extensions_dir / relative_location
registry_path = extensions_dir / 'extensions.json'

if dry_run:
	print(f'would-install:{target_dir}')
	sys.exit(0)

temp_root = pathlib.Path(tempfile.mkdtemp(prefix='vscodium-copilot-'))
backup_dir = target_dir.with_name(f'{target_dir.name}.bak-{int(time.time() * 1000)}')

try:
	with zipfile.ZipFile(vsix_path) as archive:
		archive.extractall(temp_root)

	source_dir = temp_root / 'extension'
	if not source_dir.is_dir():
		raise RuntimeError(f'extracted VSIX is missing the extension directory: {vsix_path}')

	if target_dir.exists():
		if backup_dir.exists():
			shutil.rmtree(backup_dir, ignore_errors=True)
		target_dir.replace(backup_dir)

	shutil.move(str(source_dir), str(target_dir))

	entries = []
	if registry_path.exists():
		try:
			loaded_entries = json.loads(registry_path.read_text(encoding='utf-8'))
			if isinstance(loaded_entries, list):
				entries = loaded_entries
		except json.JSONDecodeError:
			entries = []

	entries = [
		entry for entry in entries
		if not (isinstance(entry, dict) and entry.get('identifier', {}).get('id') == extension_id)
	]

	resolved_target = target_dir.resolve()
	entries.append({
		'identifier': {'id': extension_id},
		'version': version,
		'location': {
			'$mid': 1,
			'fsPath': str(resolved_target),
			'external': resolved_target.as_uri(),
			'path': str(resolved_target),
			'scheme': 'file',
		},
		'relativeLocation': relative_location,
		'metadata': {
			'isApplicationScoped': False,
			'isMachineScoped': False,
			'isBuiltin': False,
			'installedTimestamp': int(time.time() * 1000),
			'pinned': True,
			'source': 'vsix',
		},
	})
	registry_path.write_text(json.dumps(entries, ensure_ascii=False), encoding='utf-8')

	if backup_dir.exists():
		shutil.rmtree(backup_dir, ignore_errors=True)

	for sibling in extensions_dir.glob(f'{extension_id}-*'):
		if sibling == target_dir or not sibling.is_dir():
			continue
		shutil.rmtree(sibling, ignore_errors=True)

	print(f'installed:{target_dir}')
except Exception as exc:
	if target_dir.exists():
		shutil.rmtree(target_dir, ignore_errors=True)
	if backup_dir.exists() and not target_dir.exists():
		backup_dir.replace(target_dir)
	print(f'error:{vsix_path}: {exc}', file=sys.stderr)
	sys.exit(1)
finally:
	shutil.rmtree(temp_root, ignore_errors=True)
PY
}

remove_registry_entries() {
	local extension_ids_csv="$1"
	local registry_path="$extensions_dir/extensions.json"
	"$python_bin" - "$registry_path" "$extension_ids_csv" "$dry_run" <<'PY'
import json
import pathlib
import sys

registry_path = pathlib.Path(sys.argv[1]).expanduser().resolve()
extension_ids = {item for item in sys.argv[2].split(',') if item}
dry_run = sys.argv[3] == '1'

if not registry_path.exists():
    print(f'no-registry:{registry_path}')
    sys.exit(0)

try:
    raw = registry_path.read_text(encoding='utf-8').strip()
    entries = json.loads(raw) if raw else []
except json.JSONDecodeError as exc:
    print(f'error:{registry_path}: invalid JSON in extensions registry ({exc})', file=sys.stderr)
    sys.exit(1)

if not isinstance(entries, list):
    print(f'error:{registry_path}: extensions registry is not a list', file=sys.stderr)
    sys.exit(1)

removed = [
    entry for entry in entries
    if isinstance(entry, dict) and entry.get('identifier', {}).get('id') in extension_ids
]
kept = [entry for entry in entries if entry not in removed]

if dry_run:
    print(f'would-update-registry:{registry_path}: remove {len(removed)} entries')
    sys.exit(0)

if removed:
    registry_path.write_text(json.dumps(kept, ensure_ascii=False), encoding='utf-8')
    print(f'updated-registry:{registry_path}: removed {len(removed)} entries')
else:
    print(f'unchanged-registry:{registry_path}')
PY
}

uninstall_extensions() {
	local patterns=("github.copilot-chat-*")
	local registry_ids=("github.copilot-chat")
	local removed_any=0

	if [[ $include_copilot -eq 1 ]]; then
		patterns+=("github.copilot-[0-9]*")
		registry_ids+=("github.copilot")
	fi

	for pattern in "${patterns[@]}"; do
		for extension_dir in "$extensions_dir"/$pattern; do
			[[ -d "$extension_dir" ]] || continue
			removed_any=1
			log "Removing $extension_dir"
			run_cmd rm -rf "$extension_dir"
		done
	done

	if [[ $removed_any -eq 0 ]]; then
		log "No matching installed extensions were found under $extensions_dir"
	fi

	remove_registry_entries "$(IFS=,; printf '%s' "${registry_ids[*]}")"
	clear_extension_caches
	log "Completed uninstall. Fully quit and reopen VSCodium if it was running."
}

clear_extension_caches() {
	local cache_root="$user_data_dir/CachedProfilesData"
	local found_cache=0
	if [[ -d "$cache_root" ]]; then
		while IFS= read -r cache_path; do
			found_cache=1
			run_cmd rm -f "$cache_path"
		done < <(find "$cache_root" -type f -name 'extensions.user.cache' 2>/dev/null)
	fi
	if [[ $found_cache -eq 0 ]]; then
		log "No extensions.user.cache files found under $cache_root"
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--chat-vsix)
			[[ $# -ge 2 ]] || die "--chat-vsix requires a path"
			chat_vsix="$2"
			shift 2
			;;
		--copilot-vsix)
			[[ $# -ge 2 ]] || die "--copilot-vsix requires a path"
			install_copilot=1
			copilot_vsix="$2"
			shift 2
			;;
		--with-copilot)
			install_copilot=1
			shift
			;;
		--codium-bin)
			[[ $# -ge 2 ]] || die "--codium-bin requires a path"
			codium_bin="$2"
			shift 2
			;;
		--code-version)
			[[ $# -ge 2 ]] || die "--code-version requires a version string"
			code_version_override="$2"
			shift 2
			;;
		--user-data-dir)
			[[ $# -ge 2 ]] || die "--user-data-dir requires a path"
			user_data_dir="$2"
			shift 2
			;;
		--extensions-dir)
			[[ $# -ge 2 ]] || die "--extensions-dir requires a path"
			extensions_dir="$2"
			shift 2
			;;
		--uninstall)
			uninstall_mode=1
			shift
			;;
		--include-copilot)
			include_copilot=1
			shift
			;;
		--skip-install)
			skip_install=1
			shift
			;;
		--download-latest)
			download_latest=1
			shift
			;;
		--allow-running)
			allow_running=1
			shift
			;;
		--dry-run)
			dry_run=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "Unknown argument: $1"
			;;
	esac
done

init_terminal_style

if [[ $uninstall_mode -eq 1 && $skip_install -eq 1 ]]; then
	die "Use either --uninstall or --skip-install, not both."
fi

if [[ $download_latest -eq 1 && $skip_install -eq 1 ]]; then
	die "Use either --download-latest or --skip-install, not both."
fi

if [[ $include_copilot -eq 1 && $uninstall_mode -eq 0 ]]; then
	die "--include-copilot can only be used with --uninstall."
fi

if [[ $install_copilot -eq 1 && $uninstall_mode -eq 1 ]]; then
	die "--with-copilot and --copilot-vsix are install options. Use --include-copilot with --uninstall."
fi

if [[ $download_latest -eq 1 && $uninstall_mode -eq 1 ]]; then
	die "--download-latest cannot be used with --uninstall."
fi

python_bin="$(require_python)"

if [[ -z "$user_data_dir" || -z "$extensions_dir" ]]; then
	case "$(uname -s)" in
		Linux)
			user_data_dir="${user_data_dir:-$HOME/.config/VSCodium}"
			extensions_dir="${extensions_dir:-$HOME/.vscode-oss/extensions}"
			;;
		Darwin)
			user_data_dir="${user_data_dir:-$HOME/Library/Application Support/VSCodium}"
			extensions_dir="${extensions_dir:-$HOME/.vscode-oss/extensions}"
			;;
		*)
			die "Unsupported platform for this script. Use the PowerShell script on Windows."
			;;
	esac
fi

if [[ -z "$codium_bin" ]]; then
	if resolved_codium="$(resolve_command codium codium-insiders vscodium)"; then
		codium_bin="$resolved_codium"
	fi
fi

show_interactive_menu

if [[ $dry_run -eq 0 && $allow_running -eq 0 ]] && is_vscodium_running; then
	die "Close all VSCodium windows before running this installer, or pass --allow-running."
fi

if [[ $uninstall_mode -eq 0 ]]; then
	mkdir -p "$extensions_dir"
fi

if [[ $uninstall_mode -eq 1 ]]; then
	log "Uninstall requested. The script will remove installed extension directories, update the registry, and clear caches."
	uninstall_extensions
	exit 0
fi

if [[ $skip_install -eq 0 && $download_latest -eq 0 && -z "$chat_vsix" ]]; then
	if detected_chat_vsix="$(detect_vsix_for_extension 'github.copilot-chat' 2>/dev/null)"; then
		chat_vsix="$detected_chat_vsix"
	fi
fi

if [[ $install_copilot -eq 1 && $skip_install -eq 0 && $download_latest -eq 0 && -z "$copilot_vsix" ]]; then
	if detected_copilot_vsix="$(detect_vsix_for_extension 'github.copilot' 2>/dev/null)"; then
		copilot_vsix="$detected_copilot_vsix"
	fi
fi

if [[ $skip_install -eq 0 && -z "$chat_vsix" ]]; then
	download_marketplace_vsix 'GitHub.copilot-chat' chat_vsix
fi

if [[ $install_copilot -eq 1 && $skip_install -eq 0 && -z "$copilot_vsix" ]]; then
	download_marketplace_vsix 'GitHub.copilot' copilot_vsix
fi

if [[ -n "$chat_vsix" && ! -f "$chat_vsix" ]]; then
	die "Chat VSIX not found: $chat_vsix"
fi

if [[ -n "$copilot_vsix" && ! -f "$copilot_vsix" ]]; then
	die "Copilot VSIX not found: $copilot_vsix"
fi

if [[ $skip_install -eq 0 ]]; then
	[[ -n "$chat_vsix" ]] || die "No Copilot Chat VSIX was found or downloaded. Pass --chat-vsix, keep a local VSIX nearby, or check marketplace connectivity."
	if [[ $install_copilot -eq 1 ]]; then
		[[ -n "$copilot_vsix" ]] || die "No GitHub Copilot VSIX was found or downloaded. Pass --copilot-vsix, keep a local VSIX nearby, or check marketplace connectivity."
		log "Install requested. The script will install GitHub Copilot Chat and the deprecated base GitHub Copilot extension, patch installed manifests, verify them, and clear caches."
		install_vsix "$copilot_vsix"
	else
		log "Install requested. The script will install GitHub Copilot Chat, patch installed manifests, verify them, and clear caches."
	fi
	install_vsix "$chat_vsix"
fi

chat_manifests=()
for extension_dir in "$extensions_dir"/github.copilot-chat-*; do
	if [[ -d "$extension_dir" && -f "$extension_dir/package.json" ]]; then
		chat_manifests+=("$extension_dir/package.json")
	fi
done

if [[ ${#chat_manifests[@]} -eq 0 ]]; then
	die "No installed github.copilot-chat directories were found under $extensions_dir"
fi

for manifest_path in "${chat_manifests[@]}"; do
	log "Patching $(dirname -- "$manifest_path")"
	patch_manifest "$manifest_path"
done

clear_extension_caches

log "Completed. Fully quit and reopen VSCodium so it rescans the patched extension."
if [[ $dry_run -eq 1 ]]; then
	log "Dry run only. No files were changed."
fi