# Runs the FoodBench pilot on Gemma, Qwen3.8, and DeepSeek-R1 sequentially on GPU 0.
# Waits for pulls and the D: move to finish first. Gemma judges every run.
Set-Location $PSScriptRoot
$env:OLLAMA_HOST = "127.0.0.1:11600"
$env:OLLAMA_BASE_URL = "http://127.0.0.1:11600/v1"
$inspect = ".\.venv\Scripts\inspect.exe"

function Have($name) { (ollama list 2>$null) -match [regex]::Escape($name) }
"waiting for pulls..."
while (-not ((Have "qwen3.8:27b") -and (Have "deepseek-r1:32b"))) { Start-Sleep 30 }
while (Test-Path "$env:USERPROFILE\.ollama\models\manifests\hf.co\huihui-ai") { "waiting for D: move..."; Start-Sleep 30 }
"all models present: $(Get-Date)"

$runs = @(
  @{ model = "gemma4:31b";     log = "logs/gemma-pilot";    extra = @() },
  @{ model = "qwen3.8:27b";    log = "logs/qwen-pilot";     extra = @("-T", "max_tokens=6000") },
  @{ model = "deepseek-r1:32b"; log = "logs/deepseek-pilot"; extra = @("-T", "max_tokens=8000") }
)
foreach ($r in $runs) {
  "=== START $($r.model) $(Get-Date)"
  Remove-Item -Recurse -Force $r.log -ErrorAction SilentlyContinue
  & $inspect eval tasks/pilot.py --model "ollama/$($r.model)" --model-role judge=ollama/gemma4:31b `
      --max-connections 1 --log-dir $r.log --display plain @($r.extra) 2>&1 | Tee-Object -FilePath "$($r.log).out.txt"
  "=== END $($r.model) $(Get-Date) exit=$LASTEXITCODE"
}
ollama stop gemma4:31b 2>$null; ollama stop deepseek-r1:32b 2>$null; ollama stop qwen3.8:27b 2>$null
"=== CHAIN DONE $(Get-Date)"
