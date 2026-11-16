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
    [int]$StartHaeuser = -1,       # neue Partie: hoechstens so viele Wohnhaeuser je Startort (die Orte wachsen dann selbst)
    [int]$TagSekunden = -1,        # neue Partie: Laenge eines Spieltags in Sim-Sekunden (Standard 60; Eko empfohlen 600)
    [int]$Tempo = 2,               # neue Partie: Spielgeschwindigkeit 1/2/4/8/16 (Autotest-Standard waere 16 – zu schnell fuer denkende Wesen)
    [string]$Modell = "hf.co/6block/Qwen3.8-27B-GGUF:IQ3_M",   # Modell der Wesen (Ollama); Benedikt 16.11.: Qwen 27B lokal
    [int]$Ctx = 0                  # Kontextfenster der Wesen (0 = Standard des Schwarms)
)
$ErrorActionPreference = "Continue"
$logs = Join-Path $env:USERPROFILE "PixelTransportRivals-Eko\welt"
New-Item -ItemType Directory -Force $logs | Out-Null
$eko = @("--eko-spieler", "--eko-endlos", "--eko-folgen", "--eko-modell=$Modell")
if ($Ctx -gt 0) { $eko += "--eko-ctx=$Ctx" }
$args0 = @("--path", $Projekt, "--", "--autotest", "--speed=$Tempo") + $eko
if ($StartHaeuser -ge 0) { $args0 += "--start-haeuser=$StartHaeuser" }
if ($TagSekunden -gt 0) { $args0 += "--tag-sekunden=$TagSekunden" }
if (-not $NeuePartie) { $args0 = @("--path", $Projekt, "--", "--autotest", "--load") + $eko }
$runs = 0
while ($true) {
    $runs++
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $out = Join-Path $logs "welt_$stamp.log"
    Write-Host "[$stamp] Welt startet (Lauf $runs) ..." -ForegroundColor Cyan
    $p = Start-Process -FilePath $Godot -ArgumentList $args0 -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    $p.WaitForExit()
    $crash = (Select-String -Path $out, "$out.err" -Pattern "FATAL|CrashHandler" -Quiet)
    $ende = Get-Date -Format "HH:mm:ss"
    if ($crash) {
        Write-Host "[$ende] Absturz erkannt - Neustart aus dem letzten Spielstand in 5 s (Protokoll: $out)" -ForegroundColor Yellow
        Add-Content (Join-Path $logs "abstuerze.txt") "$stamp bis $ende : $out"
    } else {
        Write-Host "[$ende] Welt beendet (Code $($p.ExitCode)). Neustart in 5 s, Strg+C zum Beenden." -ForegroundColor Gray
    }
    $args0 = @("--path", $Projekt, "--", "--autotest", "--load") + $eko   # danach immer aus dem Spielstand
    Start-Sleep -Seconds 5
}
