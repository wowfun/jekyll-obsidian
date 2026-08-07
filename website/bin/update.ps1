$ErrorActionPreference = "Stop"

$CanonicalOrigin = "https://github.com/wowfun/jekyll-obsidian.git"
$ReleaseMetadataName = ".jekyll-obsidian-release"
$ConfigStart = "  # jekyll-obsidian:managed-start"
$ConfigEnd = "  # jekyll-obsidian:managed-end"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$TestFailAt = ""

function Show-Usage {
    @"
Usage: website\bin\update.cmd [--check] [--to YYYY.M.D]

Update the managed jekyll-obsidian website snapshot from an official release.

Options:
  --check             Check whether a newer snapshot is available without writing
  --to YYYY.M.D       Select a specific release (default: latest stable release)
  --help, -h          Show this help
"@ | Write-Output
}

function Fail([string]$Message) {
    throw "Update error: $Message"
}

function Read-Utf8Lf([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail "missing $Label." }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
        Fail "$Label must be UTF-8 without a byte-order mark."
    }
    if ($bytes -contains 13) { Fail "$Label must use LF line endings." }
    try { return $Utf8Strict.GetString($bytes) }
    catch { Fail "$Label is not valid UTF-8." }
}

function Write-Utf8Lf([string]$Path, [string]$Content) {
    $parent = [System.IO.Directory]::GetParent($Path)
    if ($null -ne $parent) { [System.IO.Directory]::CreateDirectory($parent.FullName) | Out-Null }
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n")
    [System.IO.File]::WriteAllText($Path, $normalized, $Utf8NoBom)
}

function Read-Utf8Normalized([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail "missing $Label." }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
        Fail "$Label must be UTF-8 without a byte-order mark."
    }
    try { $text = $Utf8Strict.GetString($bytes) }
    catch { Fail "$Label is not valid UTF-8." }
    return $text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-CalVer([string]$Version, [string]$Label) {
    $match = [Regex]::Match($Version, '^(?<year>\d{4})\.(?<month>[1-9]|1[0-2])\.(?<day>[1-9]|[12]\d|3[01])$')
    if (-not $match.Success) { Fail "$Label must be a calendar version in YYYY.M.D form." }
    try {
        $date = New-Object DateTime(
            [int]$match.Groups["year"].Value,
            [int]$match.Groups["month"].Value,
            [int]$match.Groups["day"].Value,
            0,
            0,
            0,
            [DateTimeKind]::Utc
        )
    }
    catch {
        Fail "$Label is not a valid calendar date."
    }
    return [PSCustomObject]@{ Version = $Version; Date = $date }
}

function Read-ReleaseMetadata([string]$SitePath, [string]$ExpectedVersion) {
    foreach ($required in @(
        ".jekyll-obsidian-release",
        "bin\build",
        "bin\integrate",
        "bin\integrate.ps1",
        "bin\integrate.cmd",
        "bin\setup",
        "bin\test",
        "bin\update",
        "bin\update.ps1",
        "bin\update.cmd",
        "scripts\example-config.yml",
        "scripts\templates\host-config.yml",
        "scripts\templates\pages.yml"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $SitePath $required) -PathType Leaf)) {
            Fail "release is missing required updater component website/$($required.Replace('\', '/'))."
        }
    }
    $releasePath = Join-Path $SitePath $ReleaseMetadataName
    $release = Read-Utf8Lf $releasePath "website/$ReleaseMetadataName"
    $match = [Regex]::Match($release, '\Aformat=1\nversion=(?<version>[^\n]+)\nupdater_protocol=1\n\z')
    if (-not $match.Success) { Fail "website/$ReleaseMetadataName is malformed or uses an unsupported updater protocol." }
    $version = $match.Groups["version"].Value
    [void](Get-CalVer $version "release version")
    if (-not [string]::IsNullOrEmpty($ExpectedVersion) -and $version -cne $ExpectedVersion) {
        Fail "release metadata version $version does not match $ExpectedVersion."
    }

    $packagePath = Join-Path $SitePath "package.json"
    $packageLockPath = Join-Path $SitePath "package-lock.json"
    $rubyPath = Join-Path $SitePath "lib\jekyll_obsidian.rb"
    try {
        $package = (Read-Utf8Normalized $packagePath "website/package.json") | ConvertFrom-Json
        # Windows PowerShell 5.1 rejects an empty JSON property name. npm uses one
        # for the package-lock root, so give that key an internal parsing name.
        $packageLockText = Read-Utf8Normalized $packageLockPath "website/package-lock.json"
        $packageLock = ([Regex]::Replace($packageLockText, '""\s*:', '"__jekyll_obsidian_root__":')) | ConvertFrom-Json
    }
    catch {
        Fail "release package metadata is malformed JSON."
    }
    $lockRoot = $packageLock.version
    $lockPackageProperty = $packageLock.packages.PSObject.Properties["__jekyll_obsidian_root__"]
    if ($null -eq $lockPackageProperty) { Fail "website/package-lock.json is missing the root package entry." }
    $lockPackage = $lockPackageProperty.Value.version
    $ruby = Read-Utf8Normalized $rubyPath "website/lib/jekyll_obsidian.rb"
    $rubyMatches = [Regex]::Matches($ruby, '(?m)^\s*VERSION = "(?<version>[^"]+)"\s*$')
    if ($rubyMatches.Count -ne 1) { Fail "website/lib/jekyll_obsidian.rb has a malformed VERSION contract." }
    $rubyVersion = $rubyMatches[0].Groups["version"].Value
    foreach ($entry in @(
        @{ Label = "website/package.json"; Value = $package.version },
        @{ Label = "website/package-lock.json"; Value = $lockRoot },
        @{ Label = "website/package-lock.json root package"; Value = $lockPackage },
        @{ Label = "website/lib/jekyll_obsidian.rb"; Value = $rubyVersion }
    )) {
        if ([string]$entry.Value -cne $version) { Fail "$($entry.Label) version does not match release version $version." }
    }
    return [PSCustomObject]@{ Version = $version; Path = $releasePath }
}

function Assert-NotReparsePoint([string]$Path, [string]$Label) {
    $item = Get-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Fail "$Label must not be a symbolic link, junction, or reparse point."
    }
}

function Invoke-Git([string]$WorkingDirectory, [string[]]$Arguments, [bool]$AllowFailure = $false) {
    Push-Location $WorkingDirectory
    $previousErrorAction = $ErrorActionPreference
    $hadOptionalLocks = Test-Path Env:\GIT_OPTIONAL_LOCKS
    $previousOptionalLocks = $env:GIT_OPTIONAL_LOCKS
    $env:GIT_OPTIONAL_LOCKS = "0"
    $ErrorActionPreference = "Continue"
    try {
        $raw = & git.exe @Arguments 2>&1
        $code = $LASTEXITCODE
        $global:LASTEXITCODE = 0
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
        if ($hadOptionalLocks) { $env:GIT_OPTIONAL_LOCKS = $previousOptionalLocks }
        else { Remove-Item Env:\GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue }
        Pop-Location
    }
    $lines = @($raw | ForEach-Object { [string]$_ })
    $output = ($lines -join "`n").TrimEnd()
    if (-not $AllowFailure -and $code -ne 0) {
        if ([string]::IsNullOrWhiteSpace($output)) { Fail "git $($Arguments[0]) failed with exit code $code." }
        Fail "git $($Arguments[0]) failed: $output"
    }
    return [PSCustomObject]@{ Code = $code; Output = $output }
}

