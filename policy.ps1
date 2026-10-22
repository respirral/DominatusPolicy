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
$lockFile = Join-Path $env:ProgramData 'roman_hwid.json'

$locks = @{}
if (Test-Path $lockFile){
    try { (Get-Content $lockFile -Raw | ConvertFrom-Json) | ForEach-Object { $locks[$_.user] = $_.hwid } } catch { $locks = @{} }
}
function Save-Locks { param($tbl,$path)
    try { @($tbl.GetEnumerator() | ForEach-Object { [pscustomobject]@{ user=$_.Key; hwid=$_.Value } } | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8 } catch {}
}

Clear-Host
Line ""
Line "=== Roman Recording Policy - Login ===" Yellow
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
        Start-Sleep -Milliseconds 120
    }
    Write-Host ""; Write-Host ""
}

function Show-DownloadBar {
    for ($i=0; $i -le 20; $i++){
        $bar = "#"*$i + "-"*(20-$i)
        $pct = [math]::Round($i/20*100)
        Write-Host -NoNewline ("`rDownloading Process Explorer: [ $bar ] {0}% " -f $pct) -ForegroundColor Cyan
        Start-Sleep -Milliseconds 150
    }
    Write-Host ""; Write-Host ""
}

function Wait-ForEnter {
    param([string]$Message = "Press Enter to Continue")
    Start-Sleep -Seconds 1
    Line $Message Yellow
    while ($true){ if ([Console]::KeyAvailable){ if ([Console]::ReadKey($true).Key -eq 'Enter'){ break } } Start-Sleep -Milliseconds 100 }
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
function Fast-SigMicrosoft { param([string]$Path)
    if (-not $Path) { return $false }
    try { $s = Get-AuthenticodeSignature -FilePath $Path -ErrorAction SilentlyContinue; return ($s.Status -eq 'Valid' -and $s.SignerCertificate.Subject -match 'Microsoft') } catch { return $false }
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

$Flagged = @('spectre.exe','software.exe','tiworker.exe','loader.exe','injector.exe','bamparser.exe','svhost.exe','csrss32.exe')

function Test-Flagged { param([string]$P)
    if (-not $P) { return $false }
    $leaf = try { (Split-Path $P -Leaf).ToLower() } catch { $P.ToLower() }
    foreach ($f in $Flagged){
        if ($leaf -eq $f){
            if ($f -eq 'tiworker.exe'){
                if (-not (Test-Path $P -ErrorAction SilentlyContinue)){ return $false }
                if (Fast-SigMicrosoft $P){ return $false }
                return $true
            }
            return $true
        }
    }
    return $false }

Line ""
Line "=== Roman Recording Policy ===" Yellow
Line "Complete all steps with 100% success to pass." White
Line "Follow the instructions listed on each step." White
Line "This PowerShell policy currently has 5 steps." White
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
Line "Made by respiral" White
Write-Host ""
Wait-ForEnter
Clear-Host

Line "Step 1 of 5: Execution History" White
Line "INSTRUCTION: Reach 100% success" Yellow
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
            if (Test-Flagged $_.Name){ $bamHit++; Note $FAIL "BAM shows flagged program ran -> $(Split-Path $_.Name -Leaf) [last run $when]" }
        } } }
if ($bamN -eq 0){ Note $WARN "BAM has no execution records - cleared or missing." }
elseif ($bamN -lt 10){ Note $WARN "BAM only $bamN entries - suspiciously sparse." }
elseif ($bamHit -eq 0){ Note $PASS "BAM: $bamN entries, none flagged." }

$am="$env:SystemRoot\AppCompat\Programs\Amcache.hve"
if (Test-Path $am){ $kb=[int]((Get-Item $am -Force).Length/1KB); if ($kb -lt 256){ Note $WARN "Amcache only ${kb}KB - unusually small." } else { Note $PASS "Amcache present (${kb}KB)." } } else { Note $WARN "Amcache hive missing." }

