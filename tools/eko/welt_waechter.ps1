# Eko-Welt-Waechter: startet die Welt aus dem letzten Spielstand und nach einem Absturz automatisch neu.
# Hintergrund: ungeklaerter Engine-Absturz ("FATAL: Index p_index = 1 is out of bounds", siehe STATUS.md seit 03.11.).
# Im Wesen-Modus speichert das Spiel alle 3 Minuten; die Wesen (eko_schwarm.py) melden sich nach dem Neustart selbst wieder an.
#
#   powershell -ExecutionPolicy Bypass -File tools\eko\welt_waechter.ps1
#   (Abbruch mit Strg+C; je Lauf ein Protokoll in %USERPROFILE%\PixelTransportRivals-Eko\welt\)
param(
    [string]$Godot = "C:\Users\Benedikt\Tools\godot441\Godot_v4.4.1-stable_win64_console.exe",
    [string]$Projekt = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..")).Path,
    [switch]$NeuePartie,           # ohne Spielstand starten (neue Partie mit Wesen, neuer Zufalls-Seed)
    [switch]$Wildnis,              # neue Partie ohne Staedte: jede KI sucht ihren Platz und gruendet ihre Siedlung (Benedikt 17.11.)
    [int]$Spieler = 4,             # neue Partie: Zahl der KI-Unternehmer (Benedikt 18.11.: erst mit 2 starten)
    [int]$StartHaeuser = -1,       # neue Partie: hoechstens so viele Wohnhaeuser je Startort (die Orte wachsen dann selbst)
    [int]$TagSekunden = -1,        # neue Partie: Laenge eines Spieltags in Sim-Sekunden (Standard 60; Eko empfohlen 600)
    [int]$Tempo = 2,               # neue Partie: Spielgeschwindigkeit 1/2/4/8/16 (Autotest-Standard waere 16 – zu schnell fuer denkende Wesen)
    [string]$Modell = "qwen3.5:9b-q4_K_M",   # Modell der Wesen (Ollama); Benedikt 19.11.: nur noch qwen3.5:9b (vorher Qwen 27B, Grafikspeicher voll)
    [int]$Ctx = 0                  # Kontextfenster der Wesen (0 = Standard des Schwarms)
)
$ErrorActionPreference = "Continue"
$logs = Join-Path $env:USERPROFILE "PixelTransportRivals-Eko\welt"
New-Item -ItemType Directory -Force $logs | Out-Null
$eko = @("--eko-spieler", "--eko-endlos", "--eko-folgen", "--eko-modell=$Modell")
if ($Ctx -gt 0) { $eko += "--eko-ctx=$Ctx" }
$args0 = @("--path", $Projekt, "--", "--autotest", "--speed=$Tempo", "--players=$Spieler") + $eko
if ($StartHaeuser -ge 0) { $args0 += "--start-haeuser=$StartHaeuser" }
if ($TagSekunden -gt 0) { $args0 += "--tag-sekunden=$TagSekunden" }
if ($Wildnis) { $args0 += "--wildnis" }
if (-not $NeuePartie) { $args0 = @("--path", $Projekt, "--", "--autotest", "--load") + $eko }
$runs = 0
while ($true) {
    $runs++
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $out = Join-Path $logs "welt_$stamp.log"
    Write-Host "[$stamp] Welt startet (Lauf $runs) ..." -ForegroundColor Cyan
    $p = Start-Process -FilePath $Godot -ArgumentList $args0 -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    # 18.11.2026: Grafiktreiber-Absturz (NVIDIA TDR) beendete nur das Spielfenster, der Konsolen-Starter lief weiter und der
    # Waechter wartete ewig. Daher das Lebenszeichen des Spiels (user://logs/zuletzt.txt, alle 25 ms) pruefen.
    $beat = Join-Path $env:APPDATA "Godot\app_userdata\Pixel Transport Rivals\logs\zuletzt.txt"
    $started = Get-Date
    $stale = $false
    while (-not $p.WaitForExit(10000)) {
        # 19.11.2026: Absturz 34 s nach dem Start - der Konsolen-Starter blieb nach dem CrashHandler haengen, die
        # Lebenszeichen-Pruefung griff erst nach 3 min. Ein Absturzbericht im Protokoll beendet die Reste sofort.
        if ((Test-Path "$out.err") -and (Select-String -Path "$out.err" -Pattern "CrashHandlerException" -Quiet)) {
            Write-Host "[$(Get-Date -Format HH:mm:ss)] Absturzbericht im Protokoll - beende Reste." -ForegroundColor Yellow
            Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'Godot*' -or ($_.Name -like 'python*' -and $_.CommandLine -match 'eko_') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            break
        }
        if (((Get-Date) - $started).TotalSeconds -lt 180 -or -not (Test-Path $beat)) { continue }
        if (((Get-Date) - (Get-Item $beat).LastWriteTime).TotalSeconds -gt 120) {
            $stale = $true
            Write-Host "[$(Get-Date -Format HH:mm:ss)] Kein Lebenszeichen seit 2 min - Spiel haengt oder ist abgestuerzt, beende Reste." -ForegroundColor Yellow
            Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'Godot*' -or ($_.Name -like 'python*' -and $_.CommandLine -match 'eko_') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            break
        }
    }
    $crash = $stale -or (Select-String -Path $out, "$out.err" -Pattern "FATAL|CrashHandler" -Quiet)
    $ende = Get-Date -Format "HH:mm:ss"
    if ($crash) {
        Write-Host "[$ende] Absturz erkannt - Neustart aus dem letzten Spielstand in 5 s (Protokoll: $out)" -ForegroundColor Yellow
        Add-Content (Join-Path $logs "abstuerze.txt") "$stamp bis $ende : $out"
        # 18.11.: Brotkrume (letzte Markierungen des Hauptthreads, auch welche Zeichenebene) vor dem Neustart sichern
        if (Test-Path $beat) { Copy-Item $beat (Join-Path $logs "absturz_${stamp}_zuletzt.txt") -Force }
        $hang = Join-Path (Split-Path $beat) "haenger.txt"
        if (Test-Path $hang) { Get-Content $hang -Tail 8 | Add-Content (Join-Path $logs "absturz_${stamp}_zuletzt.txt") }
    } else {
        Write-Host "[$ende] Welt beendet (Code $($p.ExitCode)). Neustart in 5 s, Strg+C zum Beenden." -ForegroundColor Gray
    }
    $args0 = @("--path", $Projekt, "--", "--autotest", "--load") + $eko   # danach immer aus dem Spielstand
    Start-Sleep -Seconds 5
}
