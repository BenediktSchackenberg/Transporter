# Eko-Modus: startet einen Claude-Code-Agenten als freies Wesen in der laufenden Partie (Idee nach Clawblox, MIT).
# Voraussetzung: Spiel laeuft mit --eko (Weltschnittstelle auf 127.0.0.1:8790), Claude Code ist installiert und angemeldet.
#
#   powershell -ExecutionPolicy Bypass -File tools\eko\start_eko.ps1 -Name Lumo
#   (weitere Wesen mit anderem -Name; Abbruch mit Strg+C, das Gedaechtnis bleibt im Arbeitsordner)
#
# Der Agent darf nur curl ausfuehren und Dateien in seinem Arbeitsordner lesen/schreiben (--allowedTools).
param(
    [string]$Name = "Lumo",
    [string]$Seele = "lumo",     # Persoenlichkeit aus tools\eko\seelen\<Seele>.md beim ersten Start ("" = neutrale Vorlage)
    [int]$Port = 8790,
    [string]$Model = "",
    [string]$Root = "$env:USERPROFILE\PixelTransportRivals-Eko",
    [int]$MaxRounds = 0          # 0 = endlos
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$base = "http://127.0.0.1:$Port"
$agentDir = Join-Path $Root $Name
$ws = Join-Path $agentDir "workspace"
$logs = Join-Path $agentDir "logs"
New-Item -ItemType Directory -Force $ws, $logs | Out-Null

# Gedaechtnis beim ersten Start aus der Vorlage anlegen (spaeter nie ueberschreiben)
foreach ($f in Get-ChildItem (Join-Path $here "vorlage")) {
    $dst = Join-Path $ws $f.Name
    if (-not (Test-Path $dst)) {
        Copy-Item $f.FullName $dst
        if ($f.Name -eq "SOUL.md" -and $Seele -ne "") { Copy-Item (Join-Path $here "seelen\$Seele.md") $dst -Force }
    }
}
$epi = Join-Path $ws "EPISODIC_MEMORY.jsonl"
if (-not (Test-Path $epi)) { New-Item -ItemType File $epi | Out-Null }

try { Invoke-WebRequest -UseBasicParsing "$base/api.md" -TimeoutSec 5 | Out-Null }
catch { Write-Error "Keine Weltschnittstelle unter $base. Spiel mit --eko starten (siehe README, Eko-Modus)."; exit 1 }

$prompt = (Get-Content -Raw -Encoding UTF8 (Join-Path $here "systemprompt.md")).Replace('${NAME}', $Name).Replace('${WORKSPACE}', $ws).Replace('${BASE}', $base)
$tools = @("Bash(curl:*)", "Read", "Write", "Edit", "Glob", "Grep")
$common = @("--append-system-prompt", $prompt, "--allowedTools") + $tools + @("--output-format", "text")
if ($Model -ne "") { $common += @("--model", $Model) }

Push-Location $ws
# Hinweise von claude auf stderr (z. B. Anmeldung laeuft bald ab) duerfen die Schleife nicht beenden (PowerShell 5.1)
$ErrorActionPreference = "Continue"
try {
    $round = 0
    $started = Test-Path (Join-Path $agentDir ".gestartet")
    while ($MaxRounds -eq 0 -or $round -lt $MaxRounds) {
        $round++
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        if ($started) {
            $msg = "Bitte nicht aufhören. Mach einfach weiter mit dem, was du tun möchtest."
            $out = & claude -c -p $msg @common 2>&1
        } else {
            $out = & claude -p "Beginne." @common 2>&1
            New-Item -ItemType File (Join-Path $agentDir ".gestartet") -Force | Out-Null
            $started = $true
        }
        $text = ($out | Out-String)
        Add-Content -Encoding UTF8 (Join-Path $logs "sitzung.log") "`n===== Runde $round ($stamp) =====`n$text"
        Write-Host "[$stamp] $Name, Runde ${round}:" -ForegroundColor Cyan
        Write-Host $text
        if ($LASTEXITCODE -ne 0) { Write-Warning "claude endete mit Code $LASTEXITCODE; neuer Versuch in 15 s."; Start-Sleep 15 }
    }
} finally { Pop-Location }