$pfEnabled = try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name EnablePrefetcher -ErrorAction Stop).EnablePrefetcher } catch { $null }
if ($pfEnabled -eq 0){ Note $WARN "Prefetch disabled in registry." }
$pfDir="$env:SystemRoot\Prefetch"
if (Test-Path $pfDir){
    $pf=@(Get-ChildItem $pfDir -Filter *.pf -Force -ErrorAction SilentlyContinue); $pfHit=0
    foreach ($x in $pf){ $n=($x.BaseName -replace '-[0-9A-F]{8}$',''); if (Test-Flagged $n){ $pfHit++; Note $FAIL "Prefetch trace for $n [last run $($x.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))]" } }
    if ($pf.Count -eq 0){ Note $WARN "Prefetch folder empty - cleared." }
    elseif ($pf.Count -lt 20){ Note $WARN "Prefetch only $($pf.Count) files - likely wiped." }
    elseif ($pfHit -eq 0){ Note $PASS "Prefetch: $($pf.Count) traces, none flagged." }
} else { Note $WARN "Prefetch folder does not exist." }

try {
    $blob=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache' -Name AppCompatCache -ErrorAction Stop).AppCompatCache
    $txt=[Text.Encoding]::Unicode.GetString($blob); $scHit=0
    foreach ($f in $Flagged){ if ($f -eq 'tiworker.exe'){ continue }; if ($txt -match [regex]::Escape($f)){ $scHit++; Note $FAIL "ShimCache references $f" } }
    if ($scHit -eq 0){ Note $PASS "ShimCache: $([int]($blob.Length/1KB))KB swept, no flagged names." }
} catch { Note $WARN "ShimCache could not read AppCompatCache." }

$mui='HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'
if (Test-Path $mui){
    $mp=Get-ItemProperty $mui -ErrorAction SilentlyContinue; $mHit=0; $mN=0
    if ($mp){ $mp.PSObject.Properties | Where-Object { $_.Name -like '*.exe*' } | ForEach-Object { $mN++; if (Test-Flagged ($_.Name -replace '\.FriendlyAppName$','')){ $mHit++; Note $FAIL "MUICache launched -> $(Split-Path ($_.Name -replace '\.FriendlyAppName$','') -Leaf)" } } }
    if ($mHit -eq 0){ Note $PASS "MUICache: $mN entries, clean." }
} else { Note $WARN "MUICache key absent." }

$srum="$env:SystemRoot\System32\sru\SRUDB.dat"
if (Test-Path $srum){ $mb=[math]::Round((Get-Item $srum -Force).Length/1MB,1); if ($mb -lt 1){ Note $WARN "SRUM only ${mb}MB - likely reset." } else { Note $PASS "SRUM present (${mb}MB)." } } else { Note $WARN "SRUM SRUDB.dat missing." }

$hist="$env:APPDATA\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt"
if (Test-Path $hist){ $h=@(Get-Content $hist -ErrorAction SilentlyContinue); if ($h.Count -eq 0){ Note $WARN "PS history empty - cleared." } else { Note $PASS "PS history: $($h.Count) lines present." } } else { Note $WARN "PS history file missing." }

Write-Section $s1
$sub=$Results | Select-Object -Skip $s1
$t=($sub).Count; $ok=@($sub|Where-Object{$_.State -eq 'Pass'}).Count
Write-Host ""
Line ("Success Rate: {0}% ($ok / $t)" -f $([math]::Round($ok/[math]::Max($t,1)*100,0))) $(if($ok -eq $t){'Green'}else{'Red'})
Wait-ForEnter
Clear-Host

Line "Step 2 of 5: Persistence, Storage & Traces" White
Line "INSTRUCTION: Reach 100% success" Yellow
Write-Host ""
Show-LoadingBar
$s2=$Results.Count

