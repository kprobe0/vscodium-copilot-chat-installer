# VSCodium Copilot Chat Installer

This repo exists to install GitHub Copilot Chat in VSCodium and patch the extension manifest so VSCodium will actually load it.

The main path is the Bash installer on Linux. PowerShell is included for Windows, but Linux is the path that has been exercised the most.

## Recommended Use

If you just want the safest install path, use the marketplace resolver and let the script pick the newest build that matches your VSCodium version.

```bash
chmod +x ./scripts/install_vscodium_copilot_chat.sh
./scripts/install_vscodium_copilot_chat.sh --download-latest
```

That installs Copilot Chat only.

If you also want the deprecated base Copilot extension:

```bash
./scripts/install_vscodium_copilot_chat.sh --download-latest --with-copilot
```

On Windows:

```powershell
.\scripts\install_vscodium_copilot_chat.ps1 -DownloadLatest
```

Or, if you also want the deprecated base extension:

```powershell
.\scripts\install_vscodium_copilot_chat.ps1 -DownloadLatest -WithCopilot
```

If you run either script with no arguments in a real terminal, it opens an interactive menu.

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

## A Few Useful Commands

```bash
./scripts/install_vscodium_copilot_chat.sh --download-latest
./scripts/install_vscodium_copilot_chat.sh --download-latest --with-copilot
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

- `scripts/install_vscodium_copilot_chat.sh`
- `scripts/install_vscodium_copilot_chat.ps1`
- `scripts/install_vscodium_copilot_chat.bat`
- `.github/workflows/validate-installers.yml`

If you want to pin a specific VSIX, pass it directly or place it next to the script.