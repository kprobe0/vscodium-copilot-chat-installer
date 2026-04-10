# VSCodium Copilot Chat Installer

Small install helpers for getting GitHub Copilot and GitHub Copilot Chat into VSCodium, then patching Copilot Chat so VSCodium will accept the extension's proposed API list.

## What It Does

- Installs both `GitHub.copilot` and `GitHub.copilot-chat`
- Downloads the newest marketplace builds compatible with your target VSCodium version when you are not using a local VSIX
- Supports local VSIX pinning if you want to force a specific build
- Patches `enabledApiProposals` in installed Copilot Chat manifests by stripping version suffixes such as `chatDebug@4`
- Verifies a required set of proposal names after patching
- Removes stale installed versions of the same extension so VSCodium does not keep scanning an incompatible leftover build
- Clears VSCodium extension cache files so the next full restart rescans the extension
- Supports uninstall and patch-only flows

## Status

- Linux Bash install and uninstall paths have been run directly against temporary test directories
- The PowerShell script has been exercised under PowerShell 7 and against temporary directories, but this repo has not been manually verified on a real Windows machine
- The compatibility selector has been verified against VSCodium `1.112.01907`
- A GitHub Actions workflow is included to run the installer on `ubuntu-latest` and `windows-latest`
- Until that workflow has run successfully in the published repo, treat Windows support as provisional

## Repo Contents

- `scripts/install_vscodium_copilot_chat.sh`
- `scripts/install_vscodium_copilot_chat.ps1`
- `scripts/install_vscodium_copilot_chat.bat`
- `.github/workflows/validate-installers.yml`

This repo does not ship Copilot VSIX files. If you want to pin a specific release, place your own `.vsix` files next to the script or pass explicit paths.

## Quick Start

Linux or macOS:

```bash
chmod +x ./scripts/install_vscodium_copilot_chat.sh
./scripts/install_vscodium_copilot_chat.sh --download-latest
```

Windows:

```powershell
.\scripts\install_vscodium_copilot_chat.ps1 -DownloadLatest
```

If you run either script with no arguments in an interactive terminal, it opens a small menu.

## Behavior

Install order is:

1. Explicit VSIX path passed on the command line
2. Local `.vsix` files found in the current directory, script directory, or repo root
3. Marketplace download fallback

`--download-latest` and `-DownloadLatest` mean newest compatible marketplace build, not blindly newest upload.

Use `--code-version` or `-CodeVersion` if you want marketplace compatibility to target a specific VSCodium build instead of reading the version from the local `codium` binary.

## Common Commands

Bash:

```bash
./scripts/install_vscodium_copilot_chat.sh --download-latest
./scripts/install_vscodium_copilot_chat.sh --download-latest --code-version 1.112.01907
./scripts/install_vscodium_copilot_chat.sh --dry-run --download-latest
./scripts/install_vscodium_copilot_chat.sh --skip-install
./scripts/install_vscodium_copilot_chat.sh --uninstall
./scripts/install_vscodium_copilot_chat.sh --uninstall --include-copilot
```

PowerShell:

```powershell
.\scripts\install_vscodium_copilot_chat.ps1 -DownloadLatest
.\scripts\install_vscodium_copilot_chat.ps1 -DownloadLatest -CodeVersion 1.112.01907
.\scripts\install_vscodium_copilot_chat.ps1 -DryRun -DownloadLatest
.\scripts\install_vscodium_copilot_chat.ps1 -SkipInstall
.\scripts\install_vscodium_copilot_chat.ps1 -Uninstall
.\scripts\install_vscodium_copilot_chat.ps1 -Uninstall -IncludeCopilot
```

## Default Paths

Linux user data: `~/.config/VSCodium`
Linux and macOS extensions: `~/.vscode-oss/extensions`
macOS user data: `~/Library/Application Support/VSCodium`
Windows user data: `%APPDATA%\VSCodium`
Windows extensions: `%USERPROFILE%\.vscode-oss\extensions`

## Notes

- Fully quit VSCodium after running the installer. `Reload Window` is not enough.
- `--skip-install` and `-SkipInstall` only repatch an existing install.
- `--uninstall` and `-Uninstall` remove Copilot Chat. Add `--include-copilot` or `-IncludeCopilot` to remove the base Copilot extension too.
- `--download-latest` and `-DownloadLatest` are the safest flags if you do not want an older local VSIX to win and you want the selector to choose the newest compatible build.
- `--code-version` and `-CodeVersion` are useful in CI or on systems where the `codium` CLI is not available.
- `--dry-run` and `-DryRun` validate the flow without touching your real extension directories.
- The installers need outbound HTTPS access to the Visual Studio Marketplace when they are downloading packages.

## CI

The workflow at `.github/workflows/validate-installers.yml` runs the Bash installer on Ubuntu and the PowerShell installer on Windows using temporary directories, then checks install and uninstall results.

That is the only credible way to say the Windows path is covered without personally testing it on a Windows machine.