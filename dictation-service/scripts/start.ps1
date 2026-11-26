# Starts Notchy's dictation service on Windows.
#
# First run: creates dictation-service\.venv and installs the service with the
# Qwen3-ASR Transformers extra. vLLM, and so streaming with partial text, has
# no native Windows build: for that, run scripts/start.sh inside WSL2 with an
# NVIDIA GPU, and point Notchy at the address it prints. The model weights
# (Qwen/Qwen3-ASR-1.7B, about 4.7 GB) download on the first start into the
# Hugging Face cache (%USERPROFILE%\.cache\huggingface).
#
# With an NVIDIA GPU, install PyTorch with CUDA first, then run this script:
#   .venv\Scripts\python -m pip install torch --index-url https://download.pytorch.org/whl/cu129
#
# Arguments go to the service: .\scripts\start.ps1 --port 8800 ; .\scripts\start.ps1 --check
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$Venv = if ($env:DICTATION_VENV) { $env:DICTATION_VENV } else { ".venv" }
$Extra = if ($env:DICTATION_EXTRA) { $env:DICTATION_EXTRA } else { "qwen" }
$Python = Join-Path $Venv "Scripts\python.exe"

if (-not (Test-Path $Python)) {
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($launcher) {
        & py -3.12 -m venv $Venv
        if ($LASTEXITCODE -ne 0) { & py -3 -m venv $Venv }
    } else {
        & python -m venv $Venv
    }
    if (-not (Test-Path $Python)) {
        Write-Error "Preciso do Python 3.10 ou mais novo (o Qwen3-ASR recomenda o 3.12): https://www.python.org/downloads/"
    }
    & $Python -m pip install --quiet --upgrade pip
}

$Marker = Join-Path $Venv ".installed-$Extra"
if (-not (Test-Path $Marker)) {
    Write-Host "Instalando o serviço com o extra [$Extra] (pode levar alguns minutos)…"
    & $Python -m pip install --upgrade -e ".[$Extra]"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    New-Item -ItemType File -Path $Marker | Out-Null
}

if (-not (Test-Path ".env")) {
    Write-Host "Sem .env: usando os padrões (copie .env.example para .env para mudar algo)."
}

& $Python -m notchy_dictation @args
exit $LASTEXITCODE