function Invoke-ReleaseGit([string]$WorkingDirectory, [string[]]$Arguments, [bool]$AllowFailure = $false) {
    $environmentNames = @(
        "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS",
        "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"
    )
    $saved = @{}
    foreach ($name in $environmentNames) {
        $path = "Env:\$name"
        $saved[$name] = [PSCustomObject]@{ Exists = Test-Path $path; Value = [Environment]::GetEnvironmentVariable($name, "Process") }
        Remove-Item $path -ErrorAction SilentlyContinue
    }
    $env:GIT_CONFIG_NOSYSTEM = "1"
    $env:GIT_CONFIG_GLOBAL = "NUL"
    $env:GIT_CONFIG_SYSTEM = "NUL"
    try { return Invoke-Git $WorkingDirectory $Arguments $AllowFailure }
    finally {
        foreach ($name in $environmentNames) {
            $state = $saved[$name]
            if ($state.Exists) { [Environment]::SetEnvironmentVariable($name, [string]$state.Value, "Process") }
            else { Remove-Item "Env:\$name" -ErrorAction SilentlyContinue }
        }
    }
}

function Invoke-PowerShellFile([string]$Script, [string[]]$Arguments) {
    $executable = (Get-Process -Id $PID).Path
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $raw = & $executable -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1
        $code = $LASTEXITCODE
        $global:LASTEXITCODE = 0
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [PSCustomObject]@{ Code = $code; Output = (@($raw | ForEach-Object { [string]$_ }) -join "`n").TrimEnd() }
}

function Get-TransportOrigin {
    $testing = $env:JEKYLL_OBSIDIAN_UPDATE_TESTING
    $testOrigin = $env:JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN
    if ($testing -ceq "1") {
        if ([string]::IsNullOrWhiteSpace($testOrigin)) { Fail "the internal test transport is missing its origin." }
        $uri = $null
        if (-not [Uri]::TryCreate($testOrigin, [UriKind]::Absolute, [ref]$uri) -or -not $uri.IsFile) {
            Fail "the internal test transport must be an absolute file:// URI."
        }
        $script:TestFailAt = [string]$env:JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT
        if (@("", "fail_after_first_file", "pause_after_transaction_claim", "crash_after_all_renames") -cnotcontains $script:TestFailAt) { Fail "the internal failure injection point is invalid." }
        return $uri.AbsoluteUri
    }
    if (-not [string]::IsNullOrEmpty($testing) -or -not [string]::IsNullOrEmpty($testOrigin) -or
        -not [string]::IsNullOrEmpty($env:JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT)) {
        Fail "the internal test transport is disabled."
    }
    return $CanonicalOrigin
}

function Get-RemoteReleases([string]$HostDir, [string]$Transport) {
    $result = Invoke-ReleaseGit $HostDir @("ls-remote", "--tags", $Transport)
    $direct = @{}
    $peeled = @{}
    foreach ($line in @($result.Output -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $match = [Regex]::Match($line, '^(?<oid>[0-9a-f]{40,64})\s+refs/tags/(?<tag>v[^\^\s]+)(?<peeled>\^\{\})?$')
        if (-not $match.Success) { continue }
        $tag = $match.Groups["tag"].Value
        if ($tag -notmatch '^v\d{4}\.\d+\.\d+$') { continue }
        $version = $tag.Substring(1)
        [void](Get-CalVer $version "remote tag $tag")
        $target = if ($match.Groups["peeled"].Success) { $peeled } else { $direct }
        if ($target.ContainsKey($tag)) { Fail "remote release $tag is ambiguous." }
        $target[$tag] = $match.Groups["oid"].Value
    }
    $releases = New-Object System.Collections.Generic.List[object]
    foreach ($tag in $direct.Keys) {
        if (-not $peeled.ContainsKey($tag)) { Fail "remote release $tag is not an annotated tag." }
        $calver = Get-CalVer $tag.Substring(1) "remote tag $tag"
        [void]$releases.Add([PSCustomObject]@{
            Tag = $tag
            Version = $calver.Version
            Date = $calver.Date
            TagObject = $direct[$tag]
            Commit = $peeled[$tag]
        })
    }
    if ($releases.Count -eq 0) { Fail "the official origin has no stable annotated CalVer releases." }
    return @($releases.ToArray() | Sort-Object -Property Date)
}

function Select-RemoteRelease([object[]]$Releases, [string]$RequestedVersion) {
    if ([string]::IsNullOrEmpty($RequestedVersion)) { return $Releases[-1] }
    foreach ($release in $Releases) {
        if ($release.Version -ceq $RequestedVersion) { return $release }
    }
    Fail "release v$RequestedVersion does not exist as an annotated official tag."
}

function Assert-SafeRepositoryPath([string]$Path) {
    if (-not $Path.StartsWith("website/", [StringComparison]::Ordinal) -or $Path.Length -le 8) {
        Fail "a release contains a path outside website/."
    }
    if ($Path.Contains('\') -or $Path -match '[\x00-\x1f\x7f<>:"|?*]') { Fail "release path is not portable: $Path" }
    foreach ($segment in $Path.Split('/')) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -eq "." -or $segment -eq ".." -or
            $segment.EndsWith(" ") -or $segment.EndsWith(".")) { Fail "release path is not portable: $Path" }
        $stem = $segment.Split('.')[0]
        if ($stem -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])$') { Fail "release path is not portable: $Path" }
    }
}

function Get-WebsiteTreeEntries([string]$Repository, [string]$Treeish) {
    $result = Invoke-Git $Repository @("-c", "core.quotePath=false", "ls-tree", "-r", "--full-tree", $Treeish, "--", "website")
    $entries = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in @($result.Output -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $match = [Regex]::Match($line, '^(?<mode>[0-9]{6}) (?<type>[^ ]+) (?<oid>[0-9a-f]{40,64})\t(?<path>.+)$')
        if (-not $match.Success -or $match.Groups["type"].Value -cne "blob" -or
            @("100644", "100755") -cnotcontains $match.Groups["mode"].Value) {
            Fail "release website tree may contain only regular files."
        }
        $path = $match.Groups["path"].Value
        Assert-SafeRepositoryPath $path
        if (-not $seen.Add($path)) { Fail "release website paths collide on a case-insensitive filesystem: $path" }
        [void]$entries.Add([PSCustomObject]@{
            Path = $path
            Relative = $path.Substring(8)
            Mode = $match.Groups["mode"].Value
            Oid = $match.Groups["oid"].Value
        })
    }
    if ($entries.Count -eq 0) { Fail "release website tree is empty." }
    return @($entries.ToArray())
}

function Test-WebsiteEntriesEqual([object[]]$Left, [object[]]$Right) {
    if ($Left.Count -ne $Right.Count) { return $false }
    $rightByPath = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach ($entry in $Right) { $rightByPath.Add([string]$entry.Path, [string]$entry.Oid) }
    foreach ($entry in $Left) {
        if (-not $rightByPath.ContainsKey($entry.Path) -or $rightByPath[$entry.Path] -cne $entry.Oid) { return $false }
    }
    return $true
}

function Fetch-Release([string]$HostDir, [string]$Transport, [object]$Release, [string]$ParentDirectory) {
    $repository = Join-Path $ParentDirectory "release"
    [System.IO.Directory]::CreateDirectory($repository) | Out-Null
    [void](Invoke-ReleaseGit $HostDir @("init", "--quiet", $repository))
    [void](Invoke-ReleaseGit $HostDir @("-C", $repository, "fetch", "--quiet", "--no-tags", $Transport, "refs/tags/$($Release.Tag):refs/tags/$($Release.Tag)"))

    $type = (Invoke-ReleaseGit $HostDir @("-C", $repository, "cat-file", "-t", "refs/tags/$($Release.Tag)")).Output
    if ($type -cne "tag") { Fail "release $($Release.Tag) is not an annotated tag." }
    $tagObject = (Invoke-ReleaseGit $HostDir @("-C", $repository, "rev-parse", "refs/tags/$($Release.Tag)^{tag}")).Output
    $commit = (Invoke-ReleaseGit $HostDir @("-C", $repository, "rev-parse", "refs/tags/$($Release.Tag)^{commit}")).Output
    if ($tagObject -cne $Release.TagObject -or $commit -cne $Release.Commit) { Fail "release $($Release.Tag) moved while it was being fetched." }
    $tagPayload = (Invoke-ReleaseGit $HostDir @("-C", $repository, "cat-file", "-p", $tagObject)).Output
    $tagHeader = [Regex]::Match($tagPayload, '\Aobject (?<object>[0-9a-f]{40,64})\ntype commit\ntag (?<tag>[^\n]+)\n')
    if (-not $tagHeader.Success -or $tagHeader.Groups["object"].Value -cne $commit -or
        $tagHeader.Groups["tag"].Value -cne $Release.Tag) {
        Fail "release tag object does not name $($Release.Tag) or directly reference its commit."
    }
    $tree = (Invoke-ReleaseGit $HostDir @("-C", $repository, "rev-parse", "$commit`:website")).Output
    $entries = Get-WebsiteTreeEntries $repository $commit
    [void](Invoke-ReleaseGit $HostDir @("-C", $repository, "checkout", "--quiet", "--detach", $commit))
    $site = Join-Path $repository "website"
    [void](Read-ReleaseMetadata $site $Release.Version)
    foreach ($executable in @("build", "integrate", "setup", "test", "update")) {
        $executableEntries = @($entries | Where-Object { $_.Path -ceq "website/bin/$executable" })
        if ($executableEntries.Count -ne 1 -or $executableEntries[0].Mode -cne "100755") {
            Fail "release $($Release.Tag) does not contain executable website/bin/$executable."
        }
    }
    return [PSCustomObject]@{
        Repository = $repository
        Site = $site
        Tree = $tree
        Entries = $entries
        Release = $Release
    }
}

function Read-ProvenanceLock([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail "missing .github/jekyll-obsidian.lock." }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
        Fail ".github/jekyll-obsidian.lock must be UTF-8 without a byte-order mark."
    }
    try { $text = $Utf8Strict.GetString($bytes) }
    catch { Fail ".github/jekyll-obsidian.lock is not valid UTF-8." }
    if ($text.Contains("`r")) {
        if ([Regex]::IsMatch($text, '\r(?!\n)|(?<!\r)\n')) {
            Fail ".github/jekyll-obsidian.lock must use consistent LF or CRLF line endings."
        }
        $text = $text.Replace("`r`n", "`n")
    }
    $pattern = '\Aformat=1\norigin=(?<origin>[^\n]+)\nversion=(?<version>[^\n]+)\ntag=(?<tag>[^\n]+)\ntag_object=(?<tag_object>[0-9a-f]{40,64})\ncommit=(?<commit>[0-9a-f]{40,64})\nwebsite_tree=(?<tree>[0-9a-f]{40,64})\n\z'
    $match = [Regex]::Match($text, $pattern)
    if (-not $match.Success) { Fail ".github/jekyll-obsidian.lock is malformed." }
    $version = $match.Groups["version"].Value
    [void](Get-CalVer $version "locked version")
    if ($match.Groups["origin"].Value -cne $CanonicalOrigin -or $match.Groups["tag"].Value -cne "v$version") {
        Fail ".github/jekyll-obsidian.lock does not describe an official release."
    }
    return [PSCustomObject]@{
        Origin = $match.Groups["origin"].Value
        Version = $version
        Tag = $match.Groups["tag"].Value
        TagObject = $match.Groups["tag_object"].Value
        Commit = $match.Groups["commit"].Value
        Tree = $match.Groups["tree"].Value
    }
}

