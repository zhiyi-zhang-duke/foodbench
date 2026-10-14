# Repair pass after the 2026-10-14 pilot: the judge's 300-token cap was eaten by Gemma 4's
# hidden reasoning, so most verdicts came back empty. The scorer now sets
# reasoning_effort="none" with a 1500-token cap.
#   1. Re-judge the existing Qwen and DeepSeek recipes (no regeneration; scored copies are new files).
#   2. Rerun Gemma end to end with the same 6000-token generation budget as the others.
# Same safety as run_chain.ps1: GPU-0-only preflight plus the display-GPU watchdog.
param([switch]$RescoreOnly)
Set-Location $PSScriptRoot
$env:OLLAMA_HOST = "127.0.0.1:11600"
$env:OLLAMA_BASE_URL = "http://127.0.0.1:11600/v1"
$inspect = ".\.venv\Scripts\inspect.exe"

$log = Join-Path $env:LOCALAPPDATA 'Ollama\server-gpu0.log'
$dev = @(Select-String -Path $log -Pattern 'inference compute' -ErrorAction SilentlyContinue | ForEach-Object { $_.Line })
$tray = Get-Process 'ollama app' -ErrorAction SilentlyContinue
if ($tray -or $dev.Count -eq 0 -or (($dev -join "`n") -match '04:00\.0|247d36d3|library=Vulkan')) {
  "=== PREFLIGHT FAILED: Ollama is not the GPU-0-only server. $(Get-Date)"; exit 1
}
"=== PREFLIGHT OK $(Get-Date)"
$wd = Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSScriptRoot\gpu_watchdog.ps1" -WindowStyle Hidden -PassThru

foreach ($d in @("qwen", "deepseek")) {
  if ($wd.HasExited) { "=== WATCHDOG FIRED $(Get-Date)"; exit 1 }
  $src = Get-ChildItem "logs/$d-pilot/*.eval" | Where-Object { $_.Name -notmatch 'rescored' } | Sort-Object LastWriteTime | Select-Object -Last 1
  $dst = Join-Path $src.DirectoryName ($src.BaseName + "-rescored.eval")
  Copy-Item $src.FullName $dst -Force   # originals stay untouched; score the copy in place
  "=== START rescore $d $(Get-Date) ($($src.Name))"
  & $inspect score $dst --model-role judge=ollama/gemma4:31b --action overwrite --overwrite --display plain 2>&1 | Tee-Object -FilePath "logs/$d-rescore.out.txt"
  "=== END rescore $d $(Get-Date) exit=$LASTEXITCODE"
}

if (-not $RescoreOnly -and -not $wd.HasExited) {
  "=== START gemma rerun $(Get-Date)"
  Remove-Item -Recurse -Force logs/gemma-pilot -ErrorAction SilentlyContinue
  & $inspect eval tasks/pilot.py --model ollama/gemma4:31b --model-role judge=ollama/gemma4:31b `
      --max-connections 1 --log-dir logs/gemma-pilot --display plain 2>&1 | Tee-Object -FilePath logs/gemma-pilot.out.txt
  "=== END gemma rerun $(Get-Date) exit=$LASTEXITCODE"
}
ollama stop gemma4:31b 2>$null; ollama stop qwen3.8:27b 2>$null; ollama stop deepseek-r1:32b 2>$null
New-Item -ItemType File -Force "$PSScriptRoot\logs\watchdog.stop" | Out-Null
"=== REPAIR DONE $(Get-Date)"
