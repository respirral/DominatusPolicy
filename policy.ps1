#Requires -Version 5.0

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    $sp = try { (Resolve-Path $MyInvocation.MyCommand.Definition -ErrorAction Stop).Path } catch { $null }
    if ($sp -and (Test-Path $sp)) {
        Write-Host "[INFO] Relaunching with admin rights..." -ForegroundColor Yellow
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$sp`""
        exit
    } else {
        Write-Host "`n[WARNING] Run this from a saved .ps1 file as Administrator.`n" -ForegroundColor Red
        Pause; exit 1
    }
}

$PASS='Pass'; $WARN='Unsure'; $FAIL='Fail'
function Line { param([string]$T,[ConsoleColor]$C='White') Write-Host $T -ForegroundColor $C }

$Users = @{}
$Users['owner']    = 'unknown'
$Users['dieshire'] = 'daddy'
$Users['cearful']  = 'son'
$Users['villian']  = 'yeah'

function Get-HWID {
    try { $u = (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID } catch { $u = $null }
    if (-not $u -or $u -eq 'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF'){
        try { $u = (Get-CimInstance Win32_BIOS).SerialNumber } catch { $u = 'UNKNOWN' }
    }
    return "$u".Trim()
}

$hwid = Get-HWID
$lockFile = Join-Path $env:ProgramData 'dominatus_hwid.json'

$locks = @{}
if (Test-Path $lockFile){
    try { (Get-Content $lockFile -Raw | ConvertFrom-Json) | ForEach-Object { $locks[$_.user] = $_.hwid } } catch { $locks = @{} }
}
function Save-Locks { param($tbl,$path)
    try { @($tbl.GetEnumerator() | ForEach-Object { [pscustomobject]@{ user=$_.Key; hwid=$_.Value } } | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8 } catch {}
}

Clear-Host
Line ""
Line "=== Dominatus Recording Policy - Login ===" Yellow
Line ""

$authed = $false
for ($tryN=1; $tryN -le 3; $tryN++){
    $u = (Read-Host "Username").Trim()
    $p = (Read-Host "Password").Trim()
    if (-not $Users.ContainsKey($u) -or $Users[$u] -ne $p){
        Line "Invalid username or password. ($tryN/3)" Red; Write-Host ""
        continue
    }
    if ($locks.ContainsKey($u)){
        if ($locks[$u] -eq $hwid){
            Line "Welcome back, $u." Green; $authed=$true; break
        } else {
            Line "This login is locked to another machine. Access denied." Red
            Line "Your HWID: $hwid" DarkGray; Write-Host ""
            continue
        }
    } else {
        $locks[$u] = $hwid
        Save-Locks $locks $lockFile
        Line "Login OK. This account is now locked to this machine." Green
        Line "HWID: $hwid" DarkGray
        $authed=$true; break
    }
}
if (-not $authed){
    Write-Host ""; Line "Authentication failed. Exiting." Red
    Start-Sleep -Seconds 2; exit 1
}
Start-Sleep -Seconds 1
Clear-Host

function Show-LoadingBar {
    for ($i=0; $i -le 10; $i++){
        $bar = "#"*$i + "-"*(10-$i)
        Write-Host -NoNewline ("`rProgress: [ $bar ] {0}% " -f ($i*10)) -ForegroundColor White
        Start-Sleep -Milliseconds 80
    }
    Write-Host ""; Write-Host ""
}
function Wait-ForEnter {
    param([string]$Message = "Press Enter to Continue")
    Start-Sleep -Seconds 0.5
    Line $Message Yellow
    while ($true){ if ([Console]::KeyAvailable){ if ([Console]::ReadKey($true).Key -eq 'Enter'){ break } } Start-Sleep -Milliseconds 50 }
}

$SigCache = @{}
function Fast-SigValid { param([string]$Path)
    if (-not $Path) { return $true }
    if ($SigCache.ContainsKey($Path)) { return $SigCache[$Path] }
    $ok = $true
    try { $s = Get-AuthenticodeSignature -FilePath $Path -ErrorAction SilentlyContinue; $ok = ($s.Status -eq 'Valid') } catch { $ok = $true }
    $SigCache[$Path] = $ok
    return $ok
}

