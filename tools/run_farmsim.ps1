<#
    FarmSim helper script.

    Finds the Godot 4 executable on this machine, then either runs the
    automated test suite (headless) or launches the prototype for play.

        powershell -ExecutionPolicy Bypass -File tools\run_farmsim.ps1 -Mode test
        powershell -ExecutionPolicy Bypass -File tools\run_farmsim.ps1 -Mode play
        powershell -ExecutionPolicy Bypass -File tools\run_farmsim.ps1 -Mode lan
        powershell -ExecutionPolicy Bypass -File tools\run_farmsim.ps1 -Mode pair
        powershell -ExecutionPolicy Bypass -File tools\run_farmsim.ps1 -Mode phone

    LAN port: 'lan' runs the two-copy network test headlessly (a host and a
    client on this computer play a whole session against each other); 'pair'
    opens two game windows so you can try hosting and joining on one machine.

    Normally you would just double-click run_tests.bat or run_game.bat instead.

    Everything it does is written to test_out\runner.log and, for the engine
    itself, test_out\godot_output.log, so a run can be inspected afterwards
    without anyone having watched the console.
#>

param(
    [ValidateSet('test', 'play', 'import', 'find', 'lan', 'pair', 'phone')]
    [string]$Mode = 'test',
    [int]$TimeoutSeconds = 300,
    # Extra arguments for the LAN test, e.g. '--blip' (Player 2 loses the link
    # mid-season and reconnects) or '--host-blip' (the host's link drops).
    [string]$LanCase = ''
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OutDir      = Join-Path $ProjectRoot 'test_out'
$RunnerLog   = Join-Path $OutDir 'runner.log'
$GodotLog    = Join-Path $OutDir 'godot_output.log'
$GodotErrLog = Join-Path $OutDir 'godot_stderr.log'
$PathFile    = Join-Path $OutDir 'godot_path.txt'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Set-Content -Path $RunnerLog -Value "FarmSim runner - $(Get-Date -Format o)" -Encoding UTF8

function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $RunnerLog -Value $Message -Encoding UTF8
}

Write-Log "Mode:         $Mode"
Write-Log "Project root: $ProjectRoot"

# --------------------------------------------------------------- discovery ---

function Test-GodotExecutable {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $version = & $Path --version 2>$null | Select-Object -First 1
    } catch {
        return $null
    }
    if ($null -eq $version) { return $null }
    $version = "$version".Trim()
    if ($version -notmatch '^4\.') { return $null }
    return [pscustomobject]@{ Path = $Path; Version = $version }
}

function Find-Godot {
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:GODOT_EXE) { $candidates.Add($env:GODOT_EXE) }

    foreach ($name in @('godot', 'godot4', 'Godot', 'Godot_v4')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { $candidates.Add($cmd.Source) }
    }

    $searchRoots = @(
        'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine',
        'C:\Program Files\Godot',
        'C:\Program Files (x86)\Godot',
        (Join-Path $env:LOCALAPPDATA 'Programs\Godot'),
        (Join-Path $env:LOCALAPPDATA 'Godot'),
        (Join-Path $env:USERPROFILE 'scoop\apps\godot'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Documents'),
        'C:\ProgramData\chocolatey\lib\godot\tools'
    )

    # Steam can be installed on another drive; look for its library folders too.
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $steamPath = Join-Path $drive.Root 'SteamLibrary\steamapps\common\Godot Engine'
        if (Test-Path -LiteralPath $steamPath) { $searchRoots += $steamPath }
    }

    foreach ($root in $searchRoots) {
        if (-not $root) { continue }
        if (-not (Test-Path -LiteralPath $root)) { continue }
        try {
            $found = Get-ChildItem -LiteralPath $root -Filter '*.exe' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '(?i)godot' -and $_.Name -notmatch '(?i)console' }
        } catch {
            $found = @()
        }
        foreach ($file in $found) { $candidates.Add($file.FullName) }
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($seen.ContainsKey($candidate)) { continue }
        $seen[$candidate] = $true
        $result = Test-GodotExecutable -Path $candidate
        if ($result) { return $result }
    }
    return $null
}

