[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Dataset,

    [string]$Trainer = "HiCroPL",

    [string]$Cfg = "vit_b16_c2_ep50_batch32_16ctx",

    [int]$Shots = 16,

    [int[]]$Seeds = @(1, 2, 3),

    [ValidateSet("none", "ln_pre", "ln_post", "ln_pre_ln_post", "ln_1", "ln_2", "ln_1_ln_2", "ln_1_ln_2_ln_pre_ln_post")]
    [string]$TeacherLnMode = "none",

    [switch]$ImageLayerDistill,

    [ValidateSet("cosine", "l1", "smooth_l1", "mse", "kl")]
    [string]$ImageLayerDistillLoss = "cosine",

    [double]$LossLambda = [double]::NaN,

    [string]$RunTag = "",

    [int]$NumWorkers = 0,

    [string]$PythonExe = "python",

    [string]$DataRoot = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$LossLambdaText = if (-not [double]::IsNaN($LossLambda)) {
    $LossLambda.ToString("0.0############", [System.Globalization.CultureInfo]::InvariantCulture)
}
else {
    ""
}

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

$OutputCfg = Get-OutputCfgName -CfgName $Cfg -TeacherLnMode $TeacherLnMode -RunTag $RunTag

if (-not $DataRoot) {
    $DataRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "..\data"))
}

if (-not (Test-Path -LiteralPath $DataRoot)) {
    throw "Data root not found: $DataRoot"
}

$DatasetConfig = Join-Path $RepoRoot "configs\datasets\$Dataset.yaml"
$TrainerConfig = Join-Path $RepoRoot "configs\trainers\$Trainer\$Cfg.yaml"
$SummaryScript = Join-Path $ScriptDir "summarize_base2new.py"

if (-not (Test-Path -LiteralPath $DatasetConfig)) {
    throw "Dataset config not found: $DatasetConfig"
}

if (-not (Test-Path -LiteralPath $TrainerConfig)) {
    throw "Trainer config not found: $TrainerConfig"
}

Push-Location $RepoRoot
try {
    foreach ($Seed in $Seeds) {
        $TrainDir = Join-Path $RepoRoot "output\base2new\train_base\$Dataset\shots_$Shots\$Trainer\$OutputCfg\seed$Seed"
        Write-Host ""
        Write-Host "=== Train base | dataset=$Dataset seed=$Seed teacher_ln_mode=$TeacherLnMode ==="

        $TrainArgs = @(
            "train.py",
            "--root", $DataRoot,
            "--seed", "$Seed",
            "--trainer", $Trainer,
            "--dataset-config-file", $DatasetConfig,
            "--config-file", $TrainerConfig,
            "--output-dir", $TrainDir,
            "TRAINER.HICROPL.TEACHER_LN_MODE", $TeacherLnMode,
            "DATALOADER.NUM_WORKERS", "$NumWorkers",
            "DATASET.NUM_SHOTS", "$Shots",
            "DATASET.SUBSAMPLE_CLASSES", "base"
        )

        if ($ImageLayerDistill.IsPresent) {
            $TrainArgs += @(
                "TRAINER.HICROPL.IMAGE_LAYER_DISTILL", "True",
                "TRAINER.HICROPL.IMAGE_LAYER_DISTILL_LOSS", $ImageLayerDistillLoss
            )
        }

        if (-not [double]::IsNaN($LossLambda)) {
            $TrainArgs += @("TRAINER.HICROPL.LAMBD", $LossLambdaText)
        }

        & $PythonExe @TrainArgs
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

    foreach ($Seed in $Seeds) {
        $TrainDir = Join-Path $RepoRoot "output\base2new\train_base\$Dataset\shots_$Shots\$Trainer\$OutputCfg\seed$Seed"
        $NovelDir = Join-Path $RepoRoot "output\base2new\test_new\$Dataset\shots_$Shots\$Trainer\$OutputCfg\seed$Seed"
        Write-Host ""
        Write-Host "=== Eval novel | dataset=$Dataset seed=$Seed teacher_ln_mode=$TeacherLnMode ==="

        $EvalArgs = @(
            "train.py",
            "--root", $DataRoot,
            "--seed", "$Seed",
            "--trainer", $Trainer,
            "--dataset-config-file", $DatasetConfig,
            "--config-file", $TrainerConfig,
            "--output-dir", $NovelDir,
            "--model-dir", $TrainDir,
            "--eval-only",
            "TRAINER.HICROPL.TEACHER_LN_MODE", $TeacherLnMode,
            "DATALOADER.NUM_WORKERS", "$NumWorkers",
            "DATASET.NUM_SHOTS", "$Shots",
            "DATASET.SUBSAMPLE_CLASSES", "new"
        )

        if ($ImageLayerDistill.IsPresent) {
            $EvalArgs += @(
                "TRAINER.HICROPL.IMAGE_LAYER_DISTILL", "True",
                "TRAINER.HICROPL.IMAGE_LAYER_DISTILL_LOSS", $ImageLayerDistillLoss
            )
        }

        if (-not [double]::IsNaN($LossLambda)) {
            $EvalArgs += @("TRAINER.HICROPL.LAMBD", $LossLambdaText)
        }

        & $PythonExe @EvalArgs
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

    Write-Host ""
    Write-Host "=== Summary ==="

    $SummaryArgs = @(
        $SummaryScript,
        "--dataset", $Dataset,
        "--trainer", $Trainer,
        "--cfg", $OutputCfg,
        "--shots", "$Shots",
        "--output-root", (Join-Path $RepoRoot "output\base2new"),
        "--seeds"
    ) + ($Seeds | ForEach-Object { "$_" })

    & $PythonExe @SummaryArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
finally {
    Pop-Location
}
