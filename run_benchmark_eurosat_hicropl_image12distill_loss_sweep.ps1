[CmdletBinding()]
param(
    [int[]]$Seeds = @(1, 2, 3),
    [int]$Shots = 16,
    [string]$Dataset = "eurosat",
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
$Runner = Join-Path $RepoRoot "scripts\hicropl\base2new_3seeds.ps1"
$SummaryScript = Join-Path $RepoRoot "scripts\hicropl\summarize_base2new.py"
$OutputRoot = Join-Path $RepoRoot "output\base2new"

if (-not (Test-Path -LiteralPath $Runner)) {
    throw "Benchmark runner not found: $Runner"
}

if (-not (Test-Path -LiteralPath $SummaryScript)) {
    throw "Summary script not found: $SummaryScript"
}

$AggregateSummaryFile = "benchmark_5datasets_hicropl__${Dataset}__image12distill_lambda_loss_sweep.txt"
$AggregateSummaryPath = Join-Path $RepoRoot $AggregateSummaryFile

function Get-OutputCfgName {
    param(
        [string]$CfgName,
        [string]$RunTag
    )

    if (-not $RunTag) {
        return $CfgName
    }

    return "$CfgName" + "__" + $RunTag
}

function Get-SummaryStats {
    param(
        [string]$OutputCfg
    )

    $SummaryOutput = & $PythonExe $SummaryScript `
        --dataset $Dataset `
        --trainer $Trainer `
        --cfg $OutputCfg `
        --shots "$Shots" `
        --output-root $OutputRoot `
        --seeds $Seeds 2>&1

    if ($LASTEXITCODE -ne 0) {
        $SummaryText = $SummaryOutput | Out-String
        throw "Failed to summarize setting '$OutputCfg':`n$SummaryText"
    }

    $MeanLine = $SummaryOutput | Where-Object { $_ -match '^\s*Mean\s+' } | Select-Object -First 1
    $StdLine = $SummaryOutput | Where-Object { $_ -match '^\s*Std\s+' } | Select-Object -First 1

    if (-not $MeanLine -or -not $StdLine) {
        $SummaryText = $SummaryOutput | Out-String
        throw "Could not parse summary stats for setting '$OutputCfg':`n$SummaryText"
    }

    $MeanParts = ($MeanLine -split '\s+') | Where-Object { $_ }
    $StdParts = ($StdLine -split '\s+') | Where-Object { $_ }

    return [PSCustomObject]@{
        BaseMean  = $MeanParts[1]
        NovelMean = $MeanParts[2]
        HMMean    = $MeanParts[3]
        BaseStd   = $StdParts[1]
        NovelStd  = $StdParts[2]
        HMStd     = $StdParts[3]
    }
}

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
            $OutputCfg = Get-OutputCfgName -CfgName $Cfg -RunTag $RunTag
            $Setting = "lambda${LambdaTag}_$LossMode"

            Write-Host ""
            Write-Host "------------------------------------------" -ForegroundColor Cyan
            Write-Host "Dataset=$Dataset | weight=$WeightTag | lastN=$ImageLayerDistillLastN | lambda=$LambdaTag | loss=$LossMode" -ForegroundColor Cyan
            Write-Host "------------------------------------------" -ForegroundColor Cyan

            if (-not [double]::IsNaN($ImageLayerDistillWeight)) {
                & $Runner `
                    -Dataset $Dataset `
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
                    -Shots $Shots `
                    -Seeds $Seeds `
                    -PythonExe $PythonExe `
                    -DataRoot $DataRoot
            }
            else {
                & $Runner `
                    -Dataset $Dataset `
                    -Trainer $Trainer `
                    -Cfg $Cfg `
                    -TeacherLnMode none `
                    -ImageLayerDistill `
                    -ImageLayerDistillLoss $LossMode `
                    -ImageLayerDistillLastN $ImageLayerDistillLastN `
                    -LossLambda $LossLambda `
                    -RunTag $RunTag `
                    -NumWorkers $NumWorkers `
                    -Shots $Shots `
                    -Seeds $Seeds `
                    -PythonExe $PythonExe `
                    -DataRoot $DataRoot
            }

            if ($LASTEXITCODE -ne 0) {
                exit $LASTEXITCODE
            }

            $Stats = Get-SummaryStats -OutputCfg $OutputCfg
            $Row = "{0,-28} {1,8} {2,8} {3,8} {4,8} {5,8} {6,8}" -f `
                $Setting,
                $Stats.BaseMean,
                $Stats.NovelMean,
                $Stats.HMMean,
                $Stats.BaseStd,
                $Stats.NovelStd,
                $Stats.HMStd
            Add-Content -Path $AggregateSummaryPath -Value $Row
        }
    }

    Add-Content -Path $AggregateSummaryPath -Value ""
}
