[CmdletBinding()]
param(
    [ValidateSet('Study', 'SCI', 'Project', 'All')]
    [string]$Repository = 'All',
    [string]$Message = ('Sync files ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
    [switch]$Preview,
    [switch]$IncludeIgnored,
    [ValidateRange(1, 100)]
    [int]$MaxFileSizeMB = 10,
    [string]$CacheRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git for Windows is required.' }
if (-not (Get-Command robocopy -ErrorAction SilentlyContinue)) { throw 'Windows robocopy is required.' }
if ([string]::IsNullOrWhiteSpace($Message)) { throw 'Commit message must not be empty.' }
if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'GitDualSync'
}
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
$profiles = @(
    @{Name='Study'; Source=$PSScriptRoot; Target='learningplan2026'; Gitee='https://gitee.com/zhu-bingquanzheling/zbq.git'; GitHub='https://github.com/Zljtling/Study.git'},
    @{Name='SCI'; Source='D:\Study\scientific research project'; Target='.'; Gitee='https://gitee.com/zhu-bingquanzheling/sci.git'; GitHub='https://github.com/Zljtling/SCI.git'},
    @{Name='Project'; Source='D:\Projects'; Target='.'; Gitee='https://gitee.com/zhu-bingquanzheling/project.git'; GitHub='https://github.com/Zljtling/Project.git'}
)

$script:GitHubProxy = $null

function Get-WindowsGitHubProxy {
    # Honor explicit Git/environment proxy settings, including an empty Git
    # proxy value that deliberately disables proxying.
    $configuredProxy = & git config --get-urlmatch http.proxy https://github.com
    if ($LASTEXITCODE -eq 0) { return $null }
    foreach ($variable in @('HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY')) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($variable))) { return $null }
    }
    $settings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if (-not $settings -or -not $settings.PSObject.Properties['ProxyEnable'] -or
        -not $settings.PSObject.Properties['ProxyServer'] -or $settings.ProxyEnable -ne 1) { return $null }
    $server = [string]$settings.ProxyServer
    if ($server -match '=') {
        $entries = @{}
        foreach ($entry in ($server -split ';')) {
            $parts = $entry -split '=', 2
            if ($parts.Count -eq 2) { $entries[$parts[0].Trim()] = $parts[1].Trim() }
        }
        if ($entries.ContainsKey('https')) { $server = $entries['https'] }
        elseif ($entries.ContainsKey('http')) { $server = $entries['http'] }
        else { return $null }
    }
    if ([string]::IsNullOrWhiteSpace($server)) { return $null }
    if ($server -notmatch '^\w+://') { $server = 'http://' + $server }
    $uri = $null
    if (-not [uri]::TryCreate($server, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https', 'socks5', 'socks5h') -or $uri.UserInfo) { return $null }
    return $uri.AbsoluteUri
}

function Invoke-GitNetworkProcess {
    param([string[]]$Arguments)
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Command git -CommandType Application | Select-Object -First 1).Source
    # ProcessStartInfo.Arguments uses Windows argument quoting, not a shell.
    $quoted = foreach ($argument in $Arguments) {
        $escaped = [regex]::Replace($argument, '(\\*)"', '$1$1\"')
        $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
        '"' + $escaped + '"'
    }
    $info.Arguments = $quoted -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        $process.Start() | Out-Null
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{ExitCode=$process.ExitCode; Output=$outputTask.GetAwaiter().GetResult(); Error=$errorTask.GetAwaiter().GetResult()}
    } finally { $process.Dispose() }
}

