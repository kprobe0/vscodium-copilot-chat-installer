[CmdletBinding()]
param(
	[string]$ChatVsix,
	[string]$CopilotVsix,
	[string]$CodiumBin,
	[string]$CodeVersion = $env:VSCODIUM_CODE_VERSION,
	[string]$UserDataDir = $env:VSCODIUM_USER_DATA_DIR,
	[string]$ExtensionsDir = $env:VSCODIUM_EXTENSIONS_DIR,
	[switch]$Uninstall,
	[switch]$WithCopilot,
	[switch]$IncludeCopilot,
	[switch]$SkipInstall,
	[switch]$DownloadLatest,
	[switch]$AllowRunning,
	[switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:OriginalArgumentCount = $PSBoundParameters.Count

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$script:DownloadRoot = $null
$script:CreatedDownloadRoot = $false
$script:ResolvedCodeVersion = $null
$script:RequiredProposals = @(
	'chatDebug',
	'chatHooks',
	'languageModelToolSupportsModel',
	'findFiles2',
	'chatParticipantAdditions',
	'defaultChatParticipant',
	'aiTextSearchProvider',
	'chatParticipantPrivate',
	'chatProvider',
	'chatSessionsProvider'
)

if ($CopilotVsix) {
	$WithCopilot = $true
}

function Write-Info {
	param([string]$Message)
	Write-Host "[info] $Message"
}

function Write-WarnMsg {
	param([string]$Message)
	Write-Warning $Message
}

function Fail {
	param([string]$Message)
	throw $Message
}

function Show-Usage {
	@'
Usage: .\scripts\install_vscodium_copilot_chat.ps1 [options]

Run with no arguments in an interactive terminal to open a menu for install, patch-only, or uninstall actions.

When no local VSIX is found, the installer downloads the newest marketplace builds compatible with the target VSCodium version.

Common options:
  -ChatVsix PATH
	-WithCopilot
  -CopilotVsix PATH
	-CodeVersion VER
	-DownloadLatest
  -UserDataDir PATH
  -ExtensionsDir PATH
  -SkipInstall
  -Uninstall
  -IncludeCopilot
  -AllowRunning
  -DryRun
'@ | Write-Host
}

function Confirm-YesNo {
	param([string]$Prompt)

	$response = Read-Host "$Prompt [y/N]"
	return $response -match '^(y|yes)$'
}

function Test-InteractiveConsole {
	try {
		return (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
	} catch {
		return $true
	}
}

function Show-InteractiveMenu {
	if ($script:OriginalArgumentCount -ne 0 -or -not (Test-InteractiveConsole)) {
		return
	}

	while ($true) {
		Write-Host ''
		Write-Host 'VSCodium Copilot Chat'
		Write-Host '  1) Install and patch'
		Write-Host '  2) Patch existing install'
		Write-Host '  3) Uninstall Copilot Chat'
		Write-Host '  4) Uninstall Copilot Chat and GitHub Copilot'
		Write-Host '  5) Dry-run install and patch'
		Write-Host '  6) Show help'
		Write-Host '  7) Exit'
		Write-Host ''

		$selection = Read-Host 'Choose an option [1-7]'
		switch ($selection) {
			'1' { break }
			'2' { $SkipInstall = $true; break }
			'3' { $Uninstall = $true; break }
			'4' { $Uninstall = $true; $IncludeCopilot = $true; break }
			'5' { $DryRun = $true; break }
			'6' { Show-Usage; continue }
			'7' { Write-Info 'Cancelled.'; exit 0 }
			'q' { Write-Info 'Cancelled.'; exit 0 }
			'Q' { Write-Info 'Cancelled.'; exit 0 }
			'exit' { Write-Info 'Cancelled.'; exit 0 }
			default { Write-WarnMsg "Invalid selection: $selection" }
		}
	}

	if ($Uninstall) {
		if (-not (Confirm-YesNo 'This will remove installed Copilot extension files. Continue?')) {
			Write-Info 'Cancelled.'
			exit 0
		}
	}

	if (-not $DryRun -and -not $AllowRunning) {
		$running = @(Get-Process -Name 'codium', 'VSCodium' -ErrorAction SilentlyContinue)
		if ($running.Count -gt 0) {
			if (Confirm-YesNo 'VSCodium appears to be running. Continue anyway?') {
				$AllowRunning = $true
			} else {
				Fail 'Close all VSCodium windows and rerun, or confirm the prompt to continue.'
			}
		}
	}
}

function Invoke-Step {
	param([scriptblock]$Action, [string]$Description)
	if ($DryRun) {
		Write-Host "[dry-run] $Description"
		return
	}
	& $Action
}

function Resolve-CodiumBin {
	param([string]$RequestedPath)

	if ($RequestedPath) {
		if (Test-Path -LiteralPath $RequestedPath) {
			return (Resolve-Path -LiteralPath $RequestedPath).Path
		}
		Fail "VSCodium CLI not found at $RequestedPath"
	}

	$commandNames = @('codium.cmd', 'codium', 'codium.exe', 'vscodium.cmd', 'vscodium.exe')
	foreach ($name in $commandNames) {
		$command = Get-Command $name -ErrorAction SilentlyContinue
		if ($command) {
			return $command.Source
		}
	}

	$candidates = @(
		"$env:LOCALAPPDATA\Programs\VSCodium\bin\codium.cmd",
		"$env:ProgramFiles\VSCodium\bin\codium.cmd",
		"$env:ProgramFiles(x86)\VSCodium\bin\codium.cmd"
	)

	foreach ($candidate in $candidates) {
		if ($candidate -and (Test-Path -LiteralPath $candidate)) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}

	return $null
}

function Find-VsixByExtensionId {
	param([string]$ExtensionId)

	$candidates = @()
	$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	$roots = @((Get-Location).Path, $ScriptDir, $RepoDir)

	foreach ($root in $roots) {
		if (-not $root -or -not (Test-Path -LiteralPath $root)) {
			continue
		}

		foreach ($path in Get-ChildItem -LiteralPath $root -Filter '*.vsix' -File -ErrorAction SilentlyContinue) {
			$resolved = $path.FullName
			if (-not $seen.Add($resolved)) {
				continue
			}

			try {
				$metadata = Get-VsixMetadata -VsixPath $resolved
			} catch {
				continue
			}

			if ($metadata.Id -ne $ExtensionId) {
				continue
			}

			try {
				$versionKey = [version]$metadata.Version
			} catch {
				$versionKey = [version]'0.0.0'
			}

			$candidates += [pscustomobject]@{
				Path = $resolved
				Version = $versionKey
			}
		}
	}

	if (-not $candidates) {
		return $null
	}

	return ($candidates | Sort-Object Version | Select-Object -Last 1 -ExpandProperty Path)
}

function Get-VsixMetadata {
	param([string]$VsixPath)

	$resolvedVsix = (Resolve-Path -LiteralPath $VsixPath).Path
	$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedVsix)
	try {
		$entry = $archive.GetEntry('extension/package.json')
		if (-not $entry) {
			Fail "VSIX is missing extension/package.json: $resolvedVsix"
		}

		$reader = New-Object System.IO.StreamReader($entry.Open())
		try {
			$manifest = $reader.ReadToEnd() | ConvertFrom-Json -Depth 100
		} finally {
			$reader.Dispose()
		}
	} finally {
		$archive.Dispose()
	}

	$publisher = ([string]$manifest.publisher).ToLowerInvariant()
	$name = ([string]$manifest.name).ToLowerInvariant()
	$version = [string]$manifest.version

	if (-not $publisher -or -not $name -or -not $version) {
		Fail "VSIX manifest is missing publisher, name, or version: $resolvedVsix"
	}

	$id = "$publisher.$name"
	$relativeLocation = "$id-$version"

	[pscustomobject]@{
		Id = $id
		Version = $version
		RelativeLocation = $relativeLocation
	}
}

function ConvertTo-NormalizedVersion {
	param([string]$Text)

	$parts = New-Object System.Collections.Generic.List[int]
	foreach ($segment in ($Text.Trim().TrimStart('v') -split '\.')) {
		if ($parts.Count -ge 3) {
			break
		}

		$match = [regex]::Match($segment, '\d+')
		if ($match.Success) {
			$parts.Add([int]$match.Value)
		} else {
			$parts.Add(0)
		}
	}

	while ($parts.Count -lt 3) {
		$parts.Add(0)
	}

	return [version]::new($parts[0], $parts[1], $parts[2])
}

function Get-CaretUpperBound {
	param([version]$BaseVersion)

	if ($BaseVersion.Major -ne 0) {
		return [version]::new($BaseVersion.Major + 1, 0, 0)
	}

	if ($BaseVersion.Minor -ne 0) {
		return [version]::new(0, $BaseVersion.Minor + 1, 0)
	}

	return [version]::new(0, 0, $BaseVersion.Build + 1)
}

function Get-TildeUpperBound {
	param([version]$BaseVersion)
	return [version]::new($BaseVersion.Major, $BaseVersion.Minor + 1, 0)
}

function Get-WildcardRange {
	param([string]$Token)

	$trimmed = $Token.Trim()
	if ($trimmed -in @('*', 'x', 'X')) {
		return [pscustomobject]@{
			HasWildcard = $true
			Lower = [version]::new(0, 0, 0)
			Upper = $null
		}
	}

	$parts = $trimmed -split '\.'
	$normalized = New-Object System.Collections.Generic.List[int]
	$wildcardIndex = -1

	for ($index = 0; $index -lt $parts.Length; $index++) {
		$part = $parts[$index]
		if ($part -in @('*', 'x', 'X')) {
			$wildcardIndex = $index
			break
		}

		$match = [regex]::Match($part, '\d+')
		if ($match.Success) {
			$normalized.Add([int]$match.Value)
		} else {
			$normalized.Add(0)
		}
	}

	if ($wildcardIndex -lt 0) {
		return $null
	}

	while ($normalized.Count -lt 3) {
		$normalized.Add(0)
	}

	$lower = [version]::new($normalized[0], $normalized[1], $normalized[2])
	$upper = $null

	if ($wildcardIndex -eq 1) {
		$upper = [version]::new($lower.Major + 1, 0, 0)
	} elseif ($wildcardIndex -ge 2) {
		$upper = [version]::new($lower.Major, $lower.Minor + 1, 0)
	}

	return [pscustomobject]@{
		HasWildcard = $true
		Lower = $lower
		Upper = $upper
	}
}

function Test-VersionTokenCompatible {
	param(
		[string]$Token,
		[version]$TargetVersion
	)

	$trimmed = $Token.Trim()
	if (-not $trimmed -or $trimmed -in @('*', 'x', 'X')) {
		return $true
	}

	if ($trimmed.StartsWith('^')) {
		$baseVersion = ConvertTo-NormalizedVersion -Text $trimmed.Substring(1)
		return $TargetVersion -ge $baseVersion -and $TargetVersion -lt (Get-CaretUpperBound -BaseVersion $baseVersion)
	}

	if ($trimmed.StartsWith('~')) {
		$baseVersion = ConvertTo-NormalizedVersion -Text $trimmed.Substring(1)
		return $TargetVersion -ge $baseVersion -and $TargetVersion -lt (Get-TildeUpperBound -BaseVersion $baseVersion)
	}

	foreach ($prefix in @('>=', '<=', '>', '<', '=')) {
		if ($trimmed.StartsWith($prefix)) {
			$comparisonVersion = ConvertTo-NormalizedVersion -Text $trimmed.Substring($prefix.Length)
			switch ($prefix) {
				'>=' { return $TargetVersion -ge $comparisonVersion }
				'<=' { return $TargetVersion -le $comparisonVersion }
				'>' { return $TargetVersion -gt $comparisonVersion }
				'<' { return $TargetVersion -lt $comparisonVersion }
				default { return $TargetVersion -eq $comparisonVersion }
			}
		}
	}

	$wildcard = Get-WildcardRange -Token $trimmed
	if ($wildcard) {
		if (-not $wildcard.Upper) {
			return $true
		}
		return $TargetVersion -ge $wildcard.Lower -and $TargetVersion -lt $wildcard.Upper
	}

	return $TargetVersion -eq (ConvertTo-NormalizedVersion -Text $trimmed)
}

function Test-VersionRangeCompatible {
	param(
		[string]$Range,
		[version]$TargetVersion
	)

	foreach ($group in ($Range -split '\|\|')) {
		$tokens = @(($group -replace ',', ' ') -split '\s+' | Where-Object { $_ })
		if (-not $tokens) {
			return $true
		}

		$matches = @($tokens | ForEach-Object { Test-VersionTokenCompatible -Token $_ -TargetVersion $TargetVersion })
		if ($matches -notcontains $false) {
			return $true
		}
	}

	return $false
}

function Get-TargetCodeVersion {
	if ($script:ResolvedCodeVersion) {
		return $script:ResolvedCodeVersion
	}

	if ($CodeVersion) {
		$script:ResolvedCodeVersion = ConvertTo-NormalizedVersion -Text $CodeVersion
		return $script:ResolvedCodeVersion
	}

	if (-not $script:ResolvedCodiumBin) {
		Fail 'Unable to determine the target VSCodium version for marketplace downloads. Pass -CodeVersion or -CodiumBin.'
	}

	$versionLine = @(& $script:ResolvedCodiumBin --version 2>$null | Select-Object -First 1)[0]
	if (-not $versionLine) {
		Fail "Failed to read the VSCodium version from $($script:ResolvedCodiumBin)"
	}

	$script:ResolvedCodeVersion = ConvertTo-NormalizedVersion -Text ([string]$versionLine)
	return $script:ResolvedCodeVersion
}

function Get-DownloadRoot {
	if ($script:DownloadRoot) {
		return $script:DownloadRoot
	}

	if ($DryRun) {
		$script:DownloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'vscodium-copilot-downloads'
		return $script:DownloadRoot
	}

	$script:DownloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vscodium-copilot-downloads-" + [guid]::NewGuid().ToString())
	New-Item -ItemType Directory -Path $script:DownloadRoot -Force | Out-Null
	$script:CreatedDownloadRoot = $true
	return $script:DownloadRoot
}

function Remove-DownloadRoot {
	if ($script:CreatedDownloadRoot -and $script:DownloadRoot -and (Test-Path -LiteralPath $script:DownloadRoot)) {
		Remove-Item -LiteralPath $script:DownloadRoot -Recurse -Force -ErrorAction SilentlyContinue
	}
}

function Get-MarketplaceExtensionInfo {
	param([string]$ExtensionId)

	$targetCodeVersion = Get-TargetCodeVersion

	$payload = [ordered]@{
		filters = @(
			[ordered]@{
				criteria = @(
					[ordered]@{
						filterType = 7
						value = $ExtensionId
					}
				)
				pageNumber = 1
				pageSize = 1
				sortBy = 0
				sortOrder = 0
			}
		)
		assetTypes = @()
		flags = 103
	}

	$response = Invoke-RestMethod -Method Post -Uri 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' -Headers @{
		'Content-Type' = 'application/json'
		'Accept' = 'application/json;api-version=7.2-preview.1'
		'X-Market-Client-Id' = 'VSCode 1.0'
	} -Body ($payload | ConvertTo-Json -Depth 10 -Compress)

	$extension = @($response.results[0].extensions)[0]
	if (-not $extension) {
		Fail "Extension not found in marketplace: $ExtensionId"
	}

	$parts = $ExtensionId.Split('.', 2)
	$publisherName = $parts[0].ToLowerInvariant()
	$extensionName = $parts[1].ToLowerInvariant()

	foreach ($versionInfo in @($extension.versions)) {
		if (-not $versionInfo.version) {
			continue
		}

		$manifestAsset = @($versionInfo.files | Where-Object { $_.assetType -eq 'Microsoft.VisualStudio.Code.Manifest' } | Select-Object -First 1)[0]
		$vsixAsset = @($versionInfo.files | Where-Object { $_.assetType -eq 'Microsoft.VisualStudio.Services.VSIXPackage' } | Select-Object -First 1)[0]
		if (-not $manifestAsset -or -not $manifestAsset.source -or -not $vsixAsset -or -not $vsixAsset.source) {
			continue
		}

		$manifest = Invoke-RestMethod -Method Get -Uri $manifestAsset.source -Headers @{ 'User-Agent' = 'VSCodium Copilot Installer' }
		$engineRange = [string]$manifest.engines.vscode
		if (-not $engineRange) {
			continue
		}

		if (-not (Test-VersionRangeCompatible -Range $engineRange -TargetVersion $targetCodeVersion)) {
			continue
		}

		$fileName = "$publisherName.$extensionName-$($versionInfo.version).vsix"
		return [pscustomobject]@{
			ExtensionId = $ExtensionId
			Version = [string]$versionInfo.version
			AssetUrl = [string]$vsixAsset.source
			FileName = $fileName
			EngineRange = $engineRange
			TargetCodeVersion = $targetCodeVersion.ToString()
		}
	}

	Fail "No compatible marketplace version found for $ExtensionId and Code $($targetCodeVersion.ToString())"
}

function Download-MarketplaceVsix {
	param([string]$ExtensionId)

	$info = Get-MarketplaceExtensionInfo -ExtensionId $ExtensionId
	$downloadRoot = Get-DownloadRoot
	$targetPath = Join-Path $downloadRoot $info.FileName

	if ($DryRun) {
		Write-Host "[dry-run] Would download $($info.ExtensionId)@$($info.Version) compatible with Code $($info.TargetCodeVersion) ($($info.EngineRange)) from $($info.AssetUrl) to $targetPath"
		return $targetPath
	}

	Write-Info "Downloading $($info.ExtensionId)@$($info.Version) compatible with Code $($info.TargetCodeVersion) ($($info.EngineRange)) from the Visual Studio Marketplace"
	$previousProgressPreference = $ProgressPreference
	try {
		$ProgressPreference = 'SilentlyContinue'
		Invoke-WebRequest -Uri $info.AssetUrl -OutFile $targetPath -Headers @{ 'User-Agent' = 'VSCodium Copilot Installer' }
	} finally {
		$ProgressPreference = $previousProgressPreference
	}
	Write-Info "Downloaded $targetPath"
	return $targetPath
}

function Update-ExtensionsRegistry {
	param(
		[string]$ExtensionId,
		[string]$Version,
		[string]$TargetDir,
		[string]$RelativeLocation
	)

	$registryPath = Join-Path $ExtensionsDir 'extensions.json'
	$entries = @()

	if (Test-Path -LiteralPath $registryPath) {
		$raw = Get-Content -LiteralPath $registryPath -Raw
		if ($raw.Trim()) {
			$parsed = $raw | ConvertFrom-Json -Depth 50
			$entries = @($parsed)
		}
	}

	$entries = @($entries | Where-Object {
		-not ($_.identifier -and $_.identifier.id -eq $ExtensionId)
	})

	$resolvedTargetDir = (Resolve-Path -LiteralPath $TargetDir).Path
	$externalUri = ([System.Uri]$resolvedTargetDir).AbsoluteUri

	$entry = [ordered]@{
		identifier = [ordered]@{ id = $ExtensionId }
		version = $Version
		location = [ordered]@{
			'$mid' = 1
			fsPath = $resolvedTargetDir
			external = $externalUri
			path = $resolvedTargetDir
			scheme = 'file'
		}
		relativeLocation = $RelativeLocation
		metadata = [ordered]@{
			isApplicationScoped = $false
			isMachineScoped = $false
			isBuiltin = $false
			installedTimestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
			pinned = $true
			source = 'vsix'
		}
	}

	$entries += [pscustomobject]$entry
	$entries | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8
}

function Remove-ExtensionsRegistryEntries {
	param([string[]]$ExtensionIds)

	$registryPath = Join-Path $ExtensionsDir 'extensions.json'
	if (-not (Test-Path -LiteralPath $registryPath)) {
		Write-Info "No extensions registry found at $registryPath"
		return
	}

	$entries = @()
	$raw = Get-Content -LiteralPath $registryPath -Raw
	if ($raw.Trim()) {
		$entries = @($raw | ConvertFrom-Json -Depth 50)
	}

	$kept = @($entries | Where-Object {
		-not ($_.identifier -and $ExtensionIds -contains $_.identifier.id)
	})
	$removedCount = @($entries).Count - @($kept).Count

	if ($DryRun) {
		Write-Host "[dry-run] Would update $registryPath and remove $removedCount registry entries"
		return
	}

	if ($removedCount -gt 0) {
		$kept | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8
		Write-Info "Updated $registryPath and removed $removedCount registry entries"
	} else {
		Write-Info "Unchanged $registryPath"
	}
}

function Install-Vsix {
	param([string]$VsixPath)

	if (-not $VsixPath) {
		return
	}

	$metadata = Get-VsixMetadata -VsixPath $VsixPath
	$targetDir = Join-Path $ExtensionsDir $metadata.RelativeLocation
	Write-Info "Installing $(Split-Path -Leaf $VsixPath) into the VSCodium extensions directory"

	if ($DryRun) {
		Write-Host "[dry-run] Would install $VsixPath to $targetDir"
		return
	}

	$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vscodium-copilot-" + [guid]::NewGuid().ToString())
	$backupDir = "$targetDir.bak-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"

	try {
		New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
		Expand-Archive -LiteralPath $VsixPath -DestinationPath $tempRoot -Force

		$sourceDir = Join-Path $tempRoot 'extension'
		if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
			Fail "Extracted VSIX is missing the extension directory: $VsixPath"
		}

		if (Test-Path -LiteralPath $targetDir) {
			if (Test-Path -LiteralPath $backupDir) {
				Remove-Item -LiteralPath $backupDir -Recurse -Force
			}
			Move-Item -LiteralPath $targetDir -Destination $backupDir -Force
		}

		Move-Item -LiteralPath $sourceDir -Destination $targetDir -Force
		Update-ExtensionsRegistry -ExtensionId $metadata.Id -Version $metadata.Version -TargetDir $targetDir -RelativeLocation $metadata.RelativeLocation

		if (Test-Path -LiteralPath $backupDir) {
			Remove-Item -LiteralPath $backupDir -Recurse -Force
		}

		$resolvedTargetDir = (Resolve-Path -LiteralPath $targetDir).Path
		$staleDirs = @(Get-ChildItem -LiteralPath $ExtensionsDir -Directory -ErrorAction SilentlyContinue | Where-Object {
			$_.Name -like "$($metadata.Id)-*" -and $_.FullName -ne $resolvedTargetDir
		})
		foreach ($staleDir in $staleDirs) {
			Remove-Item -LiteralPath $staleDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
		}

		Write-Info "Installed $targetDir"
	} catch {
		if (Test-Path -LiteralPath $targetDir) {
			Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue
		}
		if ((Test-Path -LiteralPath $backupDir) -and -not (Test-Path -LiteralPath $targetDir)) {
			Move-Item -LiteralPath $backupDir -Destination $targetDir -Force
		}
		throw
	} finally {
		if (Test-Path -LiteralPath $tempRoot) {
			Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
}

function Uninstall-Extensions {
	$patterns = @('github.copilot-chat-*')
	$registryIds = @('github.copilot-chat')

	if ($IncludeCopilot) {
		$patterns += 'github.copilot-[0-9]*'
		$registryIds += 'github.copilot'
	}

	$dirs = foreach ($pattern in $patterns) {
		Get-ChildItem -LiteralPath $ExtensionsDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern }
	}
	$dirs = @($dirs | Sort-Object -Property FullName -Unique)

	if (-not $dirs) {
		Write-Info "No matching installed extensions were found under $ExtensionsDir"
	} else {
		foreach ($dir in $dirs) {
			if ($DryRun) {
				Write-Host "[dry-run] Would remove $($dir.FullName)"
			} else {
				Write-Info "Removing $($dir.FullName)"
				Remove-Item -LiteralPath $dir.FullName -Recurse -Force
			}
		}
	}

	Remove-ExtensionsRegistryEntries -ExtensionIds $registryIds
	Clear-ExtensionCaches
	Write-Info 'Completed uninstall. Fully quit and reopen VSCodium if it was running.'
}

function Patch-CopilotChatManifest {
	param([string]$ManifestPath)

	Write-Info "Patching $(Split-Path -Parent $ManifestPath)"
	$json = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 100
	if (-not ($json.enabledApiProposals -is [System.Collections.IEnumerable])) {
		Fail "enabledApiProposals is missing or invalid in $ManifestPath"
	}

	$changed = $false
	$patched = New-Object System.Collections.Generic.List[string]
	foreach ($proposal in @($json.enabledApiProposals)) {
		if ($proposal -isnot [string]) {
			Fail "enabledApiProposals contains a non-string entry in $ManifestPath"
		}

		$newValue = $proposal -replace '@\d+$', ''
		if ($newValue -ne $proposal) {
			$changed = $true
		}
		$patched.Add($newValue)
	}

	$patchedArray = @($patched.ToArray())
	$remainingVersioned = @($patchedArray | Where-Object { $_ -match '@\d+$' })
	$missingExpected = @($script:RequiredProposals | Where-Object { $patchedArray -cnotcontains $_ })

	if ($remainingVersioned.Count -gt 0) {
		Fail "Version-pinned proposals remain after normalization in ${ManifestPath}: $($remainingVersioned -join ', ')"
	}

	if ($missingExpected.Count -gt 0) {
		Fail "Missing required proposals after normalization in ${ManifestPath}: $($missingExpected -join ', ')"
	}

	$json.enabledApiProposals = $patched
	if ($DryRun) {
		if ($changed) {
			Write-Host "[dry-run] Would patch $ManifestPath"
		} else {
			Write-Info "Unchanged $ManifestPath"
		}
		Write-Info "Verified ${ManifestPath}: required proposals present and unpinned"
		return
	}

	if ($changed) {
		$updated = $json | ConvertTo-Json -Depth 100
		Set-Content -LiteralPath $ManifestPath -Value $updated -Encoding utf8
		Write-Info "Patched $ManifestPath"
	} else {
		Write-Info "Unchanged $ManifestPath"
	}

	Write-Info "Verified ${ManifestPath}: required proposals present and unpinned"
}

function Clear-ExtensionCaches {
	$cacheRoot = Join-Path $UserDataDir 'CachedProfilesData'
	if (-not (Test-Path -LiteralPath $cacheRoot)) {
		Write-Info "No CachedProfilesData directory found under $UserDataDir"
		return
	}

	$caches = Get-ChildItem -Path $cacheRoot -Filter 'extensions.user.cache' -File -Recurse -ErrorAction SilentlyContinue
	if (-not $caches) {
		Write-Info "No extensions.user.cache files found under $cacheRoot"
		return
	}

	foreach ($cache in $caches) {
		Invoke-Step -Description "Remove $($cache.FullName)" -Action {
			Remove-Item -LiteralPath $cache.FullName -Force
		}
	}
}

try {
	if (-not $UserDataDir) {
		$UserDataDir = Join-Path $env:APPDATA 'VSCodium'
	}

	if (-not $ExtensionsDir) {
		$ExtensionsDir = Join-Path $env:USERPROFILE '.vscode-oss\extensions'
	}

	Show-InteractiveMenu

	$script:ResolvedCodiumBin = Resolve-CodiumBin -RequestedPath $CodiumBin

	if (-not $AllowRunning -and -not $DryRun) {
		$running = @(Get-Process -Name 'codium', 'VSCodium' -ErrorAction SilentlyContinue)
		if ($running.Count -gt 0) {
			Fail 'Close all VSCodium windows before running this installer, or pass -AllowRunning.'
		}
	}

	if ($Uninstall -and $SkipInstall) {
		Fail 'Use either -Uninstall or -SkipInstall, not both.'
	}

	if ($DownloadLatest -and $SkipInstall) {
		Fail 'Use either -DownloadLatest or -SkipInstall, not both.'
	}

	if ($IncludeCopilot -and -not $Uninstall) {
		Fail '-IncludeCopilot can only be used with -Uninstall.'
	}

	if ($WithCopilot -and $Uninstall) {
		Fail '-WithCopilot and -CopilotVsix are install options. Use -IncludeCopilot with -Uninstall.'
	}

	if ($DownloadLatest -and $Uninstall) {
		Fail '-DownloadLatest cannot be used with -Uninstall.'
	}

	if (-not $Uninstall -and -not (Test-Path -LiteralPath $ExtensionsDir)) {
		Invoke-Step -Description "Create $ExtensionsDir" -Action {
			New-Item -ItemType Directory -Path $ExtensionsDir -Force | Out-Null
		}
	}

	if ($Uninstall) {
		Write-Info 'Uninstall requested. The script will remove installed extension directories, update the registry, and clear caches.'
		Uninstall-Extensions
		return
	}

	if (-not $SkipInstall -and -not $DownloadLatest -and -not $ChatVsix) {
		$ChatVsix = Find-VsixByExtensionId -ExtensionId 'github.copilot-chat'
	}

	if (-not $SkipInstall -and -not $DownloadLatest -and -not $CopilotVsix) {
		if ($WithCopilot) {
			$CopilotVsix = Find-VsixByExtensionId -ExtensionId 'github.copilot'
		}
	}

	if (-not $SkipInstall -and -not $ChatVsix) {
		$ChatVsix = Download-MarketplaceVsix -ExtensionId 'GitHub.copilot-chat'
	}

	if (-not $SkipInstall -and -not $CopilotVsix) {
		if ($WithCopilot) {
			$CopilotVsix = Download-MarketplaceVsix -ExtensionId 'GitHub.copilot'
		}
	}

	if ($ChatVsix -and -not (Test-Path -LiteralPath $ChatVsix)) {
		Fail "Chat VSIX not found: $ChatVsix"
	}

	if ($CopilotVsix -and -not (Test-Path -LiteralPath $CopilotVsix)) {
		Fail "Copilot VSIX not found: $CopilotVsix"
	}

	if (-not $SkipInstall) {
		if (-not $ChatVsix) {
			Fail 'No Copilot Chat VSIX was found or downloaded. Pass -ChatVsix, keep a local VSIX nearby, or check marketplace connectivity.'
		}

		if ($WithCopilot -and -not $CopilotVsix) {
			Fail 'No GitHub Copilot VSIX was found or downloaded. Pass -CopilotVsix, keep a local VSIX nearby, or check marketplace connectivity.'
		}

		if ($WithCopilot) {
			Write-Info 'Install requested. The script will install GitHub Copilot Chat and the deprecated base GitHub Copilot extension, patch installed manifests, verify them, and clear caches.'
			Install-Vsix -VsixPath $CopilotVsix
		} else {
			Write-Info 'Install requested. The script will install GitHub Copilot Chat, patch installed manifests, verify them, and clear caches.'
		}
		Install-Vsix -VsixPath $ChatVsix
	}

	$chatDirs = @(Get-ChildItem -LiteralPath $ExtensionsDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'github.copilot-chat-*' })
	if (-not $chatDirs) {
		Fail "No installed github.copilot-chat directories were found under $ExtensionsDir"
	}

	foreach ($dir in $chatDirs) {
		$manifestPath = Join-Path $dir.FullName 'package.json'
		if (Test-Path -LiteralPath $manifestPath) {
			Patch-CopilotChatManifest -ManifestPath $manifestPath
		}
	}

	Clear-ExtensionCaches

	Write-Info 'Completed. Fully quit and reopen VSCodium so it rescans the patched extension.'
	if ($DryRun) {
		Write-Info 'Dry run only. No files were changed.'
	}
} finally {
	Remove-DownloadRoot
}