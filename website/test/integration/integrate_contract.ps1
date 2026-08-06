$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$TestDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$SiteDir = [System.IO.Directory]::GetParent([System.IO.Directory]::GetParent($TestDir).FullName).FullName
$TemporaryRoots = New-Object System.Collections.Generic.List[string]
$TemporaryDirectoryLinks = New-Object System.Collections.Generic.List[string]

function Fail([string]$Message) { throw "Windows integration contract failed: $Message" }

function Write-Lf([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n").Replace("`r", "`n"), $Utf8NoBom)
}

function Write-Crlf([string]$Path, [string]$Content) {
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText($Path, $normalized, $Utf8NoBom)
}

function New-Host {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) "jekyll obsidian integrate $([Guid]::NewGuid().ToString('N'))"
    [void]$TemporaryRoots.Add($root)
    [System.IO.Directory]::CreateDirectory((Join-Path $root "website\bin")) | Out-Null
    [System.IO.Directory]::CreateDirectory((Join-Path $root "website\scripts\templates")) | Out-Null
    [System.IO.Directory]::CreateDirectory((Join-Path $root "docs")) | Out-Null
    Copy-Item -LiteralPath (Join-Path $SiteDir "bin\integrate.ps1") -Destination (Join-Path $root "website\bin\integrate.ps1")
    Copy-Item -LiteralPath (Join-Path $SiteDir "bin\integrate.cmd") -Destination (Join-Path $root "website\bin\integrate.cmd")
    Copy-Item -LiteralPath (Join-Path $SiteDir "scripts\templates\host-config.yml") -Destination (Join-Path $root "website\scripts\templates\host-config.yml")
    Copy-Item -LiteralPath (Join-Path $SiteDir "scripts\templates\pages.yml") -Destination (Join-Path $root "website\scripts\templates\pages.yml")
    Write-Lf (Join-Path $root "docs\Start.md") "---`npublish: true`n---`n# Start`n"
    return $root
}

function Invoke-Adapter([string]$Adapter, [string]$Root, [string[]]$Arguments, [bool]$ShouldSucceed = $true) {
    $script = Join-Path $Root "website\bin\integrate.ps1"
    switch ($Adapter) {
        "cmd" { & (Join-Path $Root "website\bin\integrate.cmd") @Arguments *> $null }
        "windows-powershell" { & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script @Arguments *> $null }
        "pwsh" { & pwsh.exe -NoLogo -NoProfile -File $script @Arguments *> $null }
        default { Fail "unknown adapter $Adapter" }
    }
    $code = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    if ($ShouldSucceed -and $code -ne 0) { Fail "$Adapter exited with $code" }
    if (-not $ShouldSucceed -and $code -eq 0) { Fail "$Adapter unexpectedly succeeded" }
    return $code
}

function Assert-BytesEqual([string]$First, [string]$Second, [string]$Label) {
    $left = [System.IO.File]::ReadAllBytes($First)
    $right = [System.IO.File]::ReadAllBytes($Second)
    if ($left.Length -ne $right.Length) { Fail "$Label differs in length" }
    for ($index = 0; $index -lt $left.Length; $index++) {
        if ($left[$index] -ne $right[$index]) { Fail "$Label differs at byte $index" }
    }
}

function Assert-LfWithoutBom([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) { Fail "$Path contains a BOM" }
    if ($bytes -contains 13) { Fail "$Path contains CRLF line endings" }
}

