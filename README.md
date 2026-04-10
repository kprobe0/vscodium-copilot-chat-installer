# VSCodium Copilot Chat Installer

This repo installs GitHub Copilot Chat in VSCodium and patches the extension manifest so VSCodium will load it.

The main path is Bash on Linux and macOS. PowerShell is included for Windows, but the Bash flow is the most polished path.

## Fastest Path

Linux or macOS, recommended, copy and paste this:

```bash
curl -fsSL https://raw.githubusercontent.com/kprobe0/vscodium-copilot-chat-installer/main/install.sh | bash
```

That installs Copilot Chat only and downloads the newest compatible build automatically.

If you also want the deprecated base GitHub Copilot extension:

```bash
curl -fsSL https://raw.githubusercontent.com/kprobe0/vscodium-copilot-chat-installer/main/install.sh | bash -s -- --with-copilot
```

If you prefer to clone the repo first:

```bash
git clone https://github.com/kprobe0/vscodium-copilot-chat-installer.git
cd vscodium-copilot-chat-installer
./install.sh
```

If you want the interactive menu instead of the fast path:

```bash
./install.sh --menu
```

## Windows

Windows still uses the PowerShell entrypoint directly:

```powershell
.\scripts\install_vscodium_copilot_chat.ps1 -DownloadLatest
```

Or, if you also want the deprecated base extension:

```powershell
.\scripts\install_vscodium_copilot_chat.ps1 -DownloadLatest -WithCopilot
```

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

## Useful Commands

```bash
./install.sh
./install.sh --with-copilot
./install.sh --menu
./scripts/install_vscodium_copilot_chat.sh --dry-run --download-latest
./scripts/install_vscodium_copilot_chat.sh --skip-install
./scripts/install_vscodium_copilot_chat.sh --uninstall
./scripts/install_vscodium_copilot_chat.sh --uninstall --include-copilot
```

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
- `./install.sh` is the beginner entrypoint. With no arguments it defaults to `--download-latest`.
- `--with-copilot` and `-WithCopilot` opt into the deprecated base GitHub Copilot extension.
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