try {
    $usn = & fsutil usn queryjournal C: 2>&1
    if ($LASTEXITCODE -ne 0 -or "$usn" -match 'not.*active|Error'){ Note $FAIL "USN journal disabled or deleted on C: - strong wipe indicator." }
    else { $m=([regex]'Maximum Size\s*:\s*(0x[0-9a-f]+)').Match("$usn"); $sz= if ($m.Success){ [Convert]::ToInt64($m.Groups[1].Value,16) } else { 0 }; if ($sz -gt 0 -and $sz -lt 32MB){ Note $WARN "USN journal active but only $([int]($sz/1MB))MB retained." } else { Note $PASS "USN journal active on C: ($([int]($sz/1MB))MB max)." } }
} catch { Note $WARN "USN journal query failed." }

foreach ($pair in @(@('Security',1102),@('System',104))){
    try { $ev=Get-WinEvent -FilterHashtable @{LogName=$pair[0];Id=$pair[1]} -MaxEvents 5 -ErrorAction Stop; foreach ($e in $ev){ Note $FAIL "Event log '$($pair[0])' CLEARED at $($e.TimeCreated.ToString('yyyy-MM-dd HH:mm'))" } }
    catch { Note $PASS "Event log: no clear events in '$($pair[0])'." }
}

$runKeys=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce')
$arHit=0; $arN=0
foreach ($k in $runKeys){
    if (-not (Test-Path $k)){ continue }
    $p=Get-ItemProperty $k -ErrorAction SilentlyContinue; if (-not $p){ continue }
    $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $arN++; $v="$($_.Value)"
        if (Test-Flagged $v){ $arHit++; Note $FAIL "Autorun flagged entry '$($_.Name)' -> $v" }
        else { $exe = if ($v -match '"([^"]+\.exe)"'){$matches[1]} elseif ($v -match '([A-Za-z]:\\[^ ]+\.exe)'){$matches[1]} else {$null}
            if ($exe -and (Test-Path $exe)){ if (-not (Fast-SigValid $exe)){ $arHit++; Note $WARN "Autorun unsigned startup '$($_.Name)' -> $exe" } } } } }
if ($arHit -eq 0){ Note $PASS "Autoruns: $arN Run/RunOnce entries, all clean." }

$stHit=0
foreach ($d in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup","$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")){
    if (Test-Path $d){ Get-ChildItem $d -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | ForEach-Object { if (Test-Flagged $_.Name){ $stHit++; Note $FAIL "Startup folder flagged -> $($_.FullName)" } } } }
if ($stHit -eq 0){ Note $PASS "Startup folders clean." }

try {
    $tasks=@(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' }); $tHit=0
    foreach ($t in $tasks){ foreach ($a in ($t.Actions|Where-Object{$_.Execute})){ if (Test-Flagged $a.Execute){ $tHit++; Note $FAIL "Task '$($t.TaskName)' runs flagged -> $($a.Execute)" } } }
    if ($tHit -eq 0){ Note $PASS "Scheduled tasks: $($tasks.Count) third-party, none flagged." }
} catch { Note $WARN "Scheduled tasks enumeration failed." }

$dl="$env:USERPROFILE\Downloads"
if (Test-Path $dl){
    $dHit=0; $dN=0
    Get-ChildItem $dl -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $dN++
        if (Test-Flagged $_.Name){ $dHit++; $src='unknown origin'; try { $z=Get-Content "$($_.FullName):Zone.Identifier" -ErrorAction SilentlyContinue; $hu=$z|Where-Object{$_ -like 'HostUrl=*'}|Select-Object -First 1; if ($hu){ $src=$hu -replace '^HostUrl=','' } } catch {}; Note $FAIL "Downloads flagged file '$($_.Name)' [from $src]" } }
    if ($dHit -eq 0){ Note $PASS "Downloads: $dN files, none flagged." }
} else { Note $WARN "Downloads folder missing." }