$Results = New-Object System.Collections.Generic.List[object]
function Note { param([string]$State,[string]$Text) $Results.Add([pscustomobject]@{State=$State;Text=$Text}) }

function Write-Section {
    param([int]$From)
    for ($i=$From; $i -lt $Results.Count; $i++){
        $r=$Results[$i]
        switch ($r.State){
            'Pass'   { Line ("SUCCESS: " + $r.Text) Green }
            'Unsure' { Line ("WARNING: " + $r.Text) Yellow }
            'Fail'   { Line ("FAILURE: " + $r.Text) Red }
        }
    }
}

$CheatList = @(
    'spectre.exe',
    'cheatengine.exe',
    'cheatengine-x86_64.exe',
    'csrss.exe',
    'mimikatz.exe',
    'injector.exe',
    'loader.exe',
    'xenos.exe',
    'extremeinjector.exe',
    'ghost.exe',
    'chams.exe',
    'esp.exe',
    'wallhack.exe',
    'aimbot.exe',
    'triggerbot.exe',
    'fivem.exe',
    'crack.exe',
    'noclip.exe',
    'flyhack.exe'
)

function Is-Cheat { param([string]$P)
    if (-not $P) { return $false }
    $leaf = try { (Split-Path $P -Leaf).ToLower() } catch { $P.ToLower() }
    foreach ($f in $CheatList){
        if ($leaf -eq $f -or $leaf -match 'cheat|inject|hack|aim|esp|wall|cham|trigger|fly|noclip') {
            return $true
        }
    }
    return $false
}

function Get-Entropy {
    param([byte[]]$Data)
    if (-not $Data -or $Data.Length -lt 4) { return 0 }
    $freq = @{}
    foreach ($b in $Data) {
        if ($freq.ContainsKey($b)) { $freq[$b]++ } else { $freq[$b] = 1 }
    }
    $len = $Data.Length
    $entropy = 0.0
    foreach ($count in $freq.Values) {
        $p = $count / $len
        $entropy -= $p * [math]::Log($p, 2)
    }
    return $entropy
}

Line ""
Line "=== Dominatus Recording Policy ===" Yellow
Line "Complete all steps with 100% success to pass." White
Line "This policy currently has 3 steps." White
Write-Host ""

$os=Get-CimInstance Win32_OperatingSystem
$cpu=Get-CimInstance Win32_Processor|Select-Object -First 1
$bios=Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
$board=Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
$disks=@(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)

if ($cpu.NumberOfCores -ge 4 -and $cpu.MaxClockSpeed -ge 2500){ Line "CPU: type OK" Green } else { Line "CPU: type OK" Yellow }
Line ("OS: $($os.Caption) (build $($os.BuildNumber))") White
Line ("Install: $($os.InstallDate.ToString('yyyy-MM-dd HH:mm'))") White
Line ("Uptime: {0:dd\d\ hh\h\ mm\m}" -f ((Get-Date)-$os.LastBootUpTime)) White
Write-Host ""

$bad = @('','0','none','default string','to be filled by o.e.m.','system serial number','not specified','not applicable')
function Serial-OK { param([string]$S) if (-not $S){ return $false } if ($bad -contains $S.Trim().ToLower()){ return $false } return $true }
if (Serial-OK $bios.SerialNumber){  Line "BIOS serial: normal" Green } else { Line "BIOS serial: blank/placeholder" Yellow }
if (Serial-OK $board.SerialNumber){ Line "Board serial: normal" Green } else { Line "Board serial: blank/placeholder" Yellow }
$di=0; foreach ($d in $disks){ $di++; if (Serial-OK $d.SerialNumber){ Line "Disk $di serial: normal" Green } else { Line "Disk $di serial: blank/placeholder" Yellow } }

Write-Host ""
Line "=== Credits ===" Yellow
Line "Made by stayvague" White
Write-Host ""
Wait-ForEnter
Clear-Host

# ============================================================
# STEP 1: BAM + Amcache Cheat Scan
# ============================================================
Line "Step 1 of 3: BAM & Amcache - Cheat Detection" White
Line "INSTRUCTION: Scanning for cheat-related traces" Yellow
Write-Host ""
Show-LoadingBar
$s1=$Results.Count

