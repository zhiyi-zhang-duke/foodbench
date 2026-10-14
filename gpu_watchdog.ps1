# gpu_watchdog.ps1
# Kills Ollama and Inspect if the DISPLAY GPU (GPU 1, UUID 247d36d3) takes on model-sized
# memory. Sustained inference on that card blue-screened Jarvis (VIDEO_TDR_FAILURE) on
# 2026-10-14. Runs until -StopFile appears.
param(
  [int]$LimitMiB = 8000,
  [string]$StopFile = "$PSScriptRoot\logs\watchdog.stop",
  [string]$Log = "$PSScriptRoot\logs\watchdog.log"
)
Remove-Item $StopFile -ErrorAction SilentlyContinue
"watchdog start $(Get-Date) limit=${LimitMiB}MiB" | Out-File -Append $Log
while (-not (Test-Path $StopFile)) {
  $used = nvidia-smi --id=GPU-247d36d3-977d-102f-9735-a256a923c592 --query-gpu=memory.used --format=csv,noheader,nounits 2>$null
  if ($used -and [int]$used -gt $LimitMiB) {
    "ABORT $(Get-Date): display GPU at ${used}MiB. Killing Ollama and Inspect." | Out-File -Append $Log
    Get-Process 'ollama app','ollama','llama-server','inspect' -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'run_chain.ps1' } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    break
  }
  Start-Sleep -Seconds 3
}
"watchdog stop $(Get-Date)" | Out-File -Append $Log