function Invoke-Git {
    param([string[]]$GitArguments)
    $common = @('-c', 'core.longpaths=true', '-c', 'core.safecrlf=false')
    if ($script:GitHubProxy) { $common += @('-c', ('http.https://github.com/.proxy=' + $script:GitHubProxy)) }
    $command = @($GitArguments | Where-Object { -not $_.StartsWith('-') } | Select-Object -First 1)
    $isNetwork = $command.Count -gt 0 -and $command[0] -in @('clone', 'fetch', 'push', 'ls-remote')
    if (-not $isNetwork) {
        & git @common @GitArguments
        if ($LASTEXITCODE -ne 0) { throw ('Git failed: ' + ($GitArguments -join ' ')) }
        return
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        # Read both native streams directly so PS5.1 does not format normal
        # Git progress as NativeCommandError records.
        $result = Invoke-GitNetworkProcess -Arguments ($common + $GitArguments)
        $exitCode = $result.ExitCode
        $details = $result.Error
        if (-not [string]::IsNullOrEmpty($result.Output)) {
            $result.Output.TrimEnd([char[]]"`r`n") -split '\r?\n' | Write-Output
        }
        if (-not [string]::IsNullOrWhiteSpace($details)) { Write-Host $details.TrimEnd() }
        if ($exitCode -eq 0) { return }
        $transient = $details -match '(?i)could not resolve (host|proxy)|failed to connect|connection (was )?reset|recv failure|SSL (connection|connect) error|unexpected disconnect|remote end hung up|HTTP[/ 0-9.]* (408|429|500|502|503|504)|HTTP/2 stream|curl (18|28|35|52|55|56|92)\b|operation timed out|connection timed out|TLS connection was non-properly terminated'
        if (-not $transient) { throw ('Git failed: ' + ($GitArguments -join ' ')) }
        if ($attempt -lt 3) {
            Write-Host ('Temporary network failure. Retrying ' + ($attempt + 1) + '/3...')
            Start-Sleep -Seconds (2 * $attempt)
        } else {
            throw ('Network connection failed after 3 attempts. Check GitHub access and that the configured proxy is running, then rerun All_sync. Git command: ' + ($GitArguments -join ' '))
        }
    }
}

function Get-Commit {
    param([string]$GitDirectory, [string]$Ref)
    $value = & git --git-dir=$GitDirectory rev-parse --verify --quiet $Ref
    if ($LASTEXITCODE -eq 0) { return ($value -join '').Trim() }
    if ($LASTEXITCODE -ne 1) { throw ('Cannot inspect ref: ' + $Ref) }
    return $null
}

function Get-CoreFilePolicy {
    $extensions = 'c cc cpp cxx h hh hpp hxx inl ixx cs fs vb py pyi ipynb r rmd jl m js jsx ts tsx html htm css scss sass less vue svelte gd gdshader godot tscn tres gdextension uid import sln slnx vcxproj filters csproj fsproj vbproj props targets rc resx cmake make ps1 sh bash zsh bat cmd json jsonc yaml yml toml ini cfg config xml lock txt md rst tex bib pdf docx xlsx pptx csv tsv svg png jpg jpeg webp gif bmp tga ico aseprite wav ogg mp3 flac ttf otf woff woff2 gltf glb fbx blend' -split ' '
    $names = @('.gitignore', '.gitattributes', '.gitmodules', '.editorconfig', '.dockerignore', '.clang-format', '.clang-tidy', '.env.example', 'Makefile', 'Dockerfile', 'LICENSE', 'COPYING', 'NOTICE', 'README')
    $patterns = @($extensions | ForEach-Object { '*.' + $_ }) + $names
    $directories = @('.git', '.gitee-nunpy-cleanup', '.vs', '.idea', '.godot', '.venv', 'venv', 'node_modules', '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.ipynb_checkpoints', '.cache', 'cache', 'Debug', 'Release', 'x64', 'x86', 'ipch', 'bin', 'obj', 'build', 'dist', 'out', 'outputs', 'demo', 'shader_cache', 'imported')
    return @{Patterns=$patterns; Directories=$directories}
}

function Get-TreeSize {
    param([string]$GitDirectory, [string]$Tree)
    $count = 0
    [long]$bytes = 0
    if ($Tree) {
        $lines = @(Invoke-Git -GitArguments @("--git-dir=$GitDirectory", 'ls-tree', '-r', '-l', $Tree))
        foreach ($line in $lines) {
            if ($line -match '^\d+ blob [0-9a-f]+\s+(\d+)\t') { $count++; $bytes += [long]$Matches[1] }
        }
    }
    return @{Files=$count;Bytes=$bytes}
}