try {
    $rb=@(Get-ChildItem 'C:\$Recycle.Bin' -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer -and $_.Name -like '$R*' }); $rHit=0
    foreach ($x in $rb){ if (Test-Flagged $x.Name){ $rHit++; Note $FAIL "Recycle Bin flagged deleted file -> $($x.Name)" } }
    if ($rHit -eq 0){ Note $PASS "Recycle Bin: $($rb.Count) items, none flagged." }
} catch { Note $WARN "Recycle Bin could not enumerate." }

Write-Section $s2
$sub=$Results | Select-Object -Skip $s2
$t=($sub).Count; $ok=@($sub|Where-Object{$_.State -eq 'Pass'}).Count
Write-Host ""
Line ("Success Rate: {0}% ($ok / $t)" -f $([math]::Round($ok/[math]::Max($t,1)*100,0))) $(if($ok -eq $t){'Green'}else{'Red'})
Wait-ForEnter
Clear-Host

Line "Step 3 of 5: Live System & Defence Integrity" White
Line "INSTRUCTION: Reach 100% success" Yellow
Write-Host ""
Show-LoadingBar
$s3=$Results.Count

$pHit=0; $pN=0; $userProcs=@()
$procScanStart = Get-Date
foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)){
    $pN++; $path=$null
    try { $path = $proc.MainModule.FileName } catch { $path=$null }
    $nm = if ($path){ $path } else { "$($proc.ProcessName).exe" }
    if (Test-Flagged $nm){ $pHit++; Note $FAIL "Process flagged LIVE -> $($proc.ProcessName) (PID $($proc.Id)) $(if($path){"at $path"}else{'[path hidden]'})" }
    if ($path -and ($path -match '\\Temp\\|\\AppData\\|\\Downloads\\|\\Users\\Public\\')){ $userProcs += $path }
    if ((Get-Date) - $procScanStart -gt [TimeSpan]::FromSeconds(5)) { break }
}
if ($pHit -eq 0){ Note $PASS "Processes: $pN running, none flagged." }

$uHit=0
foreach ($up in ($userProcs | Select-Object -Unique)){ if (-not (Fast-SigValid $up)){ $uHit++; Note $WARN "Process unsigned binary from user space -> $up" } }
if ($uHit -eq 0){ Note $PASS "Processes: none unsigned from temp/user dirs." }

try {
    $pref=Get-MpPreference -ErrorAction Stop
    $ex=@(); $ex+=$pref.ExclusionPath; $ex+=$pref.ExclusionProcess; $ex+=$pref.ExclusionExtension; $ex+=$pref.ExclusionIpAddress; $ex=$ex|Where-Object{$_}
    if ($ex.Count){ foreach($e in $ex){ Note $FAIL "Defender exclusion set -> $e" } } else { Note $PASS "Defender: no exclusions of any type." }
} catch { Note $WARN "Defender could not read exclusions." }

$exR='HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions'
if (Test-Path $exR){
    $rHit=0
    Get-ChildItem $exR -ErrorAction SilentlyContinue | ForEach-Object { $p=Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue; if ($p){ $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $rHit++; Note $FAIL "Defender registry exclusion -> $($_.Name)" } } }
    if ($rHit -eq 0){ Note $PASS "Defender registry exclusions empty." }
} else { Note $PASS "Defender no exclusion registry keys." }

try {
    $st=Get-MpComputerStatus -ErrorAction Stop
    if ($st.RealTimeProtectionEnabled){ Note $PASS "Defender real-time protection ON." } else { Note $FAIL "Defender real-time protection OFF." }
    if ($st.AntivirusEnabled){ Note $PASS "Defender antivirus engine enabled." } else { Note $FAIL "Defender antivirus engine disabled." }
    if ($st.IsTamperProtected){ Note $PASS "Defender tamper protection ON." } else { Note $WARN "Defender tamper protection OFF." }
    $age=[int]$st.AntivirusSignatureAge; if ($age -le 7){ Note $PASS "Defender signatures $age day(s) old." } else { Note $WARN "Defender signatures $age days old - stale." }
} catch { Note $WARN "Defender status query failed." }

