[CmdletBinding()]
param(
    [int[]]$Seeds = @(1, 2, 3),
    [int]$Shots = 16,
    [string[]]$Datasets = @("caltech101", "dtd", "eurosat", "oxford_flowers", "oxford_pets"),
    [string]$Trainer = "HiCroPL",
    [string]$Cfg = "vit_b16_c2_ep50_batch32_16ctx",
    [double[]]$Lambdas = @(12),
    [ValidateSet("cosine", "l1", "mse")]
    [string[]]$LossModes = @("cosine", "l1", "mse"),
    [double[]]$ImageLayerDistillWeights = @(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0),
    [int]$ImageLayerDistillLastN = 12,
    [int]$NumWorkers = 0,
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
    $AggregateSummaryFile = "benchmark_5datasets_hicropl__${Dataset}__image12distill_lambda_loss_sweep.txt"
    $AggregateSummaryPath = Join-Path $RepoRoot $AggregateSummaryFile

    @(
        "HiCroPL image 12-layer distill loss sweep",
        "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Dataset: $Dataset",
        "Seeds: $($Seeds -join ', ')",
        "Shots: $Shots",
        "Trainer: $Trainer",
        "Cfg: $Cfg",
        "Teacher LN mode: none",
        "Lambdas: $($Lambdas -join ', ')",
        "Loss modes: $($LossModes -join ', ')",
        "Image layer distill weights: $($ImageLayerDistillWeights -join ', ')",
        "Image layer distill last N: $ImageLayerDistillLastN",
        "Num workers: $NumWorkers",
        ""
    ) | Set-Content -Path $AggregateSummaryPath

    $TableHeader = "{0,-28} {1,8} {2,8} {3,8} {4,8} {5,8} {6,8}" -f "Setting", "Base", "Novel", "HM", "BaseStd", "NovelStd", "HMStd"

    foreach ($ImageLayerDistillWeight in $ImageLayerDistillWeights) {
        $WeightTag = if ([double]::IsNaN($ImageLayerDistillWeight)) {
            "auto"
        }
        else {
            $ImageLayerDistillWeight.ToString("0.############", [System.Globalization.CultureInfo]::InvariantCulture)
        }

        Add-Content -Path $AggregateSummaryPath -Value "=========================================="
        Add-Content -Path $AggregateSummaryPath -Value "ImageLayerDistillWeight: $WeightTag"
        Add-Content -Path $AggregateSummaryPath -Value $TableHeader
        Add-Content -Path $AggregateSummaryPath -Value ("-" * $TableHeader.Length)

        foreach ($LossLambda in $Lambdas) {
            $LambdaTag = $LossLambda.ToString("0.############", [System.Globalization.CultureInfo]::InvariantCulture)

            foreach ($LossMode in $LossModes) {
                $RunTag = "image12distill_last${ImageLayerDistillLastN}_weight${WeightTag}_lambda${LambdaTag}_loss_$LossMode"
                $SummaryFile = "benchmark_5datasets_hicropl__${Dataset}__${RunTag}.txt"
                $Setting = "lambda${LambdaTag}_$LossMode"

                Write-Host ""
                Write-Host "------------------------------------------" -ForegroundColor Cyan
                Write-Host "Dataset=$Dataset | weight=$WeightTag | lastN=$ImageLayerDistillLastN | lambda=$LambdaTag | loss=$LossMode" -ForegroundColor Cyan
                Write-Host "------------------------------------------" -ForegroundColor Cyan

                & $Runner `
                    -Seeds $Seeds `
                    -Shots $Shots `
                    -Datasets $Dataset `
                    -Trainer $Trainer `
                    -Cfg $Cfg `
                    -TeacherLnMode none `
                    -ImageLayerDistill `
                    -ImageLayerDistillLoss $LossMode `
                    -ImageLayerDistillWeight $ImageLayerDistillWeight `
                    -ImageLayerDistillLastN $ImageLayerDistillLastN `
                    -LossLambda $LossLambda `
                    -RunTag $RunTag `
                    -NumWorkers $NumWorkers `
                    -PythonExe $PythonExe `
                    -DataRoot $DataRoot `
                    -SummaryFile $SummaryFile

                if ($LASTEXITCODE -ne 0) {
                    exit $LASTEXITCODE
                }

                $SummaryPath = Join-Path $RepoRoot $SummaryFile
                $SummaryLines = Get-Content -Path $SummaryPath
                $MeanLine = $SummaryLines | Where-Object { $_ -match '^\s*' + [regex]::Escape($Dataset) + '\s+' } | Select-Object -First 1

                if (-not $MeanLine) {
                    throw "Could not parse dataset row from summary file: $SummaryPath"
                }

                $Parts = ($MeanLine -split '\s+') | Where-Object { $_ }
                if ($Parts.Count -lt 7) {
                    throw "Unexpected summary row format in ${SummaryPath}:`n$MeanLine"
                }

                $Row = "{0,-28} {1,8} {2,8} {3,8} {4,8} {5,8} {6,8}" -f `
                    $Setting,
                    $Parts[1],
                    $Parts[2],
                    $Parts[3],
                    $Parts[4],
                    $Parts[5],
                    $Parts[6]
                Add-Content -Path $AggregateSummaryPath -Value $Row
            }
        }

        Add-Content -Path $AggregateSummaryPath -Value ""
    }
}
