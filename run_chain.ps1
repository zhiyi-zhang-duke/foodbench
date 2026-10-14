# Runs the FoodBench pilot on Gemma, Qwen3.8, and DeepSeek-R1 sequentially on GPU 0.
# Gemma judges every run.
#
# Safety: requires an Ollama server that sees ONLY GPU 0 (start it with
# C:\Users\Jack\start-ollama-gpu0.ps1), and runs gpu_watchdog.ps1 alongside, which kills
# everything if the display GPU fills up.
Set-Location $PSScriptRoot
$env:OLLAMA_HOST = "127.0.0.1:11600"
$env:OLLAMA_BASE_URL = "http://127.0.0.1:11600/v1"
$inspect = ".\.venv\Scripts\inspect.exe"

# --- Preflight: the running server must be the pinned GPU 0 server ---
$log = Join-Path $env:LOCALAPPDATA 'Ollama\server-gpu0.log'
$dev = @(Select-String -Path $log -Pattern 'inference compute' -ErrorAction SilentlyContinue | ForEach-Object { $_.Line })
$tray = Get-Process 'ollama app' -ErrorAction SilentlyContinue
if ($tray -or $dev.Count -eq 0 -or (($dev -join "`n") -match '04:00\.0|247d36d3|library=Vulkan')) {
  "=== PREFLIGHT FAILED: Ollama is not the GPU-0-only server. Run start-ollama-gpu0.ps1 first. $(Get-Date)"
  exit 1
}
"=== PREFLIGHT OK: Ollama sees GPU 0 only. $(Get-Date)"

# --- Watchdog on the display GPU ---
$wd = Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSScriptRoot\gpu_watchdog.ps1" -WindowStyle Hidden -PassThru
"watchdog pid $($wd.Id)"

$runs = @(
  @{ model = "gemma4:31b";      log = "logs/gemma-pilot";    extra = @() },
  @{ model = "qwen3.8:27b";     log = "logs/qwen-pilot";     extra = @("-T", "max_tokens=6000") },
  @{ model = "deepseek-r1:32b"; log = "logs/deepseek-pilot"; extra = @("-T", "max_tokens=8000") }
)
foreach ($r in $runs) {
  if ($wd.HasExited) { "=== WATCHDOG FIRED, stopping chain $(Get-Date)"; break }
  "=== START $($r.model) $(Get-Date)"
  Remove-Item -Recurse -Force $r.log -ErrorAction SilentlyContinue
  & $inspect eval tasks/pilot.py --model "ollama/$($r.model)" --model-role judge=ollama/gemma4:31b `
      --max-connections 1 --log-dir $r.log --display plain @($r.extra) 2>&1 | Tee-Object -FilePath "$($r.log).out.txt"
  "=== END $($r.model) $(Get-Date) exit=$LASTEXITCODE"
}
ollama stop gemma4:31b 2>$null; ollama stop deepseek-r1:32b 2>$null; ollama stop qwen3.8:27b 2>$null
New-Item -ItemType File -Force "$PSScriptRoot\logs\watchdog.stop" | Out-Null
"=== CHAIN DONE $(Get-Date)"