try {
    $bcd = & bcdedit /enum "{current}" 2>&1 | Out-String
    if ($bcd -match 'testsigning\s+Yes'){ Note $FAIL "Boot test signing enabled." } else { Note $PASS "Boot test signing off." }
    if ($bcd -match 'nointegritychecks\s+Yes'){ Note $FAIL "Boot integrity checks disabled." } else { Note $PASS "Boot integrity checks on." }
    if ($bcd -match 'debug\s+Yes'){ Note $WARN "Boot kernel debugging enabled." } else { Note $PASS "Boot kernel debugging off." }
} catch { Note $WARN "Boot bcdedit read failed." }

try {
    $hv=Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -ErrorAction Stop
    if ($hv -eq 1){ Note $PASS "Memory Integrity (HVCI) ON." } else { Note $WARN "Memory Integrity (HVCI) OFF." }
} catch { Note $WARN "Memory Integrity not supported or unreadable." }

try {
    $drv=@(Get-CimInstance Win32_SystemDriver -ErrorAction Stop | Where-Object { $_.State -eq 'Running' }); $dHit=0
    foreach ($d in $drv){ $pp=$d.PathName -replace '^\\\??\\',''; if ($pp -and (Test-Path $pp -ErrorAction SilentlyContinue)){ if (-not (Fast-SigValid $pp)){ $dHit++; Note $WARN "Driver invalid signature -> $($d.Name)" } } }
    if ($dHit -eq 0){ Note $PASS "Drivers: $($drv.Count) running, all validly signed." }
} catch { Note $WARN "Drivers enumeration failed." }

Write-Section $s3
$sub=$Results | Select-Object -Skip $s3
$t=($sub).Count; $ok=@($sub|Where-Object{$_.State -eq 'Pass'}).Count
Write-Host ""
Line ("Success Rate: {0}% ($ok / $t)" -f $([math]::Round($ok/[math]::Max($t,1)*100,0))) $(if($ok -eq $t){'Green'}else{'Red'})
Wait-ForEnter
Clear-Host

Line "Step 4 of 5: Live PC Search" White
Line "INSTRUCTION: Reach 100% success" Yellow
Write-Host ""
$s4=$Results.Count

# Keywords: ESP and Aimbot.
# ESP is matched only as its own word (not inside "response", "respawn", "despawn", etc.)
# but still catches "ESP=1", "esp_enabled", "[ESP]", "ESPEnabled". Aimbot is matched anywhere, any case.
$cfgPattern = '(?<![A-Za-z])[Ee][Ss][Pp](?![a-z])|(?i:aimbot)'
$cfgBudgetSec = 10

