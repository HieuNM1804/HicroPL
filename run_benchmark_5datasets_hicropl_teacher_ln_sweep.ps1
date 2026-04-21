[CmdletBinding()]
param(
    [int[]]$Seeds = @(1, 2, 3),
    [int]$Shots = 16,
    [string[]]$Datasets = @("caltech101", "dtd", "eurosat", "oxford_flowers", "oxford_pets"),
    [string]$Trainer = "HiCroPL",
    [string]$Cfg = "vit_b16_c2_ep50_batch32_16ctx",
    [string[]]$TeacherLnModes = @(
        "ln_pre",
        "ln_post",
        "ln_pre_ln_post",
        "ln_1",
        "ln_2",
        "ln_1_ln_2",
        "ln_1_ln_2_ln_pre_ln_post"
    ),
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

foreach ($TeacherLnMode in $TeacherLnModes) {
    $SummaryFile = "benchmark_5datasets_hicropl__teacherln_$TeacherLnMode.txt"

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Teacher LN sweep mode: $TeacherLnMode" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    & $Runner `
        -Seeds $Seeds `
        -Shots $Shots `
        -Datasets $Datasets `
        -Trainer $Trainer `
        -Cfg $Cfg `
        -TeacherLnMode $TeacherLnMode `
        -NumWorkers $NumWorkers `
        -PythonExe $PythonExe `
        -DataRoot $DataRoot `
        -SummaryFile $SummaryFile

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
