[CmdletBinding()]
param(
    [int[]]$Seeds = @(1, 2, 3),
    [int]$Shots = 16,
    [string[]]$Datasets = @("caltech101", "dtd", "eurosat", "oxford_flowers", "oxford_pets"),
    [string]$Trainer = "HiCroPL",
    [string]$Cfg = "vit_b16_c2_ep50_batch32_16ctx",
    [int[]]$Lambdas = @(11, 12, 13, 14, 15),
    [string]$PythonExe = "python",
    [string]$DataRoot = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$Runner = Join-Path $RepoRoot "run_benchmark_5datasets_hicropl.ps1"

if (-not (Test-Path -LiteralPath $Runner)) {
    throw "Benchmark runner not found: $Runner"
}

foreach ($Dataset in $Datasets) {
    $AggregateSummaryFile = "benchmark_5datasets_hicropl__${Dataset}__image12distill_lambda_sweep.txt"
    $AggregateSummaryPath = Join-Path $RepoRoot $AggregateSummaryFile

    @(
        "HiCroPL image 12-layer cosine distill lambda sweep",
        "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Dataset: $Dataset",
        "Seeds: $($Seeds -join ', ')",
        "Shots: $Shots",
        "Trainer: $Trainer",
        "Cfg: $Cfg",
        "Teacher LN mode: none",
        "Lambdas: $($Lambdas -join ', ')",
        ""
    ) | Set-Content -Path $AggregateSummaryPath

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "Dataset sweep start: $Dataset" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow

    foreach ($Lambda in $Lambdas) {
        $RunTag = "image12distill_lambda$Lambda"
        $SummaryFile = "benchmark_5datasets_hicropl__${Dataset}__image12distill_lambda$Lambda.txt"

        Write-Host ""
        Write-Host "------------------------------------------" -ForegroundColor Cyan
        Write-Host "Dataset=$Dataset | Image 12-layer cosine distill | lambda=$Lambda" -ForegroundColor Cyan
        Write-Host "------------------------------------------" -ForegroundColor Cyan

        & $Runner `
            -Seeds $Seeds `
            -Shots $Shots `
            -Datasets $Dataset `
            -Trainer $Trainer `
            -Cfg $Cfg `
            -TeacherLnMode none `
            -ImageLayerDistill `
            -LossLambda $Lambda `
            -RunTag $RunTag `
            -PythonExe $PythonExe `
            -DataRoot $DataRoot `
            -SummaryFile $SummaryFile

        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }

        Add-Content -Path $AggregateSummaryPath -Value "=========================================="
        Add-Content -Path $AggregateSummaryPath -Value "Lambda: $Lambda"
        Add-Content -Path $AggregateSummaryPath -Value "Summary file: $SummaryFile"
        Add-Content -Path $AggregateSummaryPath -Value "------------------------------------------"
        Get-Content -Path (Join-Path $RepoRoot $SummaryFile) | Add-Content -Path $AggregateSummaryPath
        Add-Content -Path $AggregateSummaryPath -Value ""
    }
}