$godot = Find-Godot

if (-not $godot) {
    Write-Log ''
    Write-Log 'ERROR: could not find a Godot 4 executable on this machine.'
    Write-Log 'Looked in: PATH, the GODOT_EXE environment variable, Steam, Program Files,'
    Write-Log '           LocalAppData, Downloads, Desktop and Documents.'
    Write-Log ''
    Write-Log 'Fix it by setting GODOT_EXE for this window and running again, for example:'
    Write-Log '  $env:GODOT_EXE = "C:\path\to\Godot_v4.x-stable_win64.exe"'
    Set-Content -Path $PathFile -Value 'NOT_FOUND' -Encoding UTF8
    exit 3
}

Write-Log "Godot:        $($godot.Path)"
Write-Log "Version:      $($godot.Version)"
Set-Content -Path $PathFile -Value "$($godot.Path)`n$($godot.Version)" -Encoding UTF8

if ($Mode -eq 'find') { exit 0 }

# ------------------------------------------------------------------- runs ---

function Quote-Arg {
    param([string]$Value)
    if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
    return $Value
}

function Invoke-Godot {
    param(
        [string[]]$GodotArgs,
        [string]$StdOut,
        [string]$StdErr,
        [int]$Timeout
    )
    Write-Log "Running: `"$($godot.Path)`" $($GodotArgs -join ' ')"

    # Started through System.Diagnostics.Process rather than Start-Process:
    # Start-Process -PassThru does not reliably populate ExitCode, which is why
    # this script used to log a blank exit code for every run.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $godot.Path
    $psi.Arguments = (($GodotArgs | ForEach-Object { Quote-Arg $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($psi)
    # Read both streams asynchronously; reading one to the end while the other
    # fills its pipe buffer would deadlock.
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()

    $exitCode = 0
    if (-not $process.WaitForExit($Timeout * 1000)) {
        Write-Log "TIMEOUT after $Timeout seconds - stopping Godot."
        try { $process.Kill() } catch { }
        $exitCode = 124
    } else {
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    }

    Set-Content -Path $StdOut -Value $outTask.Result -Encoding UTF8
    Set-Content -Path $StdErr -Value $errTask.Result -Encoding UTF8
    return $exitCode
}

function Show-Log {
    param([string]$Path, [string]$Heading)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $content = Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $content -or "$content".Trim().Length -eq 0) { return $false }
    Write-Log ''
    Write-Log "---------------- $Heading ----------------"
    $content | ForEach-Object { Write-Log $_ }
    Write-Log '-----------------------------------------------'
    return $true
}

$importOut = Join-Path $OutDir 'godot_import.log'
$importErr = Join-Path $OutDir 'godot_import_stderr.log'
Write-Log ''
Write-Log 'Importing project resources...'
$importCode = Invoke-Godot -GodotArgs @('--headless', '--path', $ProjectRoot, '--import') `
    -StdOut $importOut -StdErr $importErr -Timeout 180
Write-Log "Import exit code: $importCode"
$importFailed = Show-Log -Path $importErr -Heading 'IMPORT PROBLEMS (scripts or resources that did not load)'
if ($importFailed) {
    Write-Log ''
    Write-Log 'WARNING: the import step reported errors. A script that fails to compile here'
    Write-Log '         is a script the game will run without - which usually shows up as a'
    Write-Log '         blank screen rather than a crash.'
}

if ($Mode -eq 'import') { exit $importCode }

if ($Mode -eq 'play') {
    Write-Log ''
    Write-Log 'Launching FarmSim...'
    $code = Invoke-Godot -GodotArgs @('--path', $ProjectRoot) `
        -StdOut $GodotLog -StdErr $GodotErrLog -Timeout $TimeoutSeconds
    Write-Log "FarmSim exit code: $code"
    Show-Log -Path $GodotLog -Heading 'game output' | Out-Null
    Show-Log -Path $GodotErrLog -Heading 'game errors' | Out-Null
    exit $code
}

if ($Mode -eq 'pair') {
    Write-Log ''
    Write-Log 'Opening two FarmSim windows. Host in one, join in the other (address 127.0.0.1).'
    Start-Process -FilePath $godot.Path -ArgumentList @('--path', (Quote-Arg $ProjectRoot), '--position', '40,60')
    Start-Sleep -Seconds 1
    Start-Process -FilePath $godot.Path -ArgumentList @('--path', (Quote-Arg $ProjectRoot), '--position', '700,120')
    exit 0
}

if ($Mode -eq 'phone') {
    Write-Log ''
    Write-Log 'Opening a computer window and a phone-shaped window (mobile layout, mouse acts as a finger).'
    Write-Log 'Host in the computer window, then Play with a friend > Find games in the phone window.'
    Start-Process -FilePath $godot.Path -ArgumentList @('--path', (Quote-Arg $ProjectRoot), '--position', '40,60')
    Start-Sleep -Seconds 1
    Start-Process -FilePath $godot.Path -ArgumentList @('--path', (Quote-Arg $ProjectRoot), '--position', '300,200', '--resolution', '1200x540', '--', '--mobile')
    exit 0
}

if ($Mode -eq 'lan') {
    Write-Log ''
    Write-Log 'Running the LAN test: a host and a client on this computer...'
    $hostOut = Join-Path $OutDir 'lan_host.log'
    $clientOut = Join-Path $OutDir 'lan_client.log'
    $hostPsi = New-Object System.Diagnostics.ProcessStartInfo
    $hostPsi.FileName = $godot.Path
    $hostPsi.Arguments = "--headless --path $(Quote-Arg $ProjectRoot) -- --lan-smoke --role=host $LanCase"
    $hostPsi.UseShellExecute = $false
    $hostPsi.CreateNoWindow = $true
    $hostPsi.RedirectStandardOutput = $true
    $hostPsi.RedirectStandardError = $true
    $hostProcess = [System.Diagnostics.Process]::Start($hostPsi)
    $hostOutTask = $hostProcess.StandardOutput.ReadToEndAsync()
    $hostErrTask = $hostProcess.StandardError.ReadToEndAsync()
    Start-Sleep -Seconds 2
    $clientArgs = @('--headless', '--path', $ProjectRoot, '--', '--lan-smoke', '--role=client', '--mobile')
    if ($LanCase) { $clientArgs += $LanCase }
    $clientCode = Invoke-Godot -GodotArgs $clientArgs `
        -StdOut $clientOut -StdErr (Join-Path $OutDir 'lan_client_stderr.log') -Timeout $TimeoutSeconds
    if (-not $hostProcess.WaitForExit(30000)) { try { $hostProcess.Kill() } catch { } }
    $hostProcess.WaitForExit()
    Set-Content -Path $hostOut -Value ($hostOutTask.Result + $hostErrTask.Result) -Encoding UTF8
    Get-Content -LiteralPath $hostOut | Where-Object { $_ -match '^\[lan:' } | ForEach-Object { Write-Log $_ }
    Get-Content -LiteralPath $clientOut | Where-Object { $_ -match '^\[lan:' } | ForEach-Object { Write-Log $_ }
    $hostCode = $hostProcess.ExitCode
    Write-Log "Host exit code: $hostCode   Client exit code: $clientCode"
    if ($hostCode -ne 0 -or $clientCode -ne 0) { exit 1 }
    exit 0
}

Write-Log ''
Write-Log 'Running the automated test suite (headless)...'
$code = Invoke-Godot -GodotArgs @('--headless', '--path', $ProjectRoot, '--', '--run-tests') `
    -StdOut $GodotLog -StdErr $GodotErrLog -Timeout $TimeoutSeconds
Write-Log "Test suite exit code: $code"

Show-Log -Path $GodotLog -Heading 'engine output' | Out-Null
Show-Log -Path $GodotErrLog -Heading 'engine errors' | Out-Null

$resultsPath = Join-Path $OutDir 'test_results.json'
if (Test-Path -LiteralPath $resultsPath) {
    Write-Log "Results file: $resultsPath"
} else {
    Write-Log 'WARNING: no test_results.json was produced.'
}

exit $code