function Sync-Profile {
    param([hashtable]$Profile)
    $name = $Profile.Name
    $source = (Resolve-Path -LiteralPath $Profile.Source).Path
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw ('Source folder missing: ' + $source) }
    $profileCache = Join-Path $CacheRoot $name
    New-Item -ItemType Directory -Path $profileCache -Force | Out-Null
    $lockPath = Join-Path $profileCache 'sync.lock'
    try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw ('Another sync is running for ' + $name + '. Close it before retrying.') }
    $gitDirectory = Join-Path $profileCache 'repository.git'
    $work = Join-Path $profileCache ('snapshot-' + [guid]::NewGuid().ToString('N'))
    $snapshot = Join-Path $work 'files'
    $index = Join-Path $work 'index'
    $oldIndex = $env:GIT_INDEX_FILE
    $succeeded = $false
    try {
        Write-Host ("`n=== {0} ===" -f $name)
        Write-Host ('Source: ' + $source)
        Write-Host '[1/5] Fetching Gitee and GitHub...'
        if (-not (Test-Path -LiteralPath $gitDirectory)) {
            Invoke-Git -GitArguments @('clone', '--bare', '--', $Profile.Gitee, $gitDirectory)
        }
        Invoke-Git -GitArguments @("--git-dir=$gitDirectory", 'remote', 'set-url', 'origin', $Profile.Gitee)
        $remotes = @(Invoke-Git -GitArguments @("--git-dir=$gitDirectory", 'remote'))
        if ($remotes -contains 'github') {
            Invoke-Git -GitArguments @("--git-dir=$gitDirectory", 'remote', 'set-url', 'github', $Profile.GitHub)
        } else {
            Invoke-Git -GitArguments @("--git-dir=$gitDirectory", 'remote', 'add', 'github', $Profile.GitHub)
        }
        foreach ($remoteName in @('origin', 'github')) {
            Invoke-Git -GitArguments @("--git-dir=$gitDirectory", 'fetch', '--prune', $remoteName, ('+refs/heads/*:refs/remotes/' + $remoteName + '/*'))
        }
        $parent = $null
        foreach ($ref in @('refs/heads/main', 'refs/remotes/origin/main', 'refs/remotes/github/main')) {
            $candidate = Get-Commit -GitDirectory $gitDirectory -Ref $ref
            if (-not $candidate -or $candidate -eq $parent) { continue }
            if (-not $parent) { $parent = $candidate; continue }
            & git --git-dir=$gitDirectory merge-base --is-ancestor $parent $candidate
            $forward = $LASTEXITCODE
            if ($forward -eq 0) { $parent = $candidate; continue }
            if ($forward -ne 1) { throw 'Cannot compare repository histories.' }
            & git --git-dir=$gitDirectory merge-base --is-ancestor $candidate $parent
            if ($LASTEXITCODE -ne 0) {
                throw 'Gitee and GitHub have divergent commits. Resolve the conflict before syncing; no force push was made.'
            }
        }
        New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
        $env:GIT_INDEX_FILE = $index
        $base = @("--git-dir=$gitDirectory", "--work-tree=$snapshot")
        if ($parent) { Invoke-Git -GitArguments ($base + @('read-tree', $parent)) }
        else { Invoke-Git -GitArguments ($base + @('read-tree', '--empty')) }
        # Preserve repository-wide ignore rules when only replacing a subfolder.
        if ($parent -and $Profile.Target -ne '.') {
            foreach ($metadata in @('.gitignore', '.gitattributes')) {
                $exists = @(Invoke-Git -GitArguments ($base + @('ls-files', '--', $metadata)))
                if ($exists.Count -gt 0) { Invoke-Git -GitArguments ($base + @('checkout-index', '--', $metadata)) }
            }
        }
        Write-Host ('[2/5] Selecting core files up to ' + $MaxFileSizeMB + ' MiB (local originals are retained)...')
        $destination = Join-Path $snapshot $Profile.Target
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        $policy = Get-CoreFilePolicy
        $copy = @($source, $destination) + $policy.Patterns
        $copy += @('/E', '/XJ', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', ('/MAX:' + ([long]$MaxFileSizeMB * 1MB)), '/XD')
        $copy += $policy.Directories
        $copy += @('/XF', '.git', '*.user', '*.suo', '*.log', '*.tmp', '*.bak')
        & robocopy @copy
        if ($LASTEXITCODE -ge 8) { throw ('Robocopy failed: ' + $LASTEXITCODE) }
        Write-Host '[3/5] Staging additions, updates and deletions...'
        Invoke-Git -GitArguments ($base + @('rm', '-r', '-f', '--cached', '--quiet', '--ignore-unmatch', '--', $Profile.Target))
        $add = $base + @('add', '-A')
        if ($IncludeIgnored) { $add += '-f' }
        Invoke-Git -GitArguments ($add + @('--', $Profile.Target))
        $entries = @(Invoke-Git -GitArguments ($base + @('ls-files', '--stage')))
        $objects = @{}
        foreach ($entry in $entries) {
            if ($entry -match '^\d+ ([0-9a-f]+) \d\t(.+)$') {
                if (-not $objects.ContainsKey($Matches[1])) { $objects[$Matches[1]] = @() }
                $objects[$Matches[1]] += $Matches[2]
            }
        }
        if ($objects.Count -gt 0) {
            $sizes = $objects.Keys | & git --git-dir=$gitDirectory cat-file '--batch-check=%(objectname) %(objectsize)'
            if ($LASTEXITCODE -ne 0) { throw 'Cannot check file sizes.' }
            $oversized = @()
            foreach ($line in $sizes) {
                $parts = $line -split ' '
                if ([long]$parts[1] -gt ([long]$MaxFileSizeMB * 1MB)) {
                    foreach ($path in $objects[$parts[0]]) {
                        $oversized += ('{0:N1} MiB  {1}' -f ([long]$parts[1]/1MB), $path)
                    }
                }
            }
            if ($oversized.Count -gt 0) { throw ("Oversized files; no push made:`n" + ($oversized -join "`n")) }
        }
        $tree = (Invoke-Git -GitArguments ($base + @('write-tree'))).Trim()
        $oldTree = if ($parent) { (Invoke-Git -GitArguments ($base + @('rev-parse', ($parent + '^{tree}')))).Trim() } else { $null }
        $before = Get-TreeSize -GitDirectory $gitDirectory -Tree $parent
        $after = Get-TreeSize -GitDirectory $gitDirectory -Tree $tree
        Write-Host ('Tracked files: {0} -> {1}; content size: {2:N2} -> {3:N2} MiB (Git history size is separate).' -f $before.Files, $after.Files, ($before.Bytes/1MB), ($after.Bytes/1MB))
        @{Repository=$name;Parent=$parent;Tree=$tree;BeforeFiles=$before.Files;AfterFiles=$after.Files;BeforeBytes=$before.Bytes;AfterBytes=$after.Bytes} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $profileCache 'selection.json') -Encoding UTF8
        if ($parent) { Invoke-Git -GitArguments ($base + @('diff', '--cached', '--stat', '--stat-count=10', $parent)) }
        else { Invoke-Git -GitArguments ($base + @('diff', '--cached', '--stat', '--stat-count=10')) }
        if ($Preview) {
            Write-Host 'Preview complete. No commit or push.'
            $succeeded = $true
            return
        }
        if (-not $parent -and $entries.Count -eq 0) {
            Write-Host 'Source folder and remote repository are empty. Both repositories remain empty.'
            $succeeded = $true
            return
        }
        Write-Host '[4/5] Preparing the shared commit...'
        $commit = $parent
        if (-not $parent -or $tree -ne $oldTree) {
            foreach ($key in @('user.name', 'user.email')) {
                $identity = (& git -C $source config --get $key)
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($identity -join ''))) { throw ('Set Git ' + $key + ' before syncing.') }
                Invoke-Git -GitArguments ($base + @('config', $key, ($identity -join "`n")))
            }
            $create = $base + @('commit-tree', $tree)
            if ($parent) { $create += @('-p', $parent) }
            $commit = (Invoke-Git -GitArguments ($create + @('-m', $Message))).Trim()
        }
        Invoke-Git -GitArguments ($base + @('update-ref', 'refs/heads/main', $commit))
        Invoke-Git -GitArguments ($base + @('symbolic-ref', 'HEAD', 'refs/heads/main'))
        # Restore the caller's index before remote operations.
        $env:GIT_INDEX_FILE = $oldIndex
        Write-Host '[5/5] Pushing the same commit to Gitee and GitHub...'
        $failures = @()
        foreach ($remoteName in @('origin', 'github')) {
            try {
                Invoke-Git -GitArguments @("--git-dir=$gitDirectory", 'push', '--progress', $remoteName, 'refs/heads/main:refs/heads/main')
                $head = Invoke-Git -GitArguments @("--git-dir=$gitDirectory", 'ls-remote', $remoteName, 'refs/heads/main')
                if (($head -join '') -notlike ($commit + '*')) { throw 'Remote verification failed.' }
                Write-Host ($remoteName + ': verified ' + $commit)
            } catch { $failures += ($remoteName + ': ' + $_.Exception.Message) }
        }
        if ($failures.Count -gt 0) { throw (($failures -join "`n") + "`nCommit retained in cache. Run the same shortcut again to finish syncing.") }
        Write-Host ('SUCCESS: ' + $name + ' is synchronized on both platforms.')
        $succeeded = $true
    } finally {
        $env:GIT_INDEX_FILE = $oldIndex
        if ($succeeded -and (Test-Path -LiteralPath $work)) {
            $resolvedWork = [IO.Path]::GetFullPath($work)
            if ([IO.Path]::GetDirectoryName($resolvedWork) -eq [IO.Path]::GetFullPath($profileCache) -and
                [IO.Path]::GetFileName($resolvedWork) -match '^snapshot-[0-9a-f]{32}$') {
                try { Remove-Item -LiteralPath $resolvedWork -Recurse -Force }
                catch { Write-Warning ('Sync completed. Temporary cleanup could not finish: ' + $resolvedWork) }
            }
        } elseif (-not $succeeded) {
            if (Test-Path -LiteralPath $work) { Write-Host ('Snapshot retained: ' + $work) }
            else { Write-Host 'Stopped before copying or committing local files.' }
        }
        $lock.Dispose()
    }
}

$logDirectory = Join-Path $CacheRoot 'logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$log = Join-Path $logDirectory ('Sync-' + $Repository + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
Start-Transcript -LiteralPath $log | Out-Null
try {
    Write-Host ('Log: ' + $log)
    $script:GitHubProxy = Get-WindowsGitHubProxy
    if ($script:GitHubProxy) {
        $proxyUri = [uri]$script:GitHubProxy
        Write-Host ('GitHub uses the enabled Windows proxy for this run: ' + $proxyUri.Host + ':' + $proxyUri.Port)
    }
    $errors = @()
    foreach ($profile in $profiles) {
        if ($Repository -ne 'All' -and $profile.Name -ne $Repository) { continue }
        try { Sync-Profile -Profile $profile }
        catch { Write-Host ($profile.Name + ' FAILED: ' + $_.Exception.Message) -ForegroundColor Red; $errors += $profile.Name }
    }
    if ($errors.Count -gt 0) { throw ('Sync incomplete: ' + ($errors -join ', ') + '. See log: ' + $log) }
} finally { Stop-Transcript | Out-Null }

