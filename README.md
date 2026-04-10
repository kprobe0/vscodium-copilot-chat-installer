# VSCodium Copilot Chat Installer

> Install GitHub Copilot Chat in VSCodium and patch the extension manifest so VSCodium actually loads it.

The main path is Bash on Linux and macOS. PowerShell is included for Windows, but the Bash flow is the most polished path.

## Quick Start

Linux or macOS, recommended:

```bash
curl -fsSL https://raw.githubusercontent.com/kprobe0/vscodium-copilot-chat-installer/main/install.sh | bash
```

That opens the interactive installer menu first, which is the safest default for most users.

## Choose Your Path

### Linux and macOS

| What you want | Command |
| --- | --- |
| Open the interactive menu | `curl -fsSL https://raw.githubusercontent.com/kprobe0/vscodium-copilot-chat-installer/main/install.sh | bash` |
| Direct install, Copilot Chat only | `curl -fsSL https://raw.githubusercontent.com/kprobe0/vscodium-copilot-chat-installer/main/install.sh | bash -s -- --download-latest` |
| Direct install with deprecated base Copilot too | `curl -fsSL https://raw.githubusercontent.com/kprobe0/vscodium-copilot-chat-installer/main/install.sh | bash -s -- --download-latest --with-copilot` |

If you prefer to clone the repo first:

```bash
git clone https://github.com/kprobe0/vscodium-copilot-chat-installer.git
cd vscodium-copilot-chat-installer
```

Then use one of these:

| What you want | Command |
| --- | --- |
| Open the interactive menu | `./install.sh` |
| Direct install, Copilot Chat only | `./install.sh --download-latest` |
| Direct install with deprecated base Copilot too | `./install.sh --download-latest --with-copilot` |

### Windows

Windows still uses the PowerShell entrypoint directly:

| What you want | Command |
| --- | --- |
| Direct install, Copilot Chat only | `./scripts/install_vscodium_copilot_chat.ps1 -DownloadLatest` |
| Direct install with deprecated base Copilot too | `./scripts/install_vscodium_copilot_chat.ps1 -DownloadLatest -WithCopilot` |

## Why This Exists

VSCodium can install Copilot Chat, but the extension will not load cleanly unless its proposed API entries are normalized for the VSCodium build you are running.

This repo handles the two annoying parts for you:

- getting a compatible Copilot Chat build
- patching the manifest so VSCodium will actually load it

## What The Scripts Do

- install `github.copilot-chat` by default
- optionally install the deprecated base `github.copilot` extension
- use explicit VSIX paths first, then nearby local `.vsix` files, then the marketplace
- when downloading from the marketplace, pick the newest version compatible with the target VSCodium build
- patch `enabledApiProposals` by stripping version suffixes like `chatDebug@4`
- verify the required proposal names are still present after patching
- remove stale installed versions of the same extension
- clear VSCodium extension cache files so the next full restart rescans the install
- support patch-only, dry-run, and uninstall flows

## Common Commands

### Bash

```bash
./install.sh
./install.sh --menu
./install.sh --download-latest
./install.sh --download-latest --with-copilot
./scripts/install_vscodium_copilot_chat.sh --dry-run --download-latest
./scripts/install_vscodium_copilot_chat.sh --skip-install
./scripts/install_vscodium_copilot_chat.sh --uninstall
./scripts/install_vscodium_copilot_chat.sh --uninstall --include-copilot
```

### PowerShell

```powershell
.\scripts\install_vscodium_copilot_chat.ps1 -DownloadLatest
.\scripts\install_vscodium_copilot_chat.ps1 -DownloadLatest -WithCopilot
.\scripts\install_vscodium_copilot_chat.ps1 -DryRun -DownloadLatest
.\scripts\install_vscodium_copilot_chat.ps1 -SkipInstall
.\scripts\install_vscodium_copilot_chat.ps1 -Uninstall
.\scripts\install_vscodium_copilot_chat.ps1 -Uninstall -IncludeCopilot
```

## Notes

- `--download-latest` and `-DownloadLatest` mean newest compatible marketplace build, not newest upload.
- The Bash menu defaults to Copilot Chat from the marketplace. Base Copilot is optional.
- `./install.sh` is the beginner entrypoint. With no arguments it opens the interactive menu.
- The one-line `curl ... | bash` path also opens the interactive menu by default.
- `--with-copilot` and `-WithCopilot` opt into the deprecated base GitHub Copilot extension.
- Use `--download-latest` when you want a non-interactive install.
- `--skip-install` and `-SkipInstall` only repatch an existing install.
- `--uninstall` and `-Uninstall` remove Copilot Chat. Add `--include-copilot` or `-IncludeCopilot` to remove the base Copilot extension too.
- `--code-version`, `-CodeVersion`, and `VSCODIUM_CODE_VERSION` are there for CI or for systems where `codium` is not available on `PATH`.
- Fully quit VSCodium after running the installer. `Reload Window` is not enough.
- The installers need outbound HTTPS access when they download packages from the marketplace.

## Status

- Bash install, uninstall, and dry-run paths have been tested against temporary directories.
- The compatibility selector has been verified against VSCodium `1.112.01907`.
- The PowerShell path has been exercised under PowerShell 7 and in CI-style temp-directory runs.
- Windows has not been manually tested on a real Windows machine yet.

## Files

- `install.sh`
- `scripts/install_vscodium_copilot_chat.sh`
- `scripts/install_vscodium_copilot_chat.ps1`
- `scripts/install_vscodium_copilot_chat.bat`
- `.github/workflows/validate-installers.yml`

If you want to pin a specific VSIX, pass it directly or place it next to the script.