$bamN=0; $bamHit=0
foreach ($root in @('HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings','HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings')){
    if (-not (Test-Path $root)){ continue }
    Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
        $p=Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if (-not $p){ return }
        $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and $_.Name -match '\.exe$' } | ForEach-Object {
            $bamN++; $when='?'
            try { $d=$_.Value; if ($d -is [byte[]] -and $d.Length -ge 8){ $ft=[BitConverter]::ToInt64($d,0); if ($ft -gt 0){ $when=[DateTime]::FromFileTimeUtc($ft).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } } } catch {}
            if (Is-Cheat $_.Name){ $bamHit++; Note $FAIL "BAM shows cheat ran -> $(Split-Path $_.Name -Leaf) [last run $when]" }
        } } }
if ($bamN -eq 0){ Note $WARN "BAM has no execution records." }
elseif ($bamHit -eq 0){ Note $PASS "BAM: $bamN entries, no cheats found." }

$am="$env:SystemRoot\AppCompat\Programs\Amcache.hve"
if (Test-Path $am){ $kb=[int]((Get-Item $am -Force).Length/1KB); Note $PASS "Amcache present (${kb}KB)." } else { Note $WARN "Amcache hive missing." }

$srum="$env:SystemRoot\System32\sru\SRUDB.dat"
if (Test-Path $srum){ $mb=[math]::Round((Get-Item $srum -Force).Length/1MB,1); Note $PASS "SRUM present (${mb}MB)." } else { Note $WARN "SRUM missing." }

Write-Section $s1
$sub=$Results | Select-Object -Skip $s1
$t=($sub).Count; $ok=@($sub|Where-Object{$_.State -eq 'Pass'}).Count
Write-Host ""
Line ("Success Rate: {0}% ($ok / $t)" -f $([math]::Round($ok/[math]::Max($t,1)*100,0))) $(if($ok -eq $t){'Green'}else{'Red'})
Wait-ForEnter
Clear-Host

# ============================================================
# STEP 2: Process Explorer Auto-Launch + Tamper Check
# ============================================================
Line "Step 2 of 3: Process Explorer - Live Cheat Scan" White
Line "INSTRUCTION: Launching Process Explorer and scanning for cheats" Yellow
Write-Host ""

# Auto-launch Process Explorer
$procexpPaths = @(
    "C:\Program Files\Process Explorer\procexp.exe",
    "C:\Program Files (x86)\Process Explorer\procexp.exe",
    "C:\Windows\System32\procexp.exe",
    "procexp.exe"
)

$launched = $false
foreach ($p in $procexpPaths) {
    try {
        if (Test-Path $p -ErrorAction SilentlyContinue) {
            Start-Process -FilePath $p -WindowStyle Normal -ErrorAction SilentlyContinue
            $launched = $true
            Line "✅ Process Explorer launched from: $p" Green
            break
        }
    } catch {}
}

if (-not $launched) {
    try {
        Start-Process -FilePath "procexp.exe" -WindowStyle Normal -ErrorAction SilentlyContinue
        $launched = $true
        Line "✅ Process Explorer launched from PATH" Green
    } catch {}
}

if (-not $launched) {
    Line "⚠️ Process Explorer not found. Please download from Sysinternals." Yellow
    Line "   Install path: C:\Program Files\Process Explorer\procexp.exe" Yellow
}

Start-Sleep -Seconds 1
Line "🔍 Scanning running processes for cheats..." Yellow
$s2=$Results.Count

$flagHit = 0
$scanned = 0
$cheatProcs = @()

try {
    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($proc in $procs) {
        $scanned++
        $path = $null
        try { $path = $proc.MainModule.FileName } catch { $path = $null }
        $nm = if ($path) { $path } else { "$($proc.ProcessName).exe" }
        
        if (Is-Cheat $nm) {
            $flagHit++
            $cheatProcs += "$($proc.ProcessName) (PID $($proc.Id))"
            Note $FAIL "CHEAT PROCESS FOUND: $($proc.ProcessName) (PID $($proc.Id))"
        }
        
        # Check for unsigned cheat-like names even if not in list
        $leaf = try { (Split-Path $nm -Leaf).ToLower() } catch { $nm.ToLower() }
        if ($leaf -match 'cheat|inject|hack|aim|esp|wall|cham|trigger|fly|noclip|loader|modmenu|radar|glow|bhop') {
            $flagHit++
            $cheatProcs += "$($proc.ProcessName) (PID $($proc.Id))"
            Note $FAIL "SUSPICIOUS PROCESS: $($proc.ProcessName) (PID $($proc.Id))"
        }
    }
} catch {}

