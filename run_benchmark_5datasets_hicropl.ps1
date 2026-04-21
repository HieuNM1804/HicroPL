[CmdletBinding()]
param(
    [int[]]$Seeds = @(1, 2, 3),
    [int]$Shots = 16,
    [string[]]$Datasets = @("caltech101", "dtd", "eurosat", "oxford_flowers", "oxford_pets"),
    [string]$Trainer = "HiCroPL",
    [string]$Cfg = "vit_b16_c2_ep50_batch32_16ctx",
    [ValidateSet("none", "ln_pre", "ln_post", "ln_pre_ln_post", "ln_1", "ln_2", "ln_1_ln_2", "ln_1_ln_2_ln_pre_ln_post")]
    [string]$TeacherLnMode = "none",
    [switch]$ImageLayerDistill,
    [ValidateSet("cosine", "l1", "smooth_l1", "mse", "kl")]
    [string]$ImageLayerDistillLoss = "cosine",
    [double]$ImageLayerDistillWeight = [double]::NaN,
    [int]$ImageLayerDistillLastN = 12,
    [double]$LossLambda = [double]::NaN,
    [string]$RunTag = "",
    [int]$NumWorkers = 0,
    [string]$PythonExe = "python",
    [string]$DataRoot = "",
    [string]$SummaryFile = "benchmark_5datasets_hicropl.txt"
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$Runner = Join-Path $RepoRoot "scripts\hicropl\base2new_3seeds.ps1"
$SummaryScript = Join-Path $RepoRoot "scripts\hicropl\summarize_base2new.py"
$OutputRoot = Join-Path $RepoRoot "output\base2new"

function Get-OutputCfgName {
    param(
        [string]$CfgName,
        [string]$TeacherLnMode,
        [string]$RunTag
    )

    $SuffixParts = @()
    if ($TeacherLnMode -and $TeacherLnMode -ne "none") {
        $SuffixParts += "teacherln_$TeacherLnMode"
    }
    if ($RunTag) {
        $SuffixParts += $RunTag
    }

    if ($SuffixParts.Count -eq 0) {
        return $CfgName
    }

    return "$CfgName" + "__" + ($SuffixParts -join "__")
}

function Get-RunSuffix {
    param(
        [string]$TeacherLnMode,
        [string]$RunTag
    )

    $SuffixParts = @()
    if ($TeacherLnMode -and $TeacherLnMode -ne "none") {
        $SuffixParts += "teacherln_$TeacherLnMode"
    }
    if ($RunTag) {
        $SuffixParts += $RunTag
    }

    return ($SuffixParts -join "__")
}

$OutputCfg = Get-OutputCfgName -CfgName $Cfg -TeacherLnMode $TeacherLnMode -RunTag $RunTag
$RunSuffix = Get-RunSuffix -TeacherLnMode $TeacherLnMode -RunTag $RunTag

if (-not (Test-Path -LiteralPath $Runner)) {
    throw "Runner script not found: $Runner"
}

if (-not (Test-Path -LiteralPath $SummaryScript)) {
    throw "Summary script not found: $SummaryScript"
}

if (-not $DataRoot) {
    $DataRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "..\data"))
}

if (-not (Test-Path -LiteralPath $DataRoot)) {
    throw "Data root not found: $DataRoot"
}

if ([System.IO.Path]::IsPathRooted($SummaryFile)) {
    $SummaryPath = $SummaryFile
}
else {
    if ($SummaryFile -eq "benchmark_5datasets_hicropl.txt" -and $RunSuffix) {
        $SummaryFile = "benchmark_5datasets_hicropl__${RunSuffix}.txt"
    }
    $SummaryPath = Join-Path $RepoRoot $SummaryFile
}

$FinalRows = New-Object System.Collections.Generic.List[object]

function Get-SummaryStats {
    param(
        [string]$Dataset
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
        throw "Failed to summarize dataset '$Dataset':`n$SummaryText"
    }

    $MeanLine = $SummaryOutput | Where-Object { $_ -match '^\s*Mean\s+' } | Select-Object -First 1
    $StdLine = $SummaryOutput | Where-Object { $_ -match '^\s*Std\s+' } | Select-Object -First 1

    if (-not $MeanLine -or -not $StdLine) {
        $SummaryText = $SummaryOutput | Out-String
        throw "Could not parse summary stats for dataset '$Dataset':`n$SummaryText"
    }

    $MeanParts = ($MeanLine -split '\s+') | Where-Object { $_ }
    $StdParts = ($StdLine -split '\s+') | Where-Object { $_ }

    if ($MeanParts.Count -lt 4 -or $StdParts.Count -lt 4) {
        $SummaryText = $SummaryOutput | Out-String
        throw "Unexpected summary format for dataset '$Dataset':`n$SummaryText"
    }

    return [PSCustomObject]@{
        BaseMean  = $MeanParts[1]
        NovelMean = $MeanParts[2]
        HMMean    = $MeanParts[3]
        BaseStd   = $StdParts[1]
        NovelStd  = $StdParts[2]
        HMStd     = $StdParts[3]
    }
}

foreach ($Dataset in $Datasets) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "Running benchmark for dataset=$Dataset" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow

    & $Runner `
        -Dataset $Dataset `
        -Trainer $Trainer `
        -Cfg $Cfg `
        -TeacherLnMode $TeacherLnMode `
        -ImageLayerDistill:$ImageLayerDistill `
        -ImageLayerDistillLoss $ImageLayerDistillLoss `
        -ImageLayerDistillWeight $ImageLayerDistillWeight `
        -ImageLayerDistillLastN $ImageLayerDistillLastN `
        -LossLambda $LossLambda `
        -RunTag $RunTag `
        -NumWorkers $NumWorkers `
        -Shots $Shots `
        -Seeds $Seeds `
        -PythonExe $PythonExe `
        -DataRoot $DataRoot

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $Stats = Get-SummaryStats -Dataset $Dataset
    $FinalRows.Add([PSCustomObject]@{
        Dataset   = $Dataset
        BaseMean  = $Stats.BaseMean
        NovelMean = $Stats.NovelMean
        HMMean    = $Stats.HMMean
        BaseStd   = $Stats.BaseStd
        NovelStd  = $Stats.NovelStd
        HMStd     = $Stats.HMStd
    })
}

@(
    "HiCroPL benchmark on 5 datasets",
    "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Repo root: $RepoRoot",
    "Data root: $DataRoot",
    "Datasets: $($Datasets -join ', ')",
    "Seeds: $($Seeds -join ', ')",
    "Shots: $Shots",
    "Trainer: $Trainer",
    "Cfg: $Cfg",
    "Output cfg: $OutputCfg",
    "Teacher LN mode: $TeacherLnMode",
    "Image layer distill: $($ImageLayerDistill.IsPresent)",
    "Image layer distill loss: $ImageLayerDistillLoss",
    "Image layer distill weight: $ImageLayerDistillWeight",
    "Image layer distill last N: $ImageLayerDistillLastN",
    "Loss lambda: $LossLambda",
    "Num workers: $NumWorkers",
    "Run tag: $RunTag",
    ""
) | Set-Content -Path $SummaryPath

$FinalRows |
    Format-Table Dataset, BaseMean, NovelMean, HMMean, BaseStd, NovelStd, HMStd -AutoSize |
    Out-String -Width 200 |
    Add-Content -Path $SummaryPath

Write-Host ""
Write-Host "Summary written to: $SummaryPath" -ForegroundColor Green