function Get-ReleaseByVersion([object[]]$Releases, [string]$Version) {
    foreach ($release in $Releases) {
        if ($release.Version -ceq $Version) { return $release }
    }
    Fail "installed release v$Version no longer exists at the official origin."
}

function Assert-CleanManagedState([string]$HostDir, [string]$SiteDir, [string]$LockPath) {
    $status = Invoke-Git $HostDir @("status", "--porcelain=v1", "--untracked-files=all", "--", "website", ".github/workflows/pages.yml", ".github/jekyll-obsidian.lock")
    if (-not [string]::IsNullOrWhiteSpace($status.Output)) {
        Fail "managed website, workflow, and provenance files must be committed and clean before updating."
    }
    $integration = Invoke-PowerShellFile (Join-Path $SiteDir "bin\integrate.ps1") @("--check")
    if ($integration.Code -ne 0) { Fail "current host integration is invalid: $($integration.Output)" }
    $configPath = Join-Path $HostDir ".github\jekyll-obsidian.yml"
    $worktreeConfig = [System.IO.File]::ReadAllText($configPath).Replace("`r`n", "`n").Replace("`r", "`n")
    $headConfig = (Invoke-Git $HostDir @("show", "HEAD:.github/jekyll-obsidian.yml")).Output.Replace("`r`n", "`n").Replace("`r", "`n")
    $indexConfig = (Invoke-Git $HostDir @("show", ":.github/jekyll-obsidian.yml")).Output.Replace("`r`n", "`n").Replace("`r", "`n")
    $worktreeBlock = Get-ManagedConfigBlock $worktreeConfig "worktree configuration"
    $headBlock = Get-ManagedConfigBlock $headConfig "committed configuration"
    $indexBlock = Get-ManagedConfigBlock $indexConfig "staged configuration"
    if ($worktreeBlock -cne $headBlock -or $indexBlock -cne $headBlock) {
        Fail "the managed source/theme configuration block must match HEAD before updating."
    }
    Assert-NotReparsePoint $SiteDir "website"
    Assert-NotReparsePoint (Join-Path $HostDir ".github") ".github"
    Assert-NotReparsePoint (Join-Path $HostDir ".github\workflows") ".github/workflows"
    Assert-NotReparsePoint $LockPath ".github/jekyll-obsidian.lock"
}

function Get-ManagedConfigBlock([string]$Config, [string]$Label) {
    $blockPattern = "(?ms)^$([Regex]::Escape($ConfigStart))`n.*?^$([Regex]::Escape($ConfigEnd))$"
    $blocks = [Regex]::Matches($Config, $blockPattern)
    if ($blocks.Count -ne 1) { Fail "$Label has a malformed managed source/theme block." }
    return $blocks[0].Value
}

function Write-ConfigWithManagedBlock([string]$HostConfigPath, [string]$GeneratedConfigPath, [string]$Destination) {
    $hostBytes = [System.IO.File]::ReadAllBytes($HostConfigPath)
    try { $hostText = $Utf8Strict.GetString($hostBytes) }
    catch { Fail "host configuration is not valid UTF-8." }
    $generatedText = Read-Utf8Normalized $GeneratedConfigPath "candidate host configuration"
    $blockPattern = "(?ms)^$([Regex]::Escape($ConfigStart))\r?`n.*?^$([Regex]::Escape($ConfigEnd))(?=\r?$)"
    $hostBlocks = [Regex]::Matches($hostText, $blockPattern)
    $generatedBlocks = [Regex]::Matches($generatedText, $blockPattern)
    if ($hostBlocks.Count -ne 1 -or $generatedBlocks.Count -ne 1) {
        Fail "host or candidate configuration has a malformed managed source/theme block."
    }

    $hostBlock = $hostBlocks[0].Value
    $generatedBlock = $generatedBlocks[0].Value.Replace("`r`n", "`n").Replace("`r", "`n")
    if ($hostBlock.Replace("`r`n", "`n").Replace("`r", "`n") -ceq $generatedBlock) {
        $replacement = $hostBlock
    }
    else {
        $firstNewline = $hostBlock.IndexOf("`n", [StringComparison]::Ordinal)
        if ($firstNewline -lt 0) { Fail "host managed configuration block has no line ending." }
        $lineEnding = if ($firstNewline -gt 0 -and $hostBlock[$firstNewline - 1] -eq "`r") { "`r`n" } else { "`n" }
        $replacement = $generatedBlock.Replace("`n", $lineEnding)
    }
    $merged = $hostText.Substring(0, $hostBlocks[0].Index) + $replacement +
        $hostText.Substring($hostBlocks[0].Index + $hostBlocks[0].Length)
    [System.IO.File]::WriteAllBytes($Destination, $Utf8NoBom.GetBytes($merged))
}