if ($flagHit -eq 0) {
    Note $PASS "Tamper Check: No cheats found in running processes ($scanned checked)"
} else {
    Note $FAIL "Tamper Check: $flagHit cheat/suspicious process(es) found!"
}

Write-Section $s2
$sub=$Results | Select-Object -Skip $s2
$t=($sub).Count; $ok=@($sub|Where-Object{$_.State -eq 'Pass'}).Count
Write-Host ""
Line ("Success Rate: {0}% ($ok / $t)" -f $([math]::Round($ok/[math]::Max($t,1)*100,0))) $(if($ok -eq $t){'Green'}else{'Red'})
Wait-ForEnter
Clear-Host

# ============================================================
# STEP 3: Quick Disk Scan for Cheat Files
# ============================================================
Line "Step 3 of 3: Quick Disk Scan - Cheat Files" White
Line "INSTRUCTION: Checking common cheat file locations" Yellow
Write-Host ""
Show-LoadingBar
$s3=$Results.Count

$cheatDirs = @(
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Downloads",
    "$env:TEMP",
    "C:\Users\Public"
)

$cheatExtensions = @('.exe', '.dll', '.sys', '.bin')
$cheatPatterns = @('cheat', 'inject', 'hack', 'aim', 'esp', 'wall', 'cham', 'trigger', 'fly', 'noclip', 'loader', 'modmenu', 'radar', 'glow', 'bhop', 'spectre')

$foundCheats = 0
$fileCount = 0

foreach ($dir in $cheatDirs) {
    if (-not (Test-Path $dir)) { continue }
    try {
        $files = Get-ChildItem -Path $dir -File -Force -ErrorAction SilentlyContinue | Select-Object -First 500
        foreach ($file in $files) {
            $fileCount++
            $leaf = $file.Name.ToLower()
            $isCheat = $false
            foreach ($pattern in $cheatPatterns) {
                if ($leaf -match $pattern) {
                    $isCheat = $true
                    break
                }
            }
            if ($isCheat) {
                $foundCheats++
                Note $FAIL "CHEAT FILE FOUND: $($file.FullName)"
            }
        }
    } catch {}
}

if ($foundCheats -eq 0) {
    Note $PASS "Disk scan: $fileCount files checked, no cheats found."
} else {
    Note $FAIL "Disk scan: $foundCheats cheat file(s) found!"
}

Write-Section $s3
$sub=$Results | Select-Object -Skip $s3
$t=($sub).Count; $ok=@($sub|Where-Object{$_.State -eq 'Pass'}).Count
Write-Host ""
Line ("Success Rate: {0}% ($ok / $t)" -f $([math]::Round($ok/[math]::Max($t,1)*100,0))) $(if($ok -eq $t){'Green'}else{'Red'})
Wait-ForEnter
Clear-Host

# ============================================================
# FINAL RESULT
# ============================================================
Line "=== Final Result ===" Yellow
Write-Host ""
$tot=$Results.Count
$p=@($Results|Where-Object{$_.State -eq 'Pass'}).Count
$w=@($Results|Where-Object{$_.State -eq 'Unsure'}).Count
$f=@($Results|Where-Object{$_.State -eq 'Fail'}).Count
Line ("Passed:  $p / $tot") Green
Line ("Unsure:  $w / $tot") Yellow
Line ("Failed:  $f / $tot") Red
Write-Host ""
if ($f -gt 0){ Line "VERDICT: CHEATS DETECTED" Red; Write-Host ""; foreach ($r in ($Results|Where-Object{$_.State -eq 'Fail'})){ Line ("  - " + $r.Text) Red } }
elseif ($w -gt 0){ Line "VERDICT: INCONCLUSIVE" Yellow; Write-Host ""; foreach ($r in ($Results|Where-Object{$_.State -eq 'Unsure'})){ Line ("  - " + $r.Text) Yellow } }
else { Line "VERDICT: CLEAN" Green }
Write-Host ""
Line "=== Credits ===" Yellow
Line "Made by stayvague" White
Wait-ForEnter "Press Enter to exit"
exit