try {
    $roots = @{}
    foreach ($adapter in @("cmd", "windows-powershell", "pwsh")) {
        $root = New-Host
        $roots[$adapter] = $root
        [void](Invoke-Adapter $adapter $root @())
        [void](Invoke-Adapter $adapter $root @("--check"))
        $defaultConfig = [System.IO.File]::ReadAllText((Join-Path $root ".github\jekyll-obsidian.yml"))
        if (-not $defaultConfig.Contains("  theme: 'minimal'")) { Fail "$adapter did not generate the Minimal default theme" }
        if (-not $defaultConfig.Contains("    publish_by_default: []")) { Fail "$adapter did not preserve explicit publication defaults" }
        Assert-LfWithoutBom (Join-Path $root ".github\jekyll-obsidian.yml")
        Assert-LfWithoutBom (Join-Path $root ".github\workflows\pages.yml")

        $configBefore = [System.IO.File]::ReadAllBytes((Join-Path $root ".github\jekyll-obsidian.yml"))
        $workflowBefore = [System.IO.File]::ReadAllBytes((Join-Path $root ".github\workflows\pages.yml"))
        [void](Invoke-Adapter $adapter $root @())
        $configAfter = [System.IO.File]::ReadAllBytes((Join-Path $root ".github\jekyll-obsidian.yml"))
        $workflowAfter = [System.IO.File]::ReadAllBytes((Join-Path $root ".github\workflows\pages.yml"))
        if ([Convert]::ToBase64String($configBefore) -ne [Convert]::ToBase64String($configAfter)) { Fail "$adapter host configuration is not idempotent" }
        if ([Convert]::ToBase64String($workflowBefore) -ne [Convert]::ToBase64String($workflowAfter)) { Fail "$adapter workflow is not idempotent" }
    }

    foreach ($adapter in @("windows-powershell", "pwsh")) {
        Assert-BytesEqual (Join-Path $roots["cmd"] ".github\jekyll-obsidian.yml") (Join-Path $roots[$adapter] ".github\jekyll-obsidian.yml") "$adapter host configuration"
        Assert-BytesEqual (Join-Path $roots["cmd"] ".github\workflows\pages.yml") (Join-Path $roots[$adapter] ".github\workflows\pages.yml") "$adapter workflow"
    }

    if (-not [string]::IsNullOrEmpty($env:INTEGRATION_REFERENCE_DIR)) {
        Assert-BytesEqual (Join-Path $env:INTEGRATION_REFERENCE_DIR "jekyll-obsidian.yml") (Join-Path $roots["cmd"] ".github\jekyll-obsidian.yml") "POSIX and Windows host configuration"
        Assert-BytesEqual (Join-Path $env:INTEGRATION_REFERENCE_DIR "pages.yml") (Join-Path $roots["cmd"] ".github\workflows\pages.yml") "POSIX and Windows workflow"
    }

    $crlfRoot = New-Host
    [void](Invoke-Adapter "pwsh" $crlfRoot @())
    $crlfConfig = Join-Path $crlfRoot ".github\jekyll-obsidian.yml"
    $crlfWorkflow = Join-Path $crlfRoot ".github\workflows\pages.yml"
    Write-Crlf $crlfConfig ([System.IO.File]::ReadAllText($crlfConfig))
    Write-Crlf $crlfWorkflow ([System.IO.File]::ReadAllText($crlfWorkflow))
    [void](Invoke-Adapter "pwsh" $crlfRoot @("--check"))

    $unicodeRoot = New-Host
    $unicodeSource = "Documentation\用户 指南"
    [System.IO.Directory]::CreateDirectory((Join-Path $unicodeRoot $unicodeSource)) | Out-Null
    Write-Lf (Join-Path $unicodeRoot "$unicodeSource\index.md") "---`npublish: true`n---`n# Unicode documentation`n"
    [void](Invoke-Adapter "pwsh" $unicodeRoot @("--source", $unicodeSource, "--theme", "minimal"))
    $config = [System.IO.File]::ReadAllText((Join-Path $unicodeRoot ".github\jekyll-obsidian.yml"))
    $workflow = [System.IO.File]::ReadAllText((Join-Path $unicodeRoot ".github\workflows\pages.yml"))
    if (-not $config.Contains("source: 'Documentation/用户 指南'")) { Fail "Windows source was not normalized" }
    if (-not $workflow.Contains("'Documentation/用户 指南/**'")) { Fail "Unicode workflow trigger was not generated" }

    [System.IO.Directory]::CreateDirectory((Join-Path $unicodeRoot "docs'[one]")) | Out-Null
    Write-Lf (Join-Path $unicodeRoot "docs'[one]\index.md") "---`npublish: true`n---`n# Literal YAML and glob characters`n"
    [void](Invoke-Adapter "pwsh" $unicodeRoot @("--source", "docs'[one]"))
    $workflow = [System.IO.File]::ReadAllText((Join-Path $unicodeRoot ".github\workflows\pages.yml"))
    if (-not $workflow.Contains("'docs''\[one\]/**'")) { Fail "YAML and workflow glob characters were not escaped" }

    $preserveRoot = New-Host
    [void](Invoke-Adapter "pwsh" $preserveRoot @())
    $preservedConfigPath = Join-Path $preserveRoot ".github\jekyll-obsidian.yml"
    $preservedConfig = [System.IO.File]::ReadAllText($preservedConfigPath)
    $preservedConfig = $preservedConfig.Replace("title: My Project Documentation", "title: Preserved host title")
    $preservedConfig = $preservedConfig.Replace('  repository: ""', "  repository: owner/project")
    Write-Lf $preservedConfigPath $preservedConfig
    [void](Invoke-Adapter "pwsh" $preserveRoot @("--theme", "minimal"))
    $preservedConfig = [System.IO.File]::ReadAllText($preservedConfigPath)
    if (-not $preservedConfig.Contains("title: Preserved host title")) { Fail "host title was not preserved" }
    if (-not $preservedConfig.Contains("  repository: owner/project")) { Fail "repository setting was not preserved" }
    if (-not $preservedConfig.Contains("  theme: 'minimal'")) { Fail "managed theme was not updated" }

    $legacyThemeRoot = New-Host
    foreach ($legacyTheme in @("blog", "digital-garden")) {
        [void](Invoke-Adapter "pwsh" $legacyThemeRoot @("--theme", $legacyTheme) $false)
    }
    if (Test-Path -LiteralPath (Join-Path $legacyThemeRoot ".github")) { Fail "an invalid legacy theme left partial integration files" }

    $detachedMarkersRoot = New-Host
    [System.IO.Directory]::CreateDirectory((Join-Path $detachedMarkersRoot ".github")) | Out-Null
    $detachedMarkersPath = Join-Path $detachedMarkersRoot ".github\jekyll-obsidian.yml"
    Write-Lf $detachedMarkersPath "website:`n  repository: owner/project`nother:`n  # jekyll-obsidian:managed-start`n  source: 'docs'`n  theme: 'docs'`n  # jekyll-obsidian:managed-end`n"
    $detachedBefore = [System.IO.File]::ReadAllBytes($detachedMarkersPath)
    [void](Invoke-Adapter "pwsh" $detachedMarkersRoot @() $false)
    $detachedAfter = [System.IO.File]::ReadAllBytes($detachedMarkersPath)
    if ([Convert]::ToBase64String($detachedBefore) -ne [Convert]::ToBase64String($detachedAfter)) { Fail "detached managed markers were rewritten" }

    $conflictRoot = New-Host
    [System.IO.Directory]::CreateDirectory((Join-Path $conflictRoot ".github\workflows")) | Out-Null
    Write-Lf (Join-Path $conflictRoot ".github\workflows\pages.yml") "name: Existing workflow`n"
    [void](Invoke-Adapter "pwsh" $conflictRoot @() $false)
    if (Test-Path -LiteralPath (Join-Path $conflictRoot ".github\jekyll-obsidian.yml")) { Fail "failed preflight left partial configuration" }
    [void](Invoke-Adapter "pwsh" $conflictRoot @("--force-workflow"))

    $unmanagedConfigRoot = New-Host
    [System.IO.Directory]::CreateDirectory((Join-Path $unmanagedConfigRoot ".github")) | Out-Null
    Write-Lf (Join-Path $unmanagedConfigRoot ".github\jekyll-obsidian.yml") "title: Existing configuration`n"
    [void](Invoke-Adapter "pwsh" $unmanagedConfigRoot @() $false)
    if (Test-Path -LiteralPath (Join-Path $unmanagedConfigRoot ".github\workflows")) { Fail "unmanaged configuration failure created a workflow directory" }

    $caseRoot = New-Host
    [void](Invoke-Adapter "pwsh" $caseRoot @("--source", "Docs") $false)

    $junctionRoot = New-Host
    [System.IO.Directory]::CreateDirectory((Join-Path $junctionRoot "real-docs")) | Out-Null
    Write-Lf (Join-Path $junctionRoot "real-docs\index.md") "---`npublish: true`n---`n# Junction`n"
    $junctionPath = Join-Path $junctionRoot "linked-docs"
    & cmd.exe /d /c mklink /J $junctionPath (Join-Path $junctionRoot "real-docs") *> $null
    if ($LASTEXITCODE -eq 0) {
        [void]$TemporaryDirectoryLinks.Add($junctionPath)
        [void](Invoke-Adapter "pwsh" $junctionRoot @("--source", "linked-docs") $false)
    }

    $symlinkRoot = New-Host
    [System.IO.Directory]::CreateDirectory((Join-Path $symlinkRoot "real-docs")) | Out-Null
    Write-Lf (Join-Path $symlinkRoot "real-docs\index.md") "---`npublish: true`n---`n# Symbolic link`n"
    $symlinkPath = Join-Path $symlinkRoot "linked-docs"
    try {
        New-Item -ItemType SymbolicLink -Path $symlinkPath -Target (Join-Path $symlinkRoot "real-docs") -ErrorAction Stop | Out-Null
        [void]$TemporaryDirectoryLinks.Add($symlinkPath)
        [void](Invoke-Adapter "pwsh" $symlinkRoot @("--source", "linked-docs") $false)
    }
    catch {
        if (Test-Path -LiteralPath $symlinkPath) { throw }
    }

    Write-Output "Windows host integration contract passed."
}
finally {
    foreach ($path in $TemporaryDirectoryLinks) {
        $item = Get-Item -Force -LiteralPath $path -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            [System.IO.Directory]::Delete($path)
        }
    }
    foreach ($root in $TemporaryRoots) {
        if (Test-Path -LiteralPath $root) { [System.IO.Directory]::Delete($root, $true) }
    }
}
