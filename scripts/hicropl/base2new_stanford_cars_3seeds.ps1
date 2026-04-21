[CmdletBinding()]
param(
    [string]$Trainer = "HiCroPL",
    [string]$Cfg = "vit_b16_c2_ep50_batch32_16ctx",
    [int]$Shots = 16,
    [int[]]$Seeds = @(1, 2, 3),
    [string]$TeacherLnMode = "none",
    [string]$RunTag = "",
    [int]$NumWorkers = 0,
    [string]$PythonExe = "python",
    [string]$DataRoot = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Runner = Join-Path $ScriptDir "base2new_3seeds.ps1"

& $Runner `
    -Dataset "stanford_cars" `
    -Trainer $Trainer `
    -Cfg $Cfg `
    -TeacherLnMode $TeacherLnMode `
    -RunTag $RunTag `
    -NumWorkers $NumWorkers `
    -Shots $Shots `
    -Seeds $Seeds `
    -PythonExe $PythonExe `
    -DataRoot $DataRoot

exit $LASTEXITCODE