function Get-ManagedSource([string]$ConfigPath) {
    $config = [System.IO.File]::ReadAllText($ConfigPath).Replace("`r`n", "`n").Replace("`r", "`n")
    $blockPattern = "(?ms)^$([Regex]::Escape($ConfigStart))`n(?<body>.*?)^$([Regex]::Escape($ConfigEnd))$"
    $blocks = [Regex]::Matches($config, $blockPattern)
    if ($blocks.Count -ne 1) { Fail "the managed host configuration block is malformed." }
    $matches = [Regex]::Matches($blocks[0].Groups["body"].Value, "(?m)^  source: '(?<value>(?:[^']|'')*)'$")
    if ($matches.Count -ne 1) { Fail "the managed source entry is malformed." }
    return $matches[0].Groups["value"].Value.Replace("''", "'")
}

function Prepare-ShadowHost([string]$HostDir, [object]$Candidate, [string]$ParentDirectory) {
    $shadow = Join-Path $ParentDirectory "shadow"
    [System.IO.Directory]::CreateDirectory($shadow) | Out-Null
    Copy-Item -Recurse -LiteralPath $Candidate.Site -Destination (Join-Path $shadow "website")
    [System.IO.Directory]::CreateDirectory((Join-Path $shadow ".github\workflows")) | Out-Null
    $configPath = Join-Path $HostDir ".github\jekyll-obsidian.yml"
    $workflowPath = Join-Path $HostDir ".github\workflows\pages.yml"
    Copy-Item -LiteralPath $configPath -Destination (Join-Path $shadow ".github\jekyll-obsidian.yml")
    Copy-Item -LiteralPath $workflowPath -Destination (Join-Path $shadow ".github\workflows\pages.yml")
    $source = Get-ManagedSource $configPath
    $sourcePath = Join-Path $shadow ($source.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $sourcePath)) { [System.IO.Directory]::CreateDirectory($sourcePath) | Out-Null }

    $integrate = Join-Path $shadow "website\bin\integrate.ps1"
    $generated = Invoke-PowerShellFile $integrate @()
    if ($generated.Code -ne 0) { Fail "candidate integration failed: $($generated.Output)" }
    $checked = Invoke-PowerShellFile $integrate @("--check")
    if ($checked.Code -ne 0) { Fail "candidate integration check failed: $($checked.Output)" }
    $mergedConfig = Join-Path $ParentDirectory "managed-host-config.yml"
    Write-ConfigWithManagedBlock $configPath (Join-Path $shadow ".github\jekyll-obsidian.yml") $mergedConfig
    return [PSCustomObject]@{
        Root = $shadow
        Config = $mergedConfig
        Workflow = Join-Path $shadow ".github\workflows\pages.yml"
    }
}

