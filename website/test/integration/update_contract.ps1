$ErrorActionPreference = "Stop"

$TestDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$SiteDir = [System.IO.Directory]::GetParent([System.IO.Directory]::GetParent($TestDir).FullName).FullName
$TemporaryRoots = New-Object System.Collections.Generic.List[string]
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) { throw "Windows update contract failed: $Message" }

function Write-Lf([string]$Path, [string]$Content) {
    $parent = [System.IO.Directory]::GetParent($Path)
    if ($null -ne $parent) { [System.IO.Directory]::CreateDirectory($parent.FullName) | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n").Replace("`r", "`n"), $Utf8NoBom)
}

function Get-Sha256([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant() }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-ManagedFingerprint([string]$Root) {
    $tracked = Invoke-TestGit $Root @("ls-files", "--", "website", ".github/jekyll-obsidian.yml", ".github/workflows/pages.yml")
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($relative in @($tracked -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        $path = Join-Path $Root ($relative.Replace('/', '\'))
        $item = Get-Item -Force -LiteralPath $path
        [void]$rows.Add("$relative|$(Get-Sha256 $path)|$($item.LastWriteTimeUtc.Ticks)")
    }
    return ($rows.ToArray() -join "`n")
}

function Get-ConfigOwnerFingerprint([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path)
    $pattern = '(?ms)^  # jekyll-obsidian:managed-start\r?\n.*?^  # jekyll-obsidian:managed-end(?=\r?$)'
    $blocks = [Regex]::Matches($text, $pattern)
    if ($blocks.Count -ne 1) { Fail "could not fingerprint host-owned configuration bytes" }
    return $text.Substring(0, $blocks[0].Index) + "<managed-block>" +
        $text.Substring($blocks[0].Index + $blocks[0].Length)
}

function Get-TransactionEvidenceFingerprint([string]$TransactionRoot) {
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($file in @(Get-ChildItem -File -Recurse -LiteralPath $TransactionRoot | Where-Object {
        $_.FullName -eq (Join-Path $TransactionRoot "journal") -or
        $_.FullName.StartsWith((Join-Path $TransactionRoot "backup") + "\", [StringComparison]::OrdinalIgnoreCase)
    } | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($TransactionRoot.Length + 1)
        [void]$rows.Add("$relative|$(Get-Sha256 $file.FullName)")
    }
    return ($rows.ToArray() -join "`n")
}

function Invoke-TestGit([string]$Root, [string[]]$Arguments) {
    Push-Location $Root
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git.exe @Arguments 2>&1
        $code = $LASTEXITCODE
        $global:LASTEXITCODE = 0
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
        Pop-Location
    }
    if ($code -ne 0) { Fail "git $($Arguments -join ' ') exited with $code`: $($output -join "`n")" }
    return ($output -join "`n").Trim()
}

function Write-ReleaseSite([string]$Root, [string]$Version, [string]$Marker) {
    $site = Join-Path $Root "website"
    [System.IO.Directory]::CreateDirectory((Join-Path $site "bin")) | Out-Null
    [System.IO.Directory]::CreateDirectory((Join-Path $site "scripts\templates")) | Out-Null
    foreach ($file in @("build", "integrate", "integrate.ps1", "integrate.cmd", "setup", "test", "update", "update.ps1", "update.cmd")) {
        Copy-Item -Force -LiteralPath (Join-Path $SiteDir "bin\$file") -Destination (Join-Path $site "bin\$file")
    }
    Copy-Item -Force -LiteralPath (Join-Path $SiteDir "scripts\example-config.yml") -Destination (Join-Path $site "scripts\example-config.yml")
    foreach ($file in @("host-config.yml", "pages.yml")) {
        Copy-Item -Force -LiteralPath (Join-Path $SiteDir "scripts\templates\$file") -Destination (Join-Path $site "scripts\templates\$file")
    }
    Copy-Item -Force -LiteralPath (Join-Path $SiteDir ".gitattributes") -Destination (Join-Path $site ".gitattributes")
    Write-Lf (Join-Path $site ".jekyll-obsidian-release") "format=1`nversion=$Version`nupdater_protocol=1`n"
    Write-Lf (Join-Path $site ".gitignore") "/node_modules/`n/.env`n"
    Write-Lf (Join-Path $site "package.json") "{`n  `"name`": `"jekyll-obsidian`",`n  `"version`": `"$Version`"`n}`n"
    Write-Lf (Join-Path $site "package-lock.json") "{`n  `"name`": `"jekyll-obsidian`",`n  `"version`": `"$Version`",`n  `"lockfileVersion`": 3,`n  `"packages`": {`n    `"`": {`n      `"name`": `"jekyll-obsidian`",`n      `"version`": `"$Version`"`n    }`n  }`n}`n"
    Write-Lf (Join-Path $site "lib\jekyll_obsidian.rb") "module JekyllObsidian`n  VERSION = `"$Version`"`nend`n"
    Write-Lf (Join-Path $site "snapshot.txt") "$Marker`n"
    foreach ($executable in @("build", "integrate", "setup", "test", "update")) {
        [void](Invoke-TestGit $Root @("add", "website/bin/$executable"))
        [void](Invoke-TestGit $Root @("update-index", "--chmod=+x", "website/bin/$executable"))
    }
}

function New-ReleaseRepository {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "jekyll obsidian releases $([Guid]::NewGuid().ToString('N'))"
    [void]$TemporaryRoots.Add($root)
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    [void](Invoke-TestGit $root @("init", "--quiet"))
    [void](Invoke-TestGit $root @("config", "user.name", "Update Contract"))
    [void](Invoke-TestGit $root @("config", "user.email", "update-contract@example.invalid"))

    Write-ReleaseSite $root "2026.8.6" "current snapshot"
    [void](Invoke-TestGit $root @("add", "website"))
    [void](Invoke-TestGit $root @("commit", "--quiet", "-m", "current release"))
    [void](Invoke-TestGit $root @("tag", "-a", "v2026.8.6", "-m", "v2026.8.6"))

    Write-ReleaseSite $root "2026.8.7" "next snapshot"
    Write-Lf (Join-Path $root "website\new-file.txt") "new release file`n"
    [void](Invoke-TestGit $root @("add", "website"))
    [void](Invoke-TestGit $root @("commit", "--quiet", "-m", "next release"))
    [void](Invoke-TestGit $root @("tag", "-a", "v2026.8.7", "-m", "v2026.8.7"))
    [void](Invoke-TestGit $root @("tag", "vpreview"))

    $bare = "$root.git"
    [void]$TemporaryRoots.Add($bare)
    $parent = [System.IO.Directory]::GetParent($root).FullName
    [void](Invoke-TestGit $parent @("clone", "--quiet", "--bare", $root, $bare))
    $branch = Invoke-TestGit $root @("symbolic-ref", "--short", "HEAD")
    return @{ Work = $root; Bare = $bare; Origin = ([Uri]$bare).AbsoluteUri; Branch = $branch }
}

function New-TestHost {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "jekyll obsidian update $([Guid]::NewGuid().ToString('N'))"
    [void]$TemporaryRoots.Add($root)
    [System.IO.Directory]::CreateDirectory((Join-Path $root "website\bin")) | Out-Null
    Copy-Item -LiteralPath (Join-Path $SiteDir "bin\update.ps1") -Destination (Join-Path $root "website\bin\update.ps1")
    Copy-Item -LiteralPath (Join-Path $SiteDir "bin\update.cmd") -Destination (Join-Path $root "website\bin\update.cmd")
    return $root
}

function New-IntegratedHost([hashtable]$Release) {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "jekyll obsidian host $([Guid]::NewGuid().ToString('N'))"
    [void]$TemporaryRoots.Add($root)
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    [void](Invoke-TestGit $root @("init", "--quiet"))
    [void](Invoke-TestGit $root @("config", "user.name", "Update Contract"))
    [void](Invoke-TestGit $root @("config", "user.email", "update-contract@example.invalid"))

    [void](Invoke-TestGit $Release.Work @("checkout", "--quiet", "--detach", "v2026.8.6"))
    Copy-Item -Recurse -LiteralPath (Join-Path $Release.Work "website") -Destination (Join-Path $root "website")
    [System.IO.Directory]::CreateDirectory((Join-Path $root "docs")) | Out-Null
    Write-Lf (Join-Path $root "docs\Start.md") "---`npublish: true`n---`n# Start`n"

    Push-Location $root
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $integrationOutput = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "website\bin\integrate.ps1") 2>&1
        $integrationCode = $LASTEXITCODE
        $global:LASTEXITCODE = 0
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
        Pop-Location
    }
    if ($integrationCode -ne 0) { Fail "fixture integration failed: $($integrationOutput -join "`n")" }
    $configPath = Join-Path $root ".github\jekyll-obsidian.yml"
    $config = [System.IO.File]::ReadAllText($configPath).Replace("title: My Project Documentation", "title: Preserved host title")
    Write-Lf $configPath $config
    Write-Lf (Join-Path $root ".gitignore") "/website/host-cache/`n"
    [void](Invoke-TestGit $root @("add", "."))
    [void](Invoke-TestGit $root @("commit", "--quiet", "-m", "integrated host"))

    Write-Lf (Join-Path $root "website\node_modules\cache.txt") "preserve ignored cache`n"
    Write-Lf (Join-Path $root "website\host-cache\cache.txt") "preserve host-root ignored cache`n"
    Write-Lf (Join-Path $root "content-draft.md") "unrelated dirty host content`n"
    return $root
}

function Invoke-Adapter([string]$Adapter, [string]$Root, [string[]]$Arguments) {
    $script = Join-Path $Root "website\bin\update.ps1"
    Push-Location $Root
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = switch ($Adapter) {
            "cmd" { & (Join-Path $Root "website\bin\update.cmd") @Arguments 2>&1 }
            "windows-powershell" { & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script @Arguments 2>&1 }
            "pwsh" { & pwsh.exe -NoLogo -NoProfile -File $script @Arguments 2>&1 }
            default { Fail "unknown adapter $Adapter" }
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
        Pop-Location
    }
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    return @{ Code = $code; Output = ($output -join "`n") }
}

function New-SimulatedTransaction(
    [string]$Root,
    [ValidateSet("old", "new", "tampered")][string]$TargetState,
    [ValidateSet("prepared", "applying", "verified")][string]$JournalState = "applying"
) {
    $transaction = Join-Path $Root ".jekyll-obsidian-update"
    $backupRoot = Join-Path $transaction "backup"
    $stageRoot = Join-Path $transaction "stage"
    [System.IO.Directory]::CreateDirectory($backupRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($stageRoot) | Out-Null
    Write-Lf (Join-Path $transaction "preparing") "format=1`nstate=preparing`n"

    $target = Join-Path $Root "website\snapshot.txt"
    $backup = Join-Path $backupRoot "0"
    $source = Join-Path $stageRoot "new"
    Copy-Item -LiteralPath $target -Destination $backup
    Write-Lf $source "interrupted new state`n"
    $operation = [PSCustomObject]@{
        Target = $target
        Source = $source
        Backup = $backup
        OldExists = $true
        OldHash = Get-Sha256 $backup
        NewExists = $true
        NewHash = Get-Sha256 $source
    }
    if ($TargetState -ceq "tampered") { Write-Lf $target "neither old nor new`n" }
    elseif ($TargetState -ceq "new") { Copy-Item -Force -LiteralPath $source -Destination $target }
    $journal = [PSCustomObject]@{
        Format = 1
        State = $JournalState
        OldVersion = "2026.8.7"
        NewVersion = "2026.8.8"
        Operations = @($operation)
    }
    Write-Lf (Join-Path $transaction "journal") (($journal | ConvertTo-Json -Depth 6) + "`n")
    return $transaction
}

try {
    $adapters = @("cmd", "windows-powershell")
    if ($null -ne (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) { $adapters += "pwsh" }
    foreach ($adapter in $adapters) {
        $root = New-TestHost
        $help = Invoke-Adapter $adapter $root @("--help")
        if ($help.Code -ne 0) { Fail "$adapter --help exited with $($help.Code)" }
        if (-not $help.Output.Contains("website\bin\update.cmd [--check] [--to YYYY.M.D]")) {
            Fail "$adapter --help did not describe the public CLI"
        }

        $invalid = Invoke-Adapter $adapter $root @("--force")
        if ($invalid.Code -ne 1) { Fail "$adapter accepted an unsupported option" }
        if (-not $invalid.Output.Contains("unknown option: --force")) {
            Fail "$adapter did not explain the unsupported option"
        }
    }

    $release = New-ReleaseRepository
    $hostRoot = New-IntegratedHost $release
    $env:JEKYLL_OBSIDIAN_UPDATE_TESTING = "1"
    $env:JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN = $release.Origin
    try {
        $redirectBare = Join-Path ([System.IO.Path]::GetTempPath()) "jekyll obsidian redirected releases $([Guid]::NewGuid().ToString('N')).git"
        [void]$TemporaryRoots.Add($redirectBare)
        [System.IO.Directory]::CreateDirectory($redirectBare) | Out-Null
        [void](Invoke-TestGit $redirectBare @("init", "--quiet", "--bare"))
        $redirectOrigin = ([Uri]$redirectBare).AbsoluteUri
        [void](Invoke-TestGit $hostRoot @("config", "url.$redirectOrigin.insteadOf", $release.Origin))

        $mainConfigPath = Join-Path $hostRoot ".github\jekyll-obsidian.yml"
        $mainConfig = [System.IO.File]::ReadAllText($mainConfigPath).Replace("`r`n", "`n").Replace("`r", "`n")
        Write-Lf $mainConfigPath ("# host-owned prefix`n" + $mainConfig + "host_owned_suffix: true`n")
        $mainConfig = [System.IO.File]::ReadAllText($mainConfigPath).Replace("`n", "`r`n")
        [System.IO.File]::WriteAllText($mainConfigPath, $mainConfig, $Utf8NoBom)
        $configOwnerFingerprint = Get-ConfigOwnerFingerprint $mainConfigPath

        $statusBefore = Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")
        $touchPath = Join-Path $hostRoot "website\snapshot.txt"
        [System.IO.File]::SetLastWriteTimeUtc($touchPath, [DateTime]::UtcNow.AddMinutes(-2))
        $indexPath = Invoke-TestGit $hostRoot @("rev-parse", "--git-path", "index")
        if (-not [System.IO.Path]::IsPathRooted($indexPath)) { $indexPath = Join-Path $hostRoot $indexPath }
        $indexBeforeRead = Get-Sha256 $indexPath
        $adoptionCheck = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.6")
        if ($adoptionCheck.Code -ne 2 -or -not $adoptionCheck.Output.Contains("Provenance can be established for 2026.8.6.")) {
            Fail "--check did not distinguish provenance adoption from an update: $($adoptionCheck.Output)"
        }
        if ((Get-Sha256 $indexPath) -cne $indexBeforeRead) { Fail "--check refreshed or otherwise changed the host Git index" }

        $adoptionRoot = New-IntegratedHost $release
        $adoptionFingerprint = Get-ManagedFingerprint $adoptionRoot
        $adoption = Invoke-Adapter "windows-powershell" $adoptionRoot @("--to", "2026.8.6")
        if ($adoption.Code -ne 0 -or -not $adoption.Output.Contains("Recorded jekyll-obsidian provenance for 2026.8.6.")) {
            Fail "same-version adoption did not record provenance: $($adoption.Output)"
        }
        $adoptionChangedPaths = @($adoption.Output -split "`n" | Where-Object { $_.StartsWith("  ", [StringComparison]::Ordinal) })
        if ($adoptionChangedPaths.Count -ne 1 -or $adoptionChangedPaths[0].Trim() -cne ".github/jekyll-obsidian.lock") {
            Fail "same-version adoption reported changes other than the provenance lock: $($adoption.Output)"
        }
        if ((Get-ManagedFingerprint $adoptionRoot) -cne $adoptionFingerprint) {
            Fail "same-version adoption rewrote website, configuration, or workflow files"
        }
        if (-not (Test-Path -LiteralPath (Join-Path $adoptionRoot ".github\jekyll-obsidian.lock")) -or
            (Test-Path -LiteralPath (Join-Path $adoptionRoot ".jekyll-obsidian-update")) -or
            (Test-Path -LiteralPath (Join-Path $adoptionRoot ".jekyll-obsidian-update.completed"))) {
            Fail "same-version adoption did not limit its write to the provenance lock"
        }
        [void](Invoke-TestGit $adoptionRoot @("add", ".github/jekyll-obsidian.lock"))
        [void](Invoke-TestGit $adoptionRoot @("commit", "--quiet", "-m", "record provenance"))
        [void](Invoke-TestGit $adoptionRoot @("config", "core.autocrlf", "true"))
        $adoptionLockPath = Join-Path $adoptionRoot ".github\jekyll-obsidian.lock"
        Remove-Item -Force -LiteralPath $adoptionLockPath
        [void](Invoke-TestGit $adoptionRoot @("checkout", "--", ".github/jekyll-obsidian.lock"))
        if (-not ([System.IO.File]::ReadAllText($adoptionLockPath).Contains("`r`n"))) {
            Fail "core.autocrlf fixture did not check out the provenance lock with CRLF"
        }
        $crlfLock = Invoke-Adapter "windows-powershell" $adoptionRoot @("--check", "--to", "2026.8.6")
        if ($crlfLock.Code -ne 0 -or -not $crlfLock.Output.Contains("jekyll-obsidian 2026.8.6 is current.")) {
            Fail "a committed CRLF provenance lock could not be read: $($crlfLock.Output)"
        }

        $caseRoot = New-IntegratedHost $release
        [void](Invoke-TestGit $caseRoot @("mv", "website/snapshot.txt", "website/snapshot.rename-tmp"))
        [void](Invoke-TestGit $caseRoot @("mv", "website/snapshot.rename-tmp", "website/Snapshot.txt"))
        [void](Invoke-TestGit $caseRoot @("commit", "--quiet", "-m", "legacy case-only website path"))
        $caseAdoption = Invoke-Adapter "windows-powershell" $caseRoot @("--check", "--to", "2026.8.6")
        if ($caseAdoption.Code -ne 1 -or -not $caseAdoption.Output.Contains("unrecorded website snapshot does not exactly match")) {
            Fail "same-blob legacy website path with different case was accepted for adoption"
        }

        $check = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($check.Code -ne 2) { Fail "--check should report an available update with exit 2, got $($check.Code): $($check.Output)" }
        if (-not $check.Output.Contains("Update available: 2026.8.6 -> 2026.8.7.")) { Fail "--check did not report the available release" }
        if (Test-Path -LiteralPath (Join-Path $hostRoot ".github\jekyll-obsidian.lock")) { Fail "--check wrote a provenance lock" }
        if ((Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")) -cne $statusBefore) { Fail "--check changed the host worktree" }

        $indexBeforeUpdate = Get-Sha256 $indexPath
        $update = Invoke-Adapter "windows-powershell" $hostRoot @()
        if ($update.Code -ne 0) { Fail "update exited with $($update.Code): $($update.Output)" }
        if ((Get-Sha256 $indexPath) -cne $indexBeforeUpdate) { Fail "update changed the host Git index" }
        if (-not $update.Output.Contains("Updated jekyll-obsidian from 2026.8.6 to 2026.8.7.")) { Fail "update did not report the installed release" }
        if (-not $update.Output.Contains("Changed managed paths:") -or -not $update.Output.Contains("website/snapshot.txt") -or
            -not $update.Output.Contains(".github/jekyll-obsidian.lock")) { Fail "update did not list the managed paths that actually changed" }
        if ([System.IO.File]::ReadAllText((Join-Path $hostRoot "website\snapshot.txt")).Trim() -cne "next snapshot") { Fail "update did not install the target snapshot" }
        if ([System.IO.File]::ReadAllText((Join-Path $hostRoot "website\node_modules\cache.txt")).Trim() -cne "preserve ignored cache") { Fail "update discarded a jointly ignored file" }
        if ([System.IO.File]::ReadAllText((Join-Path $hostRoot "website\host-cache\cache.txt")).Trim() -cne "preserve host-root ignored cache") { Fail "update ignored host-root .gitignore semantics" }
        if (-not ([System.IO.File]::ReadAllText((Join-Path $hostRoot ".github\jekyll-obsidian.yml"))).Contains("title: Preserved host title")) { Fail "update rewrote host-owned configuration" }
        if ((Get-ConfigOwnerFingerprint $mainConfigPath) -cne $configOwnerFingerprint) {
            Fail "update changed host-owned configuration bytes or line endings outside the managed block"
        }

        $lock = [System.IO.File]::ReadAllText((Join-Path $hostRoot ".github\jekyll-obsidian.lock"))
        if ($lock -notmatch '(?m)^origin=https://github\.com/wowfun/jekyll-obsidian\.git$') { Fail "lock did not record the canonical origin" }
        if ($lock -notmatch '(?m)^version=2026\.8\.7$') { Fail "lock did not record the installed release" }
        if ($lock -notmatch '(?m)^tag_object=[0-9a-f]+$' -or $lock -notmatch '(?m)^website_tree=[0-9a-f]+$') { Fail "lock omitted immutable Git provenance" }
        $lockBytes = [System.IO.File]::ReadAllBytes((Join-Path $hostRoot ".github\jekyll-obsidian.lock"))
        if ($lockBytes -contains 13 -or ($lockBytes.Length -ge 3 -and $lockBytes[0] -eq 0xef -and $lockBytes[1] -eq 0xbb -and $lockBytes[2] -eq 0xbf)) {
            Fail "lock is not LF-only UTF-8 without BOM"
        }

        [void](Invoke-TestGit $hostRoot @("add", "website", ".github"))
        [void](Invoke-TestGit $hostRoot @("commit", "--quiet", "-m", "accept update"))
        $current = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($current.Code -ne 0 -or -not $current.Output.Contains("jekyll-obsidian 2026.8.7 is current.")) { Fail "committed current release was not idempotent: $($current.Output)" }

        $beforeDowngrade = Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")
        $downgrade = Invoke-Adapter "windows-powershell" $hostRoot @("--to", "2026.8.6")
        if ($downgrade.Code -ne 1 -or -not $downgrade.Output.Contains("downgrade")) { Fail "downgrade was not rejected" }
        if ((Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")) -cne $beforeDowngrade) { Fail "rejected downgrade changed the host" }

        $snapshotPath = Join-Path $hostRoot "website\snapshot.txt"
        $snapshotBytes = [System.IO.File]::ReadAllBytes($snapshotPath)
        [System.IO.File]::AppendAllText($snapshotPath, "dirty")
        $dirtyWebsite = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($dirtyWebsite.Code -ne 1 -or -not $dirtyWebsite.Output.Contains("must be committed and clean")) { Fail "dirty managed website was not rejected" }
        [System.IO.File]::WriteAllBytes($snapshotPath, $snapshotBytes)

        $untrackedPath = Join-Path $hostRoot "website\not-ignored.txt"
        Write-Lf $untrackedPath "untracked managed file`n"
        $untrackedWebsite = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($untrackedWebsite.Code -ne 1) { Fail "non-ignored untracked website state was not rejected" }
        Remove-Item -Force -LiteralPath $untrackedPath

        $workflowPath = Join-Path $hostRoot ".github\workflows\pages.yml"
        $workflowBytes = [System.IO.File]::ReadAllBytes($workflowPath)
        [System.IO.File]::AppendAllText($workflowPath, "# dirty")
        $dirtyWorkflow = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($dirtyWorkflow.Code -ne 1) { Fail "dirty managed workflow was not rejected" }
        [System.IO.File]::WriteAllBytes($workflowPath, $workflowBytes)

        $configPath = Join-Path $hostRoot ".github\jekyll-obsidian.yml"
        $configBytes = [System.IO.File]::ReadAllBytes($configPath)
        [System.IO.File]::AppendAllText($configPath, "host_extra: true`n")
        $hostOwnedConfig = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($hostOwnedConfig.Code -ne 0) { Fail "host-owned configuration outside the managed block was rejected: $($hostOwnedConfig.Output)" }
        [System.IO.File]::WriteAllBytes($configPath, $configBytes)

        $managedConfig = [System.IO.File]::ReadAllText($configPath).Replace("  theme: 'minimal'", "  theme: 'docs'")
        Write-Lf $configPath $managedConfig
        $unstagedManagedConfig = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($unstagedManagedConfig.Code -ne 1 -or -not $unstagedManagedConfig.Output.Contains("managed source/theme configuration block must match HEAD")) {
            Fail "unstaged managed configuration drift was not rejected"
        }
        [System.IO.File]::WriteAllBytes($configPath, $configBytes)

        Write-Lf $configPath $managedConfig
        [void](Invoke-TestGit $hostRoot @("add", ".github/jekyll-obsidian.yml"))
        $stagedManagedConfig = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($stagedManagedConfig.Code -ne 1 -or -not $stagedManagedConfig.Output.Contains("managed source/theme configuration block must match HEAD")) {
            Fail "staged managed configuration drift was not rejected"
        }
        [System.IO.File]::WriteAllBytes($configPath, $configBytes)
        [void](Invoke-TestGit $hostRoot @("add", ".github/jekyll-obsidian.yml"))

        foreach ($adapter in @($adapters | Where-Object { $_ -cne "windows-powershell" })) {
            $parityRoot = New-IntegratedHost $release
            $parityCheck = Invoke-Adapter $adapter $parityRoot @("--check")
            if ($parityCheck.Code -ne 2 -or -not $parityCheck.Output.Contains("Update available: 2026.8.6 -> 2026.8.7.")) {
                Fail "$adapter did not preserve the update-available exit contract: $($parityCheck.Output)"
            }
            $parityUpdate = Invoke-Adapter $adapter $parityRoot @()
            if ($parityUpdate.Code -ne 0) { Fail "$adapter could not install the same release: $($parityUpdate.Output)" }
            $parityLock = [System.IO.File]::ReadAllText((Join-Path $parityRoot ".github\jekyll-obsidian.lock"))
            if ($parityLock -cne $lock) { Fail "$adapter produced different provenance from Windows PowerShell" }
        }

        $rollbackRoot = New-IntegratedHost $release
        $rollbackBefore = Invoke-TestGit $rollbackRoot @("status", "--short", "--untracked-files=all")
        $env:JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT = "fail_after_first_file"
        try { $rollbackResult = Invoke-Adapter "windows-powershell" $rollbackRoot @() }
        finally { Remove-Item Env:\JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT -ErrorAction SilentlyContinue }
        if ($rollbackResult.Code -ne 1 -or -not $rollbackResult.Output.Contains("injected transaction failure after the first changed managed file")) {
            Fail "real Apply failure injection did not fail at the requested boundary"
        }
        if ([System.IO.File]::ReadAllText((Join-Path $rollbackRoot "website\snapshot.txt")).Trim() -cne "current snapshot" -or
            (Test-Path -LiteralPath (Join-Path $rollbackRoot ".github\jekyll-obsidian.lock")) -or
            (Test-Path -LiteralPath (Join-Path $rollbackRoot ".jekyll-obsidian-update")) -or
            (Test-Path -LiteralPath (Join-Path $rollbackRoot ".jekyll-obsidian-update.completed"))) {
            Fail "immediate rollback did not restore the old managed snapshot and remove transaction state"
        }
        if ((Invoke-TestGit $rollbackRoot @("status", "--short", "--untracked-files=all")) -cne $rollbackBefore) {
            Fail "immediate rollback changed the host worktree or index"
        }

        $crashRecoveryRoot = New-IntegratedHost $release
        $env:JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT = "crash_after_all_renames"
        try { $crashResult = Invoke-Adapter "windows-powershell" $crashRecoveryRoot @() }
        finally { Remove-Item Env:\JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT -ErrorAction SilentlyContinue }
        $crashTransaction = Join-Path $crashRecoveryRoot ".jekyll-obsidian-update"
        if ($crashResult.Code -eq 0 -or -not (Test-Path -LiteralPath (Join-Path $crashTransaction "journal") -PathType Leaf) -or
            [System.IO.File]::ReadAllText((Join-Path $crashRecoveryRoot "website\snapshot.txt")).Trim() -cne "next snapshot") {
            Fail "crash after all managed renames did not retain an applying journal and all-new snapshot"
        }
        $crashRecovery = Invoke-Adapter "windows-powershell" $crashRecoveryRoot @()
        if ($crashRecovery.Code -ne 0 -or -not $crashRecovery.Output.Contains("Recovered completed jekyll-obsidian update 2026.8.6 -> 2026.8.7.") -or
            (Test-Path -LiteralPath $crashTransaction)) {
            Fail "all-new applying recovery did not run post-install validation and finalize: $($crashRecovery.Output)"
        }

        $invalidRecoveryRoot = New-IntegratedHost $release
        $env:JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT = "crash_after_all_renames"
        try { $invalidCrash = Invoke-Adapter "windows-powershell" $invalidRecoveryRoot @() }
        finally { Remove-Item Env:\JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT -ErrorAction SilentlyContinue }
        $invalidTransaction = Join-Path $invalidRecoveryRoot ".jekyll-obsidian-update"
        if ($invalidCrash.Code -eq 0 -or -not (Test-Path -LiteralPath (Join-Path $invalidTransaction "journal") -PathType Leaf)) {
            Fail "invalid post-install recovery fixture did not retain its applying transaction"
        }
        $invalidIntegrate = Join-Path $invalidRecoveryRoot "website\bin\integrate.ps1"
        Write-Lf $invalidIntegrate "[Console]::Error.WriteLine('recovered integration failure')`nexit 1`n"
        $invalidJournalPath = Join-Path $invalidTransaction "journal"
        $invalidJournal = [System.IO.File]::ReadAllText($invalidJournalPath) | ConvertFrom-Json
        $invalidIntegrateOperation = @($invalidJournal.Operations | Where-Object {
            [string]$_.Target -ieq $invalidIntegrate
        })
        if ($invalidIntegrateOperation.Count -ne 1) { Fail "could not find installed integrate operation in crash journal" }
        $invalidIntegrateOperation[0].NewHash = Get-Sha256 $invalidIntegrate
        Write-Lf $invalidJournalPath (($invalidJournal | ConvertTo-Json -Depth 6) + "`n")
        $invalidEvidence = Get-TransactionEvidenceFingerprint $invalidTransaction
        $invalidRecovery = Invoke-Adapter "windows-powershell" $invalidRecoveryRoot @()
        if ($invalidRecovery.Code -ne 1 -or -not $invalidRecovery.Output.Contains("post-install validation") -or
            -not (Test-Path -LiteralPath $invalidJournalPath -PathType Leaf) -or
            (Get-TransactionEvidenceFingerprint $invalidTransaction) -cne $invalidEvidence) {
            Fail "failed all-new post-install validation did not preserve its journal and backups"
        }

        $concurrencyRoot = New-IntegratedHost $release
        $concurrencyScript = Join-Path $concurrencyRoot "website\bin\update.ps1"
        $env:JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT = "pause_after_transaction_claim"
        $winnerJob = Start-Job -ScriptBlock {
            param($Root, $Script)
            Set-Location $Root
            $raw = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Script 2>&1
            [PSCustomObject]@{ Code = $LASTEXITCODE; Output = ($raw -join "`n") }
        } -ArgumentList $concurrencyRoot, $concurrencyScript
        try {
            $concurrencyTransaction = Join-Path $concurrencyRoot ".jekyll-obsidian-update"
            $journalPath = Join-Path $concurrencyTransaction "journal"
            $pausePath = Join-Path $concurrencyTransaction "test-paused"
            for ($attempt = 0; $attempt -lt 600 -and -not (Test-Path -LiteralPath $pausePath -PathType Leaf); $attempt++) {
                if (@("Completed", "Failed", "Stopped") -contains $winnerJob.State) {
                    $earlyWinner = @(Receive-Job -Job $winnerJob)[-1]
                    Fail "concurrent winner exited before the applying transaction pause: $($earlyWinner.Output)"
                }
                Start-Sleep -Milliseconds 50
            }
            if (-not (Test-Path -LiteralPath $pausePath -PathType Leaf)) { Fail "concurrent winner did not reach the applying transaction pause" }
            $winnerEvidence = Get-TransactionEvidenceFingerprint $concurrencyTransaction
            if ([string]::IsNullOrEmpty($winnerEvidence)) { Fail "concurrent winner did not prepare journal and backups" }
            $loser = Invoke-Adapter "windows-powershell" $concurrencyRoot @()
            if ($loser.Code -ne 1 -or -not $loser.Output.Contains("another jekyll-obsidian updater is already running")) {
                Fail "concurrent loser did not fail at the lifecycle mutex: $($loser.Output)"
            }
            if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf) -or
                (Get-TransactionEvidenceFingerprint $concurrencyTransaction) -cne $winnerEvidence) {
                Fail "concurrent loser changed or removed the winner journal or backups"
            }
            Write-Lf (Join-Path $concurrencyTransaction "test-continue") "continue`n"
            $completedJob = Wait-Job -Job $winnerJob -Timeout 30
            if ($null -eq $completedJob) { Fail "concurrent winner did not finish" }
            $winner = @(Receive-Job -Job $winnerJob)[-1]
            if ($winner.Code -ne 0 -or -not $winner.Output.Contains("Updated jekyll-obsidian from 2026.8.6 to 2026.8.7.")) {
                Fail "concurrent winner could not complete after rejecting the loser: $($winner.Output)"
            }
            if ((Test-Path -LiteralPath $concurrencyTransaction) -or
                [System.IO.File]::ReadAllText((Join-Path $concurrencyRoot "website\snapshot.txt")).Trim() -cne "next snapshot") {
                Fail "concurrent winner did not finalize the target snapshot"
            }
        }
        finally {
            Remove-Item Env:\JEKYLL_OBSIDIAN_UPDATE_TEST_FAIL_AT -ErrorAction SilentlyContinue
            if ($null -ne $winnerJob) {
                if ($winnerJob.State -eq "Running") { Stop-Job -Job $winnerJob }
                Remove-Job -Force -Job $winnerJob
            }
        }

        $pending = New-SimulatedTransaction $hostRoot "old"
        $pendingCheck = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($pendingCheck.Code -ne 1 -or -not $pendingCheck.Output.Contains("recovery_required") -or -not (Test-Path -LiteralPath $pending)) {
            Fail "--check changed or ignored a pending transaction"
        }
        $recovered = Invoke-Adapter "windows-powershell" $hostRoot @()
        if ($recovered.Code -ne 0 -or -not $recovered.Output.Contains("Recovered rolled-back jekyll-obsidian update 2026.8.7 -> 2026.8.8.")) {
            Fail "a digest-identifiable interrupted transaction was not recovered: $($recovered.Output)"
        }
        if ([System.IO.File]::ReadAllText($snapshotPath).Trim() -cne "next snapshot" -or (Test-Path -LiteralPath $pending)) {
            Fail "transaction recovery did not restore the old managed state"
        }

        $completed = New-SimulatedTransaction $hostRoot "new" "verified"
        $completedResult = Invoke-Adapter "windows-powershell" $hostRoot @()
        if ($completedResult.Code -ne 0 -or -not $completedResult.Output.Contains("Recovered completed jekyll-obsidian update 2026.8.7 -> 2026.8.8.")) {
            Fail "a complete new interrupted state was not retained: $($completedResult.Output)"
        }
        if (-not $completedResult.Output.Contains("website/snapshot.txt")) { Fail "completed recovery did not list its changed managed path" }
        if ([System.IO.File]::ReadAllText($snapshotPath).Trim() -cne "interrupted new state" -or (Test-Path -LiteralPath $completed)) {
            Fail "completed recovery did not retain the new state or remove its journal"
        }
        [System.IO.File]::WriteAllBytes($snapshotPath, $snapshotBytes)

        $partialCompleted = New-SimulatedTransaction $hostRoot "new"
        $partialCompletedTombstone = "$partialCompleted.completed"
        [System.IO.Directory]::Move($partialCompleted, $partialCompletedTombstone)
        Remove-Item -Force -LiteralPath (Join-Path $partialCompletedTombstone "journal")
        Remove-Item -Force -Recurse -LiteralPath (Join-Path $partialCompletedTombstone "backup")
        $partialCompletedResult = Invoke-Adapter "windows-powershell" $hostRoot @()
        if ($partialCompletedResult.Code -ne 0 -or -not $partialCompletedResult.Output.Contains("Finalized a previously verified jekyll-obsidian update.")) {
            Fail "partially cleaned verified tombstone was not treated as committed: $($partialCompletedResult.Output)"
        }
        if ((Test-Path -LiteralPath $partialCompletedTombstone) -or
            [System.IO.File]::ReadAllText($snapshotPath).Trim() -cne "interrupted new state") {
            Fail "verified tombstone recovery discarded the committed target state"
        }
        [System.IO.File]::WriteAllBytes($snapshotPath, $snapshotBytes)

        $absentShapeTransaction = Join-Path $hostRoot ".jekyll-obsidian-update"
        [System.IO.Directory]::CreateDirectory((Join-Path $absentShapeTransaction "backup")) | Out-Null
        [System.IO.Directory]::CreateDirectory((Join-Path $absentShapeTransaction "stage")) | Out-Null
        Write-Lf (Join-Path $absentShapeTransaction "preparing") "format=1`nstate=preparing`n"
        $absentShapeTarget = Join-Path $hostRoot "website\absent-shape"
        [System.IO.Directory]::CreateDirectory($absentShapeTarget) | Out-Null
        $absentShapeOperation = [PSCustomObject]@{
            Target = $absentShapeTarget
            Source = ""
            Backup = Join-Path $absentShapeTransaction "backup\0"
            OldExists = $false
            OldHash = $null
            NewExists = $false
            NewHash = $null
        }
        $absentShapeJournal = [PSCustomObject]@{
            Format = 1
            State = "applying"
            OldVersion = "2026.8.7"
            NewVersion = "2026.8.8"
            Operations = @($absentShapeOperation)
        }
        Write-Lf (Join-Path $absentShapeTransaction "journal") (($absentShapeJournal | ConvertTo-Json -Depth 6) + "`n")
        $absentShapeResult = Invoke-Adapter "windows-powershell" $hostRoot @()
        if ($absentShapeResult.Code -ne 1 -or -not $absentShapeResult.Output.Contains("recovery_required") -or
            -not (Test-Path -LiteralPath (Join-Path $absentShapeTransaction "journal"))) {
            Fail "directory at an expected-absent recovery target was accepted or discarded"
        }
        Remove-Item -Force -Recurse -LiteralPath $absentShapeTarget
        Remove-Item -Force -Recurse -LiteralPath $absentShapeTransaction

        $ambiguous = New-SimulatedTransaction $hostRoot "tampered"
        $ambiguousResult = Invoke-Adapter "windows-powershell" $hostRoot @()
        if ($ambiguousResult.Code -ne 1 -or -not $ambiguousResult.Output.Contains("recovery_required")) { Fail "ambiguous recovery was not rejected" }
        if (-not (Test-Path -LiteralPath (Join-Path $ambiguous "journal")) -or -not (Test-Path -LiteralPath (Join-Path $ambiguous "backup\0"))) {
            Fail "ambiguous recovery discarded its journal or backup"
        }
        Copy-Item -Force -LiteralPath (Join-Path $ambiguous "backup\0") -Destination $snapshotPath
        Remove-Item -Force -Recurse -LiteralPath $ambiguous

        $junctionTarget = Join-Path ([System.IO.Path]::GetTempPath()) "jekyll obsidian transaction target $([Guid]::NewGuid().ToString('N'))"
        [void]$TemporaryRoots.Add($junctionTarget)
        [System.IO.Directory]::CreateDirectory($junctionTarget) | Out-Null
        Write-Lf (Join-Path $junctionTarget "must-survive.txt") "external junction target`n"
        $junctionPath = Join-Path $hostRoot ".jekyll-obsidian-update"
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & cmd.exe /d /c mklink /J $junctionPath $junctionTarget *> $null
            $junctionCode = $LASTEXITCODE
            $global:LASTEXITCODE = 0
        }
        finally { $ErrorActionPreference = $previousErrorAction }
        if ($junctionCode -eq 0) {
            $junctionResult = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
            if ($junctionResult.Code -ne 1 -or -not $junctionResult.Output.Contains("reparse point")) { Fail "a transaction junction was not rejected" }
            if (-not (Test-Path -LiteralPath (Join-Path $junctionTarget "must-survive.txt"))) { Fail "rejected transaction junction damaged its target" }
            [System.IO.Directory]::Delete($junctionPath)
        }

        $reparseTargetRoot = Join-Path ([System.IO.Path]::GetTempPath()) "jekyll obsidian recovery target $([Guid]::NewGuid().ToString('N'))"
        [void]$TemporaryRoots.Add($reparseTargetRoot)
        [System.IO.Directory]::CreateDirectory($reparseTargetRoot) | Out-Null
        Write-Lf (Join-Path $reparseTargetRoot "value.txt") "external old state`n"
        $reparsePath = Join-Path $hostRoot "website\recovery-link"
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & cmd.exe /d /c mklink /J $reparsePath $reparseTargetRoot *> $null
            $reparseCode = $LASTEXITCODE
            $global:LASTEXITCODE = 0
        }
        finally { $ErrorActionPreference = $previousErrorAction }
        if ($reparseCode -eq 0) {
            $reparseTransaction = Join-Path $hostRoot ".jekyll-obsidian-update"
            [System.IO.Directory]::CreateDirectory((Join-Path $reparseTransaction "backup")) | Out-Null
            [System.IO.Directory]::CreateDirectory((Join-Path $reparseTransaction "stage")) | Out-Null
            Write-Lf (Join-Path $reparseTransaction "preparing") "format=1`nstate=preparing`n"
            $reparseTarget = Join-Path $reparsePath "value.txt"
            $reparseBackup = Join-Path $reparseTransaction "backup\0"
            $reparseSource = Join-Path $reparseTransaction "stage\new"
            Copy-Item -LiteralPath $reparseTarget -Destination $reparseBackup
            Write-Lf $reparseSource "external new state`n"
            $reparseOperation = [PSCustomObject]@{
                Target = $reparseTarget
                Source = $reparseSource
                Backup = $reparseBackup
                OldExists = $true
                OldHash = Get-Sha256 $reparseBackup
                NewExists = $true
                NewHash = Get-Sha256 $reparseSource
            }
            $reparseJournal = [PSCustomObject]@{
                Format = 1
                State = "applying"
                OldVersion = "2026.8.7"
                NewVersion = "2026.8.8"
                Operations = @($reparseOperation)
            }
            Write-Lf (Join-Path $reparseTransaction "journal") (($reparseJournal | ConvertTo-Json -Depth 6) + "`n")
            $reparseRecovery = Invoke-Adapter "windows-powershell" $hostRoot @()
            if ($reparseRecovery.Code -ne 1 -or -not $reparseRecovery.Output.Contains("reparse point")) { Fail "recovery followed a managed target junction" }
            if (-not (Test-Path -LiteralPath (Join-Path $reparseTransaction "journal")) -or
                [System.IO.File]::ReadAllText((Join-Path $reparseTargetRoot "value.txt")).Trim() -cne "external old state") {
                Fail "reparse recovery discarded evidence or changed the external target"
            }
            [System.IO.Directory]::Delete($reparsePath)
            Remove-Item -Force -Recurse -LiteralPath $reparseTransaction
        }

        $emptyBare = Join-Path ([System.IO.Path]::GetTempPath()) "jekyll obsidian empty releases $([Guid]::NewGuid().ToString('N')).git"
        [void]$TemporaryRoots.Add($emptyBare)
        [System.IO.Directory]::CreateDirectory($emptyBare) | Out-Null
        [void](Invoke-TestGit $emptyBare @("init", "--quiet", "--bare"))
        $env:JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN = ([Uri]$emptyBare).AbsoluteUri
        $noRelease = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($noRelease.Code -ne 1 -or -not $noRelease.Output.Contains("no stable annotated CalVer releases")) { Fail "an origin without releases was not rejected" }
        $env:JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN = $release.Origin

        [void](Invoke-TestGit $release.Work @("checkout", "--quiet", $release.Branch))
        Write-ReleaseSite $release.Work "2026.8.8" "candidate integration failure"
        Write-Lf (Join-Path $release.Work "website\bin\integrate.ps1") "[Console]::Error.WriteLine('fixture integration failure')`nexit 1`n"
        [void](Invoke-TestGit $release.Work @("add", "website"))
        [void](Invoke-TestGit $release.Work @("commit", "--quiet", "-m", "candidate integration fails"))
        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.8.8", "-m", "v2026.8.8 integrate failure"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", $release.Bare, "refs/tags/v2026.8.8"))
        $beforeIntegrateFailure = Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")
        $integrateFailure = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.8")
        if ($integrateFailure.Code -ne 1 -or -not $integrateFailure.Output.Contains("candidate integration failed")) { Fail "candidate integrate failure was not rejected" }
        if ((Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")) -cne $beforeIntegrateFailure -or
            (Test-Path -LiteralPath (Join-Path $hostRoot ".jekyll-obsidian-update"))) { Fail "candidate integrate failure wrote to the host" }

        Write-ReleaseSite $release.Work "2026.8.8" "target tracked conflict"
        Write-Lf (Join-Path $release.Work "website\node_modules\cache.txt") "target owns ignored host path`n"
        [void](Invoke-TestGit $release.Work @("add", "website"))
        [void](Invoke-TestGit $release.Work @("add", "-f", "website/node_modules/cache.txt"))
        [void](Invoke-TestGit $release.Work @("commit", "--quiet", "-m", "target conflicts with ignored host file"))
        [void](Invoke-TestGit $release.Work @("tag", "-d", "v2026.8.8"))
        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.8.8", "-m", "v2026.8.8 conflict"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", "--force", $release.Bare, "refs/tags/v2026.8.8"))
        $beforeConflict = Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")
        $trackedConflict = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.8")
        if ($trackedConflict.Code -ne 1 -or -not $trackedConflict.Output.Contains("target release conflicts with local ignored or untracked state")) {
            Fail "target tracked conflict was not rejected during --check"
        }
        if ((Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")) -cne $beforeConflict -or
            (Test-Path -LiteralPath (Join-Path $hostRoot ".jekyll-obsidian-update"))) { Fail "target conflict check wrote to the host" }

        Remove-Item -Force -Recurse -LiteralPath (Join-Path $release.Work "website\node_modules")
        Write-ReleaseSite $release.Work "2026.8.8" "target path has a file ancestor"
        Write-Lf (Join-Path $release.Work "website\cache\child.txt") "target child`n"
        [void](Invoke-TestGit $release.Work @("add", "website"))
        [void](Invoke-TestGit $release.Work @("commit", "--quiet", "-m", "release adds a child below a local file"))
        [void](Invoke-TestGit $release.Work @("tag", "-d", "v2026.8.8"))
        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.8.8", "-m", "v2026.8.8 ancestor"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", "--force", $release.Bare, "refs/tags/v2026.8.8"))
        $hostExcludePath = Join-Path $hostRoot ".git\info\exclude"
        $hostExcludeBytes = [System.IO.File]::ReadAllBytes($hostExcludePath)
        try {
            [System.IO.File]::AppendAllText($hostExcludePath, "`n/website/cache`n", $Utf8NoBom)
            Write-Lf (Join-Path $hostRoot "website\cache") "ignored local file ancestor`n"
            $ancestorConflict = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.8")
            if ($ancestorConflict.Code -ne 1 -or -not $ancestorConflict.Output.Contains("managed path ancestor must be a directory")) {
                Fail "a target path below an existing ordinary file passed --check: $($ancestorConflict.Output)"
            }
            if (Test-Path -LiteralPath (Join-Path $hostRoot ".jekyll-obsidian-update")) { Fail "ancestor conflict check wrote a host transaction" }
        }
        finally {
            Remove-Item -Force -LiteralPath (Join-Path $hostRoot "website\cache") -ErrorAction SilentlyContinue
            [System.IO.File]::WriteAllBytes($hostExcludePath, $hostExcludeBytes)
        }

        Write-ReleaseSite $release.Work "2026.8.8" "missing required component"
        Remove-Item -Force -LiteralPath (Join-Path $release.Work "website\scripts\example-config.yml")
        [void](Invoke-TestGit $release.Work @("add", "website"))
        [void](Invoke-TestGit $release.Work @("commit", "--quiet", "-m", "release misses required component"))
        [void](Invoke-TestGit $release.Work @("tag", "-d", "v2026.8.8"))
        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.8.8", "-m", "v2026.8.8 incomplete"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", "--force", $release.Bare, "refs/tags/v2026.8.8"))
        $beforeMissingComponent = Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")
        $missingComponent = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.8")
        if ($missingComponent.Code -ne 1 -or -not $missingComponent.Output.Contains("missing required updater component website/scripts/example-config.yml")) {
            Fail "candidate missing a required component was accepted"
        }
        if ((Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")) -cne $beforeMissingComponent) { Fail "missing candidate component changed the host" }

        Write-ReleaseSite $release.Work "2026.8.8" "missing setup command"
        Remove-Item -Force -LiteralPath (Join-Path $release.Work "website\bin\setup")
        [void](Invoke-TestGit $release.Work @("add", "website"))
        [void](Invoke-TestGit $release.Work @("commit", "--quiet", "-m", "release misses setup"))
        [void](Invoke-TestGit $release.Work @("tag", "-d", "v2026.8.8"))
        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.8.8", "-m", "v2026.8.8 no setup"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", "--force", $release.Bare, "refs/tags/v2026.8.8"))
        $missingSetup = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.8")
        if ($missingSetup.Code -ne 1 -or -not $missingSetup.Output.Contains("missing required updater component website/bin/setup")) {
            Fail "candidate without the setup command was accepted"
        }

        Write-ReleaseSite $release.Work "2026.8.8" "non-executable POSIX updater"
        [void](Invoke-TestGit $release.Work @("add", "website"))
        [void](Invoke-TestGit $release.Work @("update-index", "--chmod=-x", "website/bin/update"))
        [void](Invoke-TestGit $release.Work @("commit", "--quiet", "-m", "release has non-executable updater"))
        [void](Invoke-TestGit $release.Work @("tag", "-d", "v2026.8.8"))
        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.8.8", "-m", "v2026.8.8 non-executable"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", "--force", $release.Bare, "refs/tags/v2026.8.8"))
        $nonExecutable = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.8")
        if ($nonExecutable.Code -ne 1 -or -not $nonExecutable.Output.Contains("does not contain executable website/bin/update")) {
            Fail "candidate with a non-executable POSIX updater was accepted"
        }

        Write-ReleaseSite $release.Work "2026.8.8" "drops a website ignore rule"
        Write-Lf (Join-Path $release.Work "website\.gitignore") "/.env`n"
        [void](Invoke-TestGit $release.Work @("add", "website"))
        [void](Invoke-TestGit $release.Work @("commit", "--quiet", "-m", "release drops ignored state rule"))
        [void](Invoke-TestGit $release.Work @("tag", "-d", "v2026.8.8"))
        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.8.8", "-m", "v2026.8.8 ignores"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", "--force", $release.Bare, "refs/tags/v2026.8.8"))
        $droppedIgnore = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.8")
        if ($droppedIgnore.Code -ne 1 -or -not $droppedIgnore.Output.Contains("ignored local state would no longer be ignored")) {
            Fail "target website ignore rules were not evaluated in the host root context"
        }

        Write-ReleaseSite $release.Work "2026.8.8" "invalid version contract"
        $badPackage = Join-Path $release.Work "website\package.json"
        Write-Lf $badPackage ([System.IO.File]::ReadAllText($badPackage).Replace('"2026.8.8"', '"2026.8.7"'))
        [void](Invoke-TestGit $release.Work @("add", "website"))
        [void](Invoke-TestGit $release.Work @("commit", "--quiet", "-m", "invalid version release"))
        [void](Invoke-TestGit $release.Work @("tag", "-d", "v2026.8.8"))
        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.8.8", "-m", "v2026.8.8"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", "--force", $release.Bare, "refs/tags/v2026.8.8"))
        $beforeInvalidRelease = Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")
        $invalidRelease = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.8")
        if ($invalidRelease.Code -ne 1 -or -not $invalidRelease.Output.Contains("package.json version does not match")) { Fail "candidate version mismatch was not rejected" }
        if ((Invoke-TestGit $hostRoot @("status", "--short", "--untracked-files=all")) -cne $beforeInvalidRelease) { Fail "invalid candidate changed the host" }

        Write-ReleaseSite $release.Work "2026.8.9" "malformed tag name"
        [void](Invoke-TestGit $release.Work @("add", "website"))
        [void](Invoke-TestGit $release.Work @("commit", "--quiet", "-m", "valid v9 release content"))
        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.8.9", "-m", "v2026.8.9"))
        $tagPayload = Invoke-TestGit $release.Work @("cat-file", "-p", "v2026.8.9")
        $wrongNamePayload = $tagPayload.Replace("tag v2026.8.9", "tag v2099.1.1") + "`n"
        Push-Location $release.Work
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $wrongTagOutput = $wrongNamePayload | & git.exe mktag 2>&1
            $wrongTagCode = $LASTEXITCODE
            $global:LASTEXITCODE = 0
        }
        finally {
            $ErrorActionPreference = $previousErrorAction
            Pop-Location
        }
        if ($wrongTagCode -ne 0) { Fail "could not construct malformed annotated tag fixture: $($wrongTagOutput -join "`n")" }
        $wrongTagObject = ($wrongTagOutput -join "`n").Trim()
        [void](Invoke-TestGit $release.Work @("update-ref", "refs/tags/v2026.8.9", $wrongTagObject))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", $release.Bare, "refs/tags/v2026.8.9"))
        $wrongNameTag = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.9")
        if ($wrongNameTag.Code -ne 1 -or -not $wrongNameTag.Output.Contains("tag object does not name v2026.8.9")) {
            Fail "an annotated tag whose internal name differs from its ref was accepted"
        }

        $v7Commit = Invoke-TestGit $release.Work @("rev-list", "-n", "1", "v2026.8.7")
        [void](Invoke-TestGit $release.Work @("tag", "-d", "v2026.8.7"))
        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.8.7", $v7Commit, "-m", "moved v2026.8.7"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", "--force", $release.Bare, "refs/tags/v2026.8.7"))
        $movedTag = Invoke-Adapter "windows-powershell" $hostRoot @("--check", "--to", "2026.8.7")
        if ($movedTag.Code -ne 1 -or -not $movedTag.Output.Contains("installed provenance does not match")) { Fail "a moved release tag was not rejected" }

        [void](Invoke-TestGit $release.Work @("tag", "v2026.8.10"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", $release.Bare, "refs/tags/v2026.8.10"))
        $lightweightRelease = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($lightweightRelease.Code -ne 1 -or -not $lightweightRelease.Output.Contains("v2026.8.10 is not an annotated tag")) {
            Fail "a lightweight release-shaped tag did not invalidate the release source"
        }
        [void](Invoke-TestGit $release.Work @("push", "--quiet", $release.Bare, ":refs/tags/v2026.8.10"))
        [void](Invoke-TestGit $release.Work @("tag", "-d", "v2026.8.10"))

        [void](Invoke-TestGit $release.Work @("tag", "-a", "v2026.02.10", "-m", "invalid padded CalVer"))
        [void](Invoke-TestGit $release.Work @("push", "--quiet", $release.Bare, "refs/tags/v2026.02.10"))
        $invalidCalendarTag = Invoke-Adapter "windows-powershell" $hostRoot @("--check")
        if ($invalidCalendarTag.Code -ne 1 -or -not $invalidCalendarTag.Output.Contains("remote tag v2026.02.10 must be a calendar version")) {
            Fail "an invalid calendar-shaped tag was silently ignored"
        }
    }
    finally {
        Remove-Item Env:\JEKYLL_OBSIDIAN_UPDATE_TESTING -ErrorAction SilentlyContinue
        Remove-Item Env:\JEKYLL_OBSIDIAN_UPDATE_TEST_ORIGIN -ErrorAction SilentlyContinue
    }

    Write-Output "Windows update contract passed."
}
finally {
    foreach ($root in $TemporaryRoots) {
        if (Test-Path -LiteralPath $root) { Remove-Item -Force -Recurse -LiteralPath $root }
    }
}