# Multi-threaded file walker: searches every fixed drive for .cfg files and checks their text,
# stopping at the time limit. Read-only.
if (-not ('RomanCfgScan2' -as [type])) {
    try {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading;

public static class RomanCfgScan2 {
    static ConcurrentStack<DirectoryInfo> work;
    static ConcurrentBag<string> hits;
    static Regex rx;
    static HashSet<string> skipPaths;
    static HashSet<string> skipNames;
    static Thread[] threads;
    static DateTime deadline;
    static int busy;
    static long dirs;
    static long cfgs;
    static int timedOut;

    public static long DirsScanned { get { return Interlocked.Read(ref dirs); } }
    public static long CfgChecked { get { return Interlocked.Read(ref cfgs); } }
    public static bool TimedOut { get { return Interlocked.CompareExchange(ref timedOut, 0, 0) == 1; } }

    public static bool IsDone {
        get {
            if (threads == null) return true;
            foreach (Thread t in threads) { if (t.IsAlive) return false; }
            return true;
        }
    }

    public static string[] Results() {
        string[] a = hits.ToArray();
        Array.Sort(a, StringComparer.OrdinalIgnoreCase);
        return a;
    }

    public static void Start(string[] roots, string pattern, int budgetMs, string[] skipPathList, string[] skipNameList) {
        work = new ConcurrentStack<DirectoryInfo>();
        hits = new ConcurrentBag<string>();
        rx = new Regex(pattern, RegexOptions.Compiled);
        skipPaths = new HashSet<string>(skipPathList, StringComparer.OrdinalIgnoreCase);
        skipNames = new HashSet<string>(skipNameList, StringComparer.OrdinalIgnoreCase);
        busy = 0; dirs = 0; cfgs = 0; timedOut = 0;
        deadline = DateTime.UtcNow.AddMilliseconds(budgetMs);
        foreach (string r in roots) { try { work.Push(new DirectoryInfo(r)); } catch { } }
        int n = Math.Max(4, Math.Min(32, Environment.ProcessorCount * 2));
        threads = new Thread[n];
        for (int i = 0; i < n; i++) {
            threads[i] = new Thread(Worker);
            threads[i].IsBackground = true;
            threads[i].Start();
        }
    }

    static bool OutOfTime() {
        if (DateTime.UtcNow > deadline) { Interlocked.Exchange(ref timedOut, 1); return true; }
        return false;
    }

    static void Worker() {
        while (true) {
            if (OutOfTime()) return;
            Interlocked.Increment(ref busy);
            DirectoryInfo dir;
            if (!work.TryPop(out dir)) {
                Interlocked.Decrement(ref busy);
                if (Interlocked.CompareExchange(ref busy, 0, 0) == 0 && work.IsEmpty) return;
                Thread.Sleep(1);
                continue;
            }
            try { Scan(dir); } catch { }
            Interlocked.Decrement(ref busy);
        }
    }

    static void Scan(DirectoryInfo dir) {
        Interlocked.Increment(ref dirs);
        try {
            foreach (FileInfo f in dir.EnumerateFiles("*.cfg")) {
                if (OutOfTime()) return;
                if (!f.Name.EndsWith(".cfg", StringComparison.OrdinalIgnoreCase)) continue;
                Interlocked.Increment(ref cfgs);
                if (Check(f)) hits.Add(f.FullName);
            }
        } catch { }
        try {
            foreach (DirectoryInfo d in dir.EnumerateDirectories()) {
                if ((d.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                if (skipNames.Contains(d.Name) || skipPaths.Contains(d.FullName)) continue;
                work.Push(d);
            }
        } catch { }
    }

    static bool Check(FileInfo f) {
        try {
            if (f.Length <= 0 || f.Length > 10L * 1024 * 1024) return false;
            using (FileStream fs = new FileStream(f.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (StreamReader sr = new StreamReader(fs, true)) {
                return rx.IsMatch(sr.ReadToEnd());
            }
        } catch { return false; }
    }
}
'@
    } catch { }
}

function Show-CfgProgress { param([int]$Pct)
    $filled = [int][math]::Floor($Pct / 5)
    $bar = "#"*$filled + "-"*(20-$filled)
    $msg = "`rSearching for .cfg files: [ $bar ] {0}%  | {1:N0} folders | {2:N0} .cfg files checked" -f $Pct, [RomanCfgScan2]::DirsScanned, [RomanCfgScan2]::CfgChecked
    Write-Host -NoNewline ($msg.PadRight(110)) -ForegroundColor Cyan
}

if ('RomanCfgScan2' -as [type]) {
    $roots = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName })
    # Huge Windows component stores that never hold user configs (skipped for speed).
    $skipPaths = @('WinSxS','Installer','servicing','SoftwareDistribution','assembly','Microsoft.NET','System32\DriverStore') | ForEach-Object { Join-Path $env:SystemRoot $_ }
    $skipNames = @('System Volume Information','node_modules','.git')

    [RomanCfgScan2]::Start([string[]]$roots, $cfgPattern, $cfgBudgetSec * 1000, [string[]]$skipPaths, [string[]]$skipNames)
    $cfgSw = [Diagnostics.Stopwatch]::StartNew()
    while (-not [RomanCfgScan2]::IsDone -and $cfgSw.Elapsed.TotalSeconds -lt ($cfgBudgetSec + 2)) {
        Show-CfgProgress ([math]::Min(99, [int]($cfgSw.Elapsed.TotalSeconds / $cfgBudgetSec * 100)))
        Start-Sleep -Milliseconds 100
    }
    Show-CfgProgress 100
    Write-Host ""; Write-Host ""

    $cfgHits = @([RomanCfgScan2]::Results())
    foreach ($h in $cfgHits){ Note $FAIL "$([IO.Path]::GetFileName($h)) has been found." }
    if ([RomanCfgScan2]::TimedOut){
        Note $WARN ("Live PC Search: stopped at the {0} second limit ({1:N0} folders searched)." -f $cfgBudgetSec, [RomanCfgScan2]::DirsScanned)
    } elseif ($cfgHits.Count -eq 0){
        Note $PASS "Live PC Search: no flagged .cfg files."
    }
} else {
    Note $WARN "Live PC Search: search engine could not start."
}

Write-Section $s4
$sub=$Results | Select-Object -Skip $s4
$t=($sub).Count; $ok=@($sub|Where-Object{$_.State -eq 'Pass'}).Count
Write-Host ""
Line ("Success Rate: {0}% ($ok / $t)" -f $([math]::Round($ok/[math]::Max($t,1)*100,0))) $(if($ok -eq $t){'Green'}else{'Red'})
Wait-ForEnter
Clear-Host

Line "Step 5 of 5: Tamper Check" White
Line "INSTRUCTION: Process Explorer will be downloaded and opened" Yellow
Write-Host ""

$tempDir = Join-Path $env:TEMP "ProcessExplorer"
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

$procExpZip = Join-Path $tempDir "procexp.zip"
$procExpExe = Join-Path $tempDir "procexp.exe"
$procExp64Exe = Join-Path $tempDir "procexp64.exe"

$downloadUrl = "https://live.sysinternals.com/procexp64.exe"
$downloadUrlZip = "https://live.sysinternals.com/ProcessExplorer.zip"

Line "Downloading Process Explorer..." White
Show-DownloadBar

$webClient = New-Object System.Net.WebClient
try {
    $webClient.DownloadFile($downloadUrl, $procExp64Exe)
    Line "Download complete." Green
} catch {
    try {
        $webClient.DownloadFile($downloadUrlZip, $procExpZip)
        Line "Downloaded zip. Extracting..." Yellow
        Expand-Archive -Path $procExpZip -DestinationPath $tempDir -Force
        Line "Extraction complete." Green
    } catch {
        Line "Download failed. Please download manually from Sysinternals." Red
        Wait-ForEnter
        Clear-Host
        Line "=== Roman Recording Policy - Complete ===" Yellow
        Write-Host ""
        Line "=== Credits ===" Yellow
        Line "Made by respiral" White
        Wait-ForEnter "Press Enter to exit"
        exit
    }
}

$procExpPath = $null
if (Test-Path $procExp64Exe) { $procExpPath = $procExp64Exe }
elseif (Test-Path $procExpExe) { $procExpPath = $procExpExe }

if ($procExpPath -and (Test-Path $procExpPath)) {
    try {
        $procExp = Start-Process -FilePath $procExpPath -PassThru -ErrorAction Stop
        Line "Process Explorer opened successfully (PID: $($procExp.Id))" Green
        Line ""
        Wait-ForEnter "Press Enter to finish"
        Note $PASS "Process Explorer opened and visual inspection performed."
    } catch {
        Line "Failed to start Process Explorer." Red
        Note $WARN "Process Explorer could not be opened."
    }
} else {
    Line "Process Explorer executable not found after download." Red
    Note $WARN "Process Explorer download failed."
}

Clear-Host
Line "=== Roman Recording Policy - Complete ===" Yellow
Write-Host ""
Line "=== Credits ===" Yellow
Line "Made by respiral" White
Wait-ForEnter "Press Enter to exit"
exit