function Get-FileHashValue([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant() }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Assert-NoReparseAncestors([string]$Root, [string]$Path) {
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $current = [System.IO.Directory]::GetParent([System.IO.Path]::GetFullPath($Path))
    while ($null -ne $current -and $current.FullName.Length -ge $rootFull.Length) {
        Assert-NotReparsePoint $current.FullName "managed path ancestor"
        $item = Get-Item -Force -LiteralPath $current.FullName -ErrorAction SilentlyContinue
        if ($null -ne $item -and -not $item.PSIsContainer) {
            Fail "managed path ancestor must be a directory: $($current.FullName)"
        }
        if ($current.FullName.TrimEnd('\') -ceq $rootFull) { return }
        $current = $current.Parent
    }
    Fail "managed update path escaped the host repository."
}

function Assert-ManagedTargetShape([string]$HostDir, [string]$TargetPath) {
    Assert-NoReparseAncestors $HostDir $TargetPath
    Assert-NotReparsePoint $TargetPath "managed update target"
    if ((Test-Path -LiteralPath $TargetPath) -and -not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        Fail "managed update target must be a regular file: $TargetPath"
    }
}

function Assert-IgnoredStateCompatible([string]$HostDir, [object]$Candidate) {
    $ignored = Invoke-Git $HostDir @("-c", "core.quotePath=false", "ls-files", "--others", "--ignored", "--exclude-standard", "--", "website")
    if ([string]::IsNullOrWhiteSpace($ignored.Output)) { return }

    $ignoreRoot = Join-Path ([System.IO.Directory]::GetParent($Candidate.Repository).FullName) "target-ignore-host"
    if (Test-Path -LiteralPath $ignoreRoot) { Remove-Item -Force -Recurse -LiteralPath $ignoreRoot }
    [System.IO.Directory]::CreateDirectory($ignoreRoot) | Out-Null
    try {
        [void](Invoke-Git $HostDir @("init", "--quiet", $ignoreRoot))
        $hostRootIgnore = Join-Path $HostDir ".gitignore"
        if (Test-Path -LiteralPath $hostRootIgnore) {
            Assert-NotReparsePoint $hostRootIgnore "host root .gitignore"
            if (-not (Test-Path -LiteralPath $hostRootIgnore -PathType Leaf)) { Fail "host root .gitignore must be a regular file." }
            Copy-Item -LiteralPath $hostRootIgnore -Destination (Join-Path $ignoreRoot ".gitignore")
        }
        $hostGitDir = (Invoke-Git $HostDir @("rev-parse", "--absolute-git-dir")).Output
        $hostExclude = Join-Path $hostGitDir "info\exclude"
        if (Test-Path -LiteralPath $hostExclude -PathType Leaf) {
            Assert-NotReparsePoint $hostExclude "host Git exclude file"
            Copy-Item -Force -LiteralPath $hostExclude -Destination (Join-Path $ignoreRoot ".git\info\exclude")
        }
        foreach ($entry in $Candidate.Entries) {
            if ($entry.Relative -cne ".gitignore" -and -not $entry.Relative.EndsWith("/.gitignore", [StringComparison]::Ordinal)) { continue }
            $destination = Join-Path $ignoreRoot ($entry.Path.Replace('/', '\'))
            [System.IO.Directory]::CreateDirectory([System.IO.Directory]::GetParent($destination).FullName) | Out-Null
            Copy-Item -LiteralPath (Join-Path $Candidate.Site ($entry.Relative.Replace('/', '\'))) -Destination $destination
        }
        foreach ($path in @($ignored.Output -split "`n")) {
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            Assert-SafeRepositoryPath $path
            $targetRule = Invoke-Git $HostDir @("-C", $ignoreRoot, "check-ignore", "--no-index", "--quiet", "--", $path) $true
            if ($targetRule.Code -ne 0) { Fail "ignored local state would no longer be ignored by the target release: $path" }
        }
    }
    finally {
        if (Test-Path -LiteralPath $ignoreRoot) { Remove-Item -Force -Recurse -LiteralPath $ignoreRoot }
    }
}

function Assert-CandidateInstallable([string]$HostDir, [object]$Candidate) {
    $currentEntries = Get-WebsiteTreeEntries $HostDir "HEAD"
    $current = @{}
    foreach ($entry in $currentEntries) { $current[$entry.Path] = $entry }
    Assert-IgnoredStateCompatible $HostDir $Candidate
    foreach ($entry in $Candidate.Entries) {
        if ($current.ContainsKey($entry.Path) -and $current[$entry.Path].Path -cne $entry.Path) {
            Fail "release contains an unsupported case-only path change: $($current[$entry.Path].Path) -> $($entry.Path)"
        }
        $targetPath = Join-Path $HostDir ($entry.Path.Replace('/', '\'))
        Assert-ManagedTargetShape $HostDir $targetPath
        if (-not $current.ContainsKey($entry.Path) -and (Test-Path -LiteralPath $targetPath)) {
            Fail "target release conflicts with local ignored or untracked state: $($entry.Path)"
        }
    }
}

function Start-UpdateTransaction([string]$TransactionRoot) {
    if (Test-Path -LiteralPath $TransactionRoot) { Fail "recovery_required: an update transaction already exists." }
    $preparingRoot = "$TransactionRoot.preparing.$([Guid]::NewGuid().ToString('N'))"
    try {
        [System.IO.Directory]::CreateDirectory($preparingRoot) | Out-Null
        Write-Utf8Lf (Join-Path $preparingRoot "preparing") "format=1`nstate=preparing`n"
        if (Test-Path -LiteralPath $TransactionRoot) { Fail "recovery_required: an update transaction appeared while preparing." }
        [System.IO.Directory]::Move($preparingRoot, $TransactionRoot)
    }
    finally {
        if (Test-Path -LiteralPath $preparingRoot) { Remove-Item -Force -Recurse -LiteralPath $preparingRoot -ErrorAction SilentlyContinue }
    }
}

function Install-FileAtomically([string]$Source, [string]$Target) {
    $parent = [System.IO.Directory]::GetParent($Target).FullName
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = Join-Path $parent ".$([Guid]::NewGuid().ToString('N')).update.tmp"
    Copy-Item -Force -LiteralPath $Source -Destination $temporary
    $replaceBackup = "$temporary.backup"
    try {
        if (Test-Path -LiteralPath $Target -PathType Leaf) {
            [System.IO.File]::Replace($temporary, $Target, $replaceBackup, $true)
        }
        else {
            [System.IO.File]::Move($temporary, $Target)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -Force -LiteralPath $temporary }
        if (Test-Path -LiteralPath $replaceBackup) { Remove-Item -Force -LiteralPath $replaceBackup }
    }
}

function New-Operation([string]$Target, [string]$Source, [string]$Backup) {
    $oldExists = Test-Path -LiteralPath $Target -PathType Leaf
    $newExists = -not [string]::IsNullOrEmpty($Source)
    if ($oldExists) { Copy-Item -Force -LiteralPath $Target -Destination $Backup }
    return [PSCustomObject]@{
        Target = $Target
        Source = $Source
        Backup = $Backup
        OldExists = [bool]$oldExists
        OldHash = if ($oldExists) { Get-FileHashValue $Target } else { $null }
        NewExists = [bool]$newExists
        NewHash = if ($newExists) { Get-FileHashValue $Source } else { $null }
    }
}

function Test-OperationState([object]$Operation, [bool]$NewState) {
    $expectedExists = if ($NewState) { $Operation.NewExists } else { $Operation.OldExists }
    $expectedHash = if ($NewState) { $Operation.NewHash } else { $Operation.OldHash }
    $exists = Test-Path -LiteralPath $Operation.Target
    if (-not $expectedExists) { return -not $exists }
    if (-not $exists -or -not (Test-Path -LiteralPath $Operation.Target -PathType Leaf)) { return $false }
    return (Get-FileHashValue $Operation.Target) -ceq [string]$expectedHash
}

function Get-ChangedOperationPaths([string]$HostDir, [object[]]$Operations) {
    $hostPrefix = [System.IO.Path]::GetFullPath($HostDir).TrimEnd('\') + '\'
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($operation in $Operations) {
        if ([bool]$operation.OldExists -eq [bool]$operation.NewExists -and
            [string]$operation.OldHash -ceq [string]$operation.NewHash) { continue }
        $target = [System.IO.Path]::GetFullPath([string]$operation.Target)
        if (-not $target.StartsWith($hostPrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        [void]$paths.Add($target.Substring($hostPrefix.Length).Replace('\', '/'))
    }
    return @($paths.ToArray() | Sort-Object -Unique)
}

function Write-ChangedPaths([string[]]$Paths) {
    if ($Paths.Count -eq 0) { return }
    Write-Output "Changed managed paths:"
    foreach ($path in $Paths) { Write-Output "  $path" }
}

function Restore-Operations([object[]]$Operations) {
    foreach ($operation in $Operations) {
        if (-not (Test-OperationState $operation $false) -and -not (Test-OperationState $operation $true)) {
            Fail "recovery_required: managed path has neither its old nor new digest: $($operation.Target)"
        }
        if ($operation.OldExists -and (Get-FileHashValue $operation.Backup) -cne [string]$operation.OldHash) {
            Fail "recovery_required: transaction backup is invalid: $($operation.Target)"
        }
    }
    for ($index = $Operations.Count - 1; $index -ge 0; $index--) {
        $operation = $Operations[$index]
        if ($operation.OldExists) { Install-FileAtomically $operation.Backup $operation.Target }
        elseif (Test-Path -LiteralPath $operation.Target) { Remove-Item -Force -LiteralPath $operation.Target }
    }
}

function Test-PathInside([string]$Root, [string]$Path) {
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    return $pathFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparseTree([string]$Root) {
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in @(Get-ChildItem -Force -LiteralPath $directory)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Fail "recovery_required: update transaction contains a symbolic link, junction, or reparse point."
            }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
        }
    }
}

function Enter-UpdateMutex([string]$HostDir) {
    $identity = [System.IO.Path]::GetFullPath($HostDir).TrimEnd('\').ToUpperInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = ([BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($identity)))).Replace("-", "") }
    finally { $sha.Dispose() }
    $mutex = New-Object System.Threading.Mutex($false, "Local\jekyll-obsidian-update-$digest")
    $acquired = $false
    try { $acquired = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) {
        $mutex.Dispose()
        Fail "another jekyll-obsidian updater is already running for this host."
    }
    return $mutex
}

function Read-TransactionOperations([string]$HostDir, [string]$TransactionRoot) {
    $journalPath = Join-Path $TransactionRoot "journal"
    $text = Read-Utf8Lf $journalPath "update transaction journal"
    try { $journal = $text | ConvertFrom-Json }
    catch { Fail "recovery_required: update transaction journal is malformed." }
    $journalProperties = @($journal.PSObject.Properties.Name | Sort-Object)
    if (($journalProperties -join ',') -cne "Format,NewVersion,OldVersion,Operations,State" -or [int]$journal.Format -ne 1 -or
        @("prepared", "applying", "verified") -cnotcontains $journal.State) {
        Fail "recovery_required: update transaction journal has an unsupported format."
    }
    [void](Get-CalVer ([string]$journal.OldVersion) "transaction old version")
    [void](Get-CalVer ([string]$journal.NewVersion) "transaction new version")
    $operations = New-Object System.Collections.Generic.List[object]
    $seenTargets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $seenBackups = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $backupRoot = Join-Path $TransactionRoot "backup"
    foreach ($operation in @($journal.Operations)) {
        $properties = @($operation.PSObject.Properties.Name | Sort-Object)
        if (($properties -join ',') -cne "Backup,NewExists,NewHash,OldExists,OldHash,Source,Target" -or
            $operation.OldExists -isnot [bool] -or $operation.NewExists -isnot [bool]) {
            Fail "recovery_required: update transaction operation is malformed."
        }
        $target = [string]$operation.Target
        $backup = [string]$operation.Backup
        if (-not (Test-PathInside $HostDir $target) -or -not (Test-PathInside $backupRoot $backup) -or
            -not $seenTargets.Add([System.IO.Path]::GetFullPath($target)) -or -not $seenBackups.Add([System.IO.Path]::GetFullPath($backup))) {
            Fail "recovery_required: update transaction path escaped its repository."
        }
        $relative = [System.IO.Path]::GetFullPath($target).Substring([System.IO.Path]::GetFullPath($HostDir).TrimEnd('\').Length + 1).Replace('\', '/')
        if (-not $relative.StartsWith("website/", [StringComparison]::Ordinal) -and
            @(".github/jekyll-obsidian.yml", ".github/workflows/pages.yml", ".github/jekyll-obsidian.lock") -cnotcontains $relative) {
            Fail "recovery_required: update transaction targets an unmanaged path."
        }
        Assert-NoReparseAncestors $HostDir $target
        Assert-NotReparsePoint $target "managed transaction target"
        Assert-NoReparseAncestors $TransactionRoot $backup
        Assert-NotReparsePoint $backup "managed transaction backup"
        if ($operation.OldExists -and [string]$operation.OldHash -notmatch '^[0-9a-f]{64}$') { Fail "recovery_required: invalid old digest." }
        if ($operation.NewExists -and [string]$operation.NewHash -notmatch '^[0-9a-f]{64}$') { Fail "recovery_required: invalid new digest." }
        [void]$operations.Add($operation)
    }
    if ($operations.Count -eq 0) { Fail "recovery_required: update transaction has no operations." }
    return [PSCustomObject]@{
        State = [string]$journal.State
        OldVersion = [string]$journal.OldVersion
        NewVersion = [string]$journal.NewVersion
        Operations = $operations.ToArray()
    }
}

function Recover-PendingTransaction([string]$HostDir, [string]$TransactionRoot, [bool]$CheckOnly) {
    $completedRoot = "$TransactionRoot.completed"
    if (Test-Path -LiteralPath $completedRoot) {
        Assert-NotReparsePoint $completedRoot "completed update transaction directory"
        if (Test-Path -LiteralPath $TransactionRoot) { Fail "recovery_required: active and completed update transactions both exist." }
        if ($CheckOnly) { Fail "recovery_required: a completed update transaction requires a normal update run." }
        if (-not (Test-Path -LiteralPath $completedRoot -PathType Container)) {
            Fail "recovery_required: completed update transaction path is not a directory."
        }
        Assert-NoReparseTree $completedRoot
        Remove-Item -Force -Recurse -LiteralPath $completedRoot
        return [PSCustomObject]@{
            Completed = $true
            Message = "Finalized a previously verified jekyll-obsidian update."
            ChangedPaths = @()
        }
    }
    if (-not (Test-Path -LiteralPath $TransactionRoot)) { return }
    Assert-NotReparsePoint $TransactionRoot "update transaction directory"
    if (-not (Test-Path -LiteralPath $TransactionRoot -PathType Container)) { Fail "recovery_required: update transaction path is not a directory." }
    $journalPath = Join-Path $TransactionRoot "journal"
    $markerPath = Join-Path $TransactionRoot "preparing"
    if ($CheckOnly) { Fail "recovery_required: a pending update transaction requires a normal update run." }
    if (-not (Test-Path -LiteralPath $journalPath)) {
        $marker = Read-Utf8Lf $markerPath "update transaction marker"
        if ($marker -cne "format=1`nstate=preparing`n") { Fail "recovery_required: update transaction has no valid journal or preparation marker." }
        Assert-NoReparseTree $TransactionRoot
        Remove-Item -Force -Recurse -LiteralPath $TransactionRoot
        return [PSCustomObject]@{ Completed = $false; Message = "Discarded an interrupted update before managed files were changed." }
    }
    Assert-NotReparsePoint $journalPath "update transaction journal"
    $transaction = Read-TransactionOperations $HostDir $TransactionRoot
    $allOld = $true
    $allNew = $true
    foreach ($operation in $transaction.Operations) {
        if (-not (Test-OperationState $operation $false)) { $allOld = $false }
        if (-not (Test-OperationState $operation $true)) { $allNew = $false }
    }
    if (-not $allOld -and -not $allNew) {
        Fail "recovery_required: the unfinished transaction is neither a complete old nor complete new snapshot; journal and backups were preserved."
    }
    if ($allNew -and $transaction.State -cne "verified") {
        try {
            [void](Read-ReleaseMetadata (Join-Path $HostDir "website") $transaction.NewVersion)
            $recoveredLock = Read-ProvenanceLock (Join-Path $HostDir ".github\jekyll-obsidian.lock")
            if ($recoveredLock.Version -cne $transaction.NewVersion) {
                Fail "recovered provenance version does not match transaction version $($transaction.NewVersion)."
            }
            foreach ($operation in $transaction.Operations) {
                if (-not (Test-OperationState $operation $true)) { Fail "recovered managed path failed its new digest check: $($operation.Target)" }
            }
            $recoveredIntegration = Invoke-PowerShellFile (Join-Path $HostDir "website\bin\integrate.ps1") @("--check")
            if ($recoveredIntegration.Code -ne 0) { Fail "recovered host integration is invalid: $($recoveredIntegration.Output)" }
        }
        catch {
            Fail "recovery_required: the all-new applying transaction did not pass post-install validation; journal and backups were preserved. $($_.Exception.Message)"
        }
    }
    Assert-NoReparseTree $TransactionRoot
    Remove-Item -Force -Recurse -LiteralPath $TransactionRoot
    if ($allNew) {
        return [PSCustomObject]@{
            Completed = $true
            Message = "Recovered completed jekyll-obsidian update $($transaction.OldVersion) -> $($transaction.NewVersion)."
            ChangedPaths = @(Get-ChangedOperationPaths $HostDir $transaction.Operations)
        }
    }
    return [PSCustomObject]@{
        Completed = $false
        Message = "Recovered rolled-back jekyll-obsidian update $($transaction.OldVersion) -> $($transaction.NewVersion)."
        ChangedPaths = @()
    }
}

function Finalize-UpdateTransaction([string]$TransactionRoot) {
    $completedRoot = "$TransactionRoot.completed"
    if (Test-Path -LiteralPath $completedRoot) { Fail "recovery_required: completed transaction cleanup already exists." }
    if (-not (Test-Path -LiteralPath (Join-Path $TransactionRoot "journal") -PathType Leaf)) {
        Fail "recovery_required: verified transaction journal disappeared before finalization."
    }
    [System.IO.Directory]::Move($TransactionRoot, $completedRoot)
    Assert-NoReparseTree $completedRoot
    Remove-Item -Force -Recurse -LiteralPath $completedRoot
}

function Write-TransactionJournal([string]$TransactionRoot, [string]$State, [string]$OldVersion, [string]$NewVersion, [object[]]$Operations) {
    $journalPath = Join-Path $TransactionRoot "journal"
    $journalStage = Join-Path $TransactionRoot "journal.next"
    $journal = [PSCustomObject]@{
        Format = 1
        State = $State
        OldVersion = $OldVersion
        NewVersion = $NewVersion
        Operations = $Operations
    }
    Write-Utf8Lf $journalStage (($journal | ConvertTo-Json -Depth 6) + "`n")
    try { Install-FileAtomically $journalStage $journalPath }
    finally { if (Test-Path -LiteralPath $journalStage) { Remove-Item -Force -LiteralPath $journalStage } }
}

function Apply-Update([string]$HostDir, [string]$SiteDir, [object]$Candidate, [object]$Shadow, [string]$LockText, [string]$TransactionRoot, [string]$OldVersion, [string]$NewVersion) {
    $backupRoot = Join-Path $TransactionRoot "backup"
    $stageRoot = Join-Path $TransactionRoot "stage"
    [System.IO.Directory]::CreateDirectory($backupRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($stageRoot) | Out-Null

    $currentEntries = Get-WebsiteTreeEntries $HostDir "HEAD"
    $current = @{}
    foreach ($entry in $currentEntries) { $current[$entry.Path] = $entry }
    $target = @{}
    foreach ($entry in $Candidate.Entries) { $target[$entry.Path] = $entry }

    Assert-IgnoredStateCompatible $HostDir $Candidate
    foreach ($entry in $Candidate.Entries) {
        if ($current.ContainsKey($entry.Path) -and $current[$entry.Path].Path -cne $entry.Path) {
            Fail "release contains an unsupported case-only path change: $($current[$entry.Path].Path) -> $($entry.Path)"
        }
        $targetPath = Join-Path $HostDir ($entry.Path.Replace('/', '\'))
        Assert-ManagedTargetShape $HostDir $targetPath
        if (-not $current.ContainsKey($entry.Path) -and (Test-Path -LiteralPath $targetPath)) {
            Fail "target release conflicts with local ignored or untracked state: $($entry.Path)"
        }
    }

    $lockStage = Join-Path $stageRoot "jekyll-obsidian.lock"
    Write-Utf8Lf $lockStage $LockText
    $operationSpecs = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $currentEntries) {
        if (-not $target.ContainsKey($entry.Path)) {
            [void]$operationSpecs.Add([PSCustomObject]@{ Target = Join-Path $HostDir ($entry.Path.Replace('/', '\')); Source = $null })
        }
    }
    foreach ($entry in $Candidate.Entries) {
        [void]$operationSpecs.Add([PSCustomObject]@{
            Target = Join-Path $HostDir ($entry.Path.Replace('/', '\'))
            Source = Join-Path $Candidate.Site ($entry.Relative.Replace('/', '\'))
        })
    }
    [void]$operationSpecs.Add([PSCustomObject]@{ Target = Join-Path $HostDir ".github\jekyll-obsidian.yml"; Source = $Shadow.Config })
    [void]$operationSpecs.Add([PSCustomObject]@{ Target = Join-Path $HostDir ".github\workflows\pages.yml"; Source = $Shadow.Workflow })
    [void]$operationSpecs.Add([PSCustomObject]@{ Target = Join-Path $HostDir ".github\jekyll-obsidian.lock"; Source = $lockStage })

    $operations = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $operationSpecs.Count; $index++) {
        $spec = $operationSpecs[$index]
        Assert-ManagedTargetShape $HostDir $spec.Target
        [void]$operations.Add((New-Operation $spec.Target $spec.Source (Join-Path $backupRoot "$index")))
    }
    $journalPath = Join-Path $TransactionRoot "journal"
    Write-TransactionJournal $TransactionRoot "prepared" $OldVersion $NewVersion $operations.ToArray()
    Write-TransactionJournal $TransactionRoot "applying" $OldVersion $NewVersion $operations.ToArray()
    if ($TestFailAt -ceq "pause_after_transaction_claim") {
        $pausePath = Join-Path $TransactionRoot "test-paused"
        $continuePath = Join-Path $TransactionRoot "test-continue"
        Write-Utf8Lf $pausePath "ready`n"
        for ($attempt = 0; $attempt -lt 600 -and -not (Test-Path -LiteralPath $continuePath -PathType Leaf); $attempt++) {
            Start-Sleep -Milliseconds 50
        }
        if (-not (Test-Path -LiteralPath $continuePath -PathType Leaf)) { Fail "internal transaction pause timed out." }
        Remove-Item -Force -LiteralPath $pausePath, $continuePath
    }

    try {
        $changedInstallCount = 0
        foreach ($operation in $operations) {
            $operationChanged = [bool]$operation.OldExists -ne [bool]$operation.NewExists -or
                [string]$operation.OldHash -cne [string]$operation.NewHash
            if ($operation.NewExists) { Install-FileAtomically $operation.Source $operation.Target }
            elseif (Test-Path -LiteralPath $operation.Target) { Remove-Item -Force -LiteralPath $operation.Target }
            if ($operationChanged) {
                $changedInstallCount++
                if ($changedInstallCount -eq 1 -and $TestFailAt -ceq "fail_after_first_file") {
                    Fail "injected transaction failure after the first changed managed file."
                }
            }
        }
        if ($TestFailAt -ceq "crash_after_all_renames") { Stop-Process -Id $PID -Force }
        $check = Invoke-PowerShellFile (Join-Path $SiteDir "bin\integrate.ps1") @("--check")
        if ($check.Code -ne 0) { Fail "updated host integration is invalid: $($check.Output)" }
        foreach ($operation in $operations) {
            if (-not (Test-OperationState $operation $true)) { Fail "installed managed path failed its digest check: $($operation.Target)" }
        }
        Write-TransactionJournal $TransactionRoot "verified" $OldVersion $NewVersion $operations.ToArray()
        return [PSCustomObject]@{ ChangedPaths = @(Get-ChangedOperationPaths $HostDir $operations.ToArray()) }
    }
    catch {
        try {
            Restore-Operations $operations.ToArray()
            if (Test-Path -LiteralPath $journalPath) { Remove-Item -Force -LiteralPath $journalPath }
        }
        catch {
            Fail $_.Exception.Message
        }
        throw
    }
}

$CheckOnly = $false
$RequestedVersion = $null
$ToWasSet = $false
$WorkingDirectory = $null
$TransactionRoot = $null
$ControllerRoot = $null
$RunMutex = $null
$OwnsTransaction = $false
$PublicArguments = @($args)
$IsWorker = $false

try {
    for ($index = 0; $index -lt $args.Count; $index++) {
        switch -CaseSensitive ($args[$index]) {
            "--check" {
                if ($CheckOnly) { Fail "--check may be specified only once." }
                $CheckOnly = $true
            }
            "--to" {
                if ($ToWasSet) { Fail "--to may be specified only once." }
                if ($index + 1 -ge $args.Count) { Fail "--to requires a value." }
                $index++
                $RequestedVersion = $args[$index]
                [void](Get-CalVer $RequestedVersion "--to")
                $ToWasSet = $true
            }
            "--help" { Show-Usage; exit 0 }
            "-h" { Show-Usage; exit 0 }
            default { Show-Usage; Fail "unknown option: $($args[$index])" }
        }
    }

    if ($null -eq (Get-Command git.exe -ErrorAction SilentlyContinue)) { Fail "Git is required to update the managed snapshot." }
    $IsWorker = $env:JEKYLL_OBSIDIAN_UPDATE_WORKER -ceq "1"
    if ($IsWorker) {
        if ([string]::IsNullOrWhiteSpace($env:JEKYLL_OBSIDIAN_UPDATE_WORKER_HOST)) { Fail "internal update worker is missing its host root." }
        $HostDir = [System.IO.Path]::GetFullPath($env:JEKYLL_OBSIDIAN_UPDATE_WORKER_HOST)
        $SiteDir = Join-Path $HostDir "website"
        $ScriptDir = Join-Path $SiteDir "bin"
    }
    else {
        $ScriptDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
        $SiteDir = [System.IO.Directory]::GetParent($ScriptDir).FullName
        $HostDir = [System.IO.Directory]::GetParent($SiteDir).FullName
    }
    if ([System.IO.Path]::GetFileName($SiteDir) -cne "website") { Fail "the site directory must be named website and live at the host repository root." }
    $gitRoot = (Invoke-Git $HostDir @("rev-parse", "--show-toplevel")).Output
    if ([System.IO.Path]::GetFullPath($gitRoot).TrimEnd('\') -ine [System.IO.Path]::GetFullPath($HostDir).TrimEnd('\')) {
        Fail "website must live at the root of its Git worktree."
    }

    if (-not $CheckOnly -and -not $IsWorker) {
        $ControllerRoot = Join-Path ([System.IO.Path]::GetTempPath()) "jekyll-obsidian-update-controller-$([Guid]::NewGuid().ToString('N'))"
        [System.IO.Directory]::CreateDirectory($ControllerRoot) | Out-Null
        $controller = Join-Path $ControllerRoot "controller.ps1"
        Copy-Item -LiteralPath $PSCommandPath -Destination $controller
        $env:JEKYLL_OBSIDIAN_UPDATE_WORKER = "1"
        $env:JEKYLL_OBSIDIAN_UPDATE_WORKER_HOST = $HostDir
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $executable = (Get-Process -Id $PID).Path
            & $executable -NoLogo -NoProfile -ExecutionPolicy Bypass -File $controller @PublicArguments
            $workerCode = $LASTEXITCODE
            $global:LASTEXITCODE = 0
        }
        finally {
            $ErrorActionPreference = $previousErrorAction
            Remove-Item Env:\JEKYLL_OBSIDIAN_UPDATE_WORKER -ErrorAction SilentlyContinue
            Remove-Item Env:\JEKYLL_OBSIDIAN_UPDATE_WORKER_HOST -ErrorAction SilentlyContinue
        }
        exit $workerCode
    }

    $RunMutex = Enter-UpdateMutex $HostDir
    $TransactionRoot = Join-Path $HostDir ".jekyll-obsidian-update"
    $recovery = Recover-PendingTransaction $HostDir $TransactionRoot $CheckOnly
    if ($null -ne $recovery) {
        Write-Output $recovery.Message
        if ($recovery.Completed) {
            Write-ChangedPaths $recovery.ChangedPaths
            Write-Output "Review git diff, run website\bin\setup if local dependencies changed, then commit the managed files."
            exit 0
        }
    }

    $LockPath = Join-Path $HostDir ".github\jekyll-obsidian.lock"
    Assert-CleanManagedState $HostDir $SiteDir $LockPath
    $installed = Read-ReleaseMetadata $SiteDir $null
    $installedCalVer = Get-CalVer $installed.Version "installed version"
    $transport = Get-TransportOrigin
    $temporaryParent = Join-Path ([System.IO.Path]::GetTempPath()) "jekyll-obsidian-update-$([Guid]::NewGuid().ToString('N'))"
    [System.IO.Directory]::CreateDirectory($temporaryParent) | Out-Null
    $WorkingDirectory = $temporaryParent
    $releases = @(Get-RemoteReleases $temporaryParent $transport)
    $targetRelease = Select-RemoteRelease $releases $RequestedVersion
    $targetCalVer = Get-CalVer $targetRelease.Version "target version"
    if ($targetCalVer.Date -lt $installedCalVer.Date) { Fail "downgrade from $($installed.Version) to $($targetRelease.Version) is not allowed." }

    $currentRelease = Get-ReleaseByVersion $releases $installed.Version
    $currentCandidate = Fetch-Release $temporaryParent $transport $currentRelease (Join-Path $temporaryParent "current")
    $headEntries = @(Get-WebsiteTreeEntries $HostDir "HEAD")
    $hasLock = Test-Path -LiteralPath $LockPath -PathType Leaf
    if ($hasLock) {
        $lock = Read-ProvenanceLock $LockPath
        if ($lock.Version -cne $installed.Version -or $lock.TagObject -cne $currentRelease.TagObject -or
            $lock.Commit -cne $currentRelease.Commit -or $lock.Tree -cne $currentCandidate.Tree -or
            -not (Test-WebsiteEntriesEqual $headEntries $currentCandidate.Entries)) {
            Fail "installed provenance does not match the committed website snapshot or official tag."
        }
    }
    elseif (-not (Test-WebsiteEntriesEqual $headEntries $currentCandidate.Entries)) {
        Fail "the unrecorded website snapshot does not exactly match official release v$($installed.Version)."
    }

    if ($targetRelease.Version -ceq $installed.Version) {
        if ($hasLock) {
            Write-Output "jekyll-obsidian $($installed.Version) is current."
            exit 0
        }
        if ($CheckOnly) {
            Write-Output "Provenance can be established for $($installed.Version)."
            exit 2
        }
        $lockText = "format=1`norigin=$CanonicalOrigin`nversion=$($currentRelease.Version)`ntag=$($currentRelease.Tag)`ntag_object=$($currentRelease.TagObject)`ncommit=$($currentRelease.Commit)`nwebsite_tree=$($currentCandidate.Tree)`n"
        Assert-NoReparseAncestors $HostDir $LockPath
        if (Test-Path -LiteralPath $LockPath) { Fail "the provenance lock appeared while adoption was being prepared." }
        $lockStage = Join-Path $temporaryParent "jekyll-obsidian.lock"
        Write-Utf8Lf $lockStage $lockText
        Install-FileAtomically $lockStage $LockPath
        Write-Output "Recorded jekyll-obsidian provenance for $($installed.Version)."
        Write-ChangedPaths @(".github/jekyll-obsidian.lock")
        Write-Output "Review git diff, then commit the managed snapshot and provenance lock."
        exit 0
    }

    $candidate = Fetch-Release $temporaryParent $transport $targetRelease (Join-Path $temporaryParent "target")
    Assert-CandidateInstallable $HostDir $candidate
    $shadow = Prepare-ShadowHost $HostDir $candidate $temporaryParent
    if ($CheckOnly) {
        Write-Output "Update available: $($installed.Version) -> $($targetRelease.Version)."
        exit 2
    }

    $lockText = "format=1`norigin=$CanonicalOrigin`nversion=$($targetRelease.Version)`ntag=$($targetRelease.Tag)`ntag_object=$($targetRelease.TagObject)`ncommit=$($targetRelease.Commit)`nwebsite_tree=$($candidate.Tree)`n"
    Start-UpdateTransaction $TransactionRoot
    $OwnsTransaction = $true
    try {
        $applyResult = Apply-Update $HostDir $SiteDir $candidate $shadow $lockText $TransactionRoot $installed.Version $targetRelease.Version
        Finalize-UpdateTransaction $TransactionRoot
        $OwnsTransaction = $false
    }
    finally {
        if ($OwnsTransaction -and (Test-Path -LiteralPath $TransactionRoot) -and -not (Test-Path -LiteralPath (Join-Path $TransactionRoot "journal"))) {
            Remove-Item -Force -Recurse -LiteralPath $TransactionRoot
            $OwnsTransaction = $false
        }
    }
    Write-Output "Updated jekyll-obsidian from $($installed.Version) to $($targetRelease.Version)."
    Write-ChangedPaths $applyResult.ChangedPaths
    Write-Output "Review git diff, run website\bin\setup if local dependencies changed, then commit the managed files."
    exit 0
}
catch {
    $message = $_.Exception.Message
    if (-not $message.StartsWith("Update error: ", [StringComparison]::Ordinal)) { $message = "Update error: $message" }
    [Console]::Error.WriteLine($message)
    if ($env:JEKYLL_OBSIDIAN_UPDATE_TESTING -ceq "1" -and -not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
        [Console]::Error.WriteLine($_.ScriptStackTrace)
    }
    exit 1
}
finally {
    if (-not [string]::IsNullOrEmpty($WorkingDirectory) -and (Test-Path -LiteralPath $WorkingDirectory)) {
        Remove-Item -Force -Recurse -LiteralPath $WorkingDirectory -ErrorAction SilentlyContinue
    }
    if (-not [string]::IsNullOrEmpty($ControllerRoot) -and (Test-Path -LiteralPath $ControllerRoot)) {
        Remove-Item -Force -Recurse -LiteralPath $ControllerRoot -ErrorAction SilentlyContinue
    }
    if ($null -ne $RunMutex) {
        try { $RunMutex.ReleaseMutex() } catch { }
        $RunMutex.Dispose()
    }
}
