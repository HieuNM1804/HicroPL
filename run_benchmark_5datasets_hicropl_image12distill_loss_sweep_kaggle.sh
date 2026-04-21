#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run HiCroPL image layer distillation loss/weight sweep on Linux/Kaggle.

Example:
  bash run_benchmark_5datasets_hicropl_image12distill_loss_sweep_kaggle.sh \
    --data-root /kaggle/input/your-data-root \
    --image-layer-distill-last-n 4 \
    --lambdas 12 \
    --loss-modes mse,l1,cosine \
    --image-layer-distill-weights 0,1,2,3,4,5,6,7,8,9,10

Options:
  --data-root PATH                     Dataset root. Defaults to DATA_ROOT env or /kaggle/input/data
  --datasets a,b,c                     Defaults to caltech101,dtd,eurosat,oxford_flowers,oxford_pets
  --seeds a,b,c                        Defaults to 1,2,3
  --shots N                            Defaults to 16
  --trainer NAME                       Defaults to HiCroPL
  --cfg NAME                           Defaults to vit_b16_c2_ep50_batch32_16ctx
  --lambdas a,b,c                      Defaults to 12
  --loss-modes a,b,c                   Defaults to mse,l1,cosine
  --image-layer-distill-weights a,b,c  Defaults to 1,2,3,4,5,6,7,8,9,10
  --image-layer-distill-last-n N       Defaults to 12
  --num-workers N                      Defaults to 0
  --python-exe CMD                     Defaults to python
USAGE
}

split_csv() {
  local input="$1"
  IFS=',' read -r -a SPLIT_CSV_RESULT <<< "$input"
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

python_exe="python"
data_root="${DATA_ROOT:-/kaggle/input/data}"
datasets_csv="caltech101,dtd,eurosat,oxford_flowers,oxford_pets"
seeds_csv="1,2,3"
shots="16"
trainer="HiCroPL"
cfg="vit_b16_c2_ep50_batch32_16ctx"
lambdas_csv="12"
loss_modes_csv="mse,l1,cosine"
image_layer_distill_weights_csv="1,2,3,4,5,6,7,8,9,10"
image_layer_distill_last_n="12"
num_workers="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-root) data_root="$2"; shift 2 ;;
    --datasets) datasets_csv="$2"; shift 2 ;;
    --seeds) seeds_csv="$2"; shift 2 ;;
    --shots) shots="$2"; shift 2 ;;
    --trainer) trainer="$2"; shift 2 ;;
    --cfg) cfg="$2"; shift 2 ;;
    --lambdas) lambdas_csv="$2"; shift 2 ;;
    --loss-modes) loss_modes_csv="$2"; shift 2 ;;
    --image-layer-distill-weights) image_layer_distill_weights_csv="$2"; shift 2 ;;
    --image-layer-distill-last-n) image_layer_distill_last_n="$2"; shift 2 ;;
    --num-workers) num_workers="$2"; shift 2 ;;
    --python-exe) python_exe="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ ! -d "$data_root" ]]; then
  echo "Data root not found: $data_root" >&2
  echo "Pass the Kaggle dataset root with --data-root, e.g. /kaggle/input/<dataset-name>/data" >&2
  exit 1
fi

split_csv "$datasets_csv"; datasets=("${SPLIT_CSV_RESULT[@]}")
split_csv "$seeds_csv"; seeds=("${SPLIT_CSV_RESULT[@]}")
split_csv "$lambdas_csv"; lambdas=("${SPLIT_CSV_RESULT[@]}")
split_csv "$loss_modes_csv"; loss_modes=("${SPLIT_CSV_RESULT[@]}")
split_csv "$image_layer_distill_weights_csv"; image_layer_distill_weights=("${SPLIT_CSV_RESULT[@]}")

output_root="$repo_root/output/base2new"
summary_script="$repo_root/scripts/hicropl/summarize_base2new.py"

if [[ ! -f "$summary_script" ]]; then
  echo "Summary script not found: $summary_script" >&2
  exit 1
fi

run_train_eval_one_setting() {
  local dataset="$1"
  local lambda="$2"
  local loss_mode="$3"
  local layer_weight="$4"
  local run_tag="$5"
  local output_cfg="${cfg}__${run_tag}"
  local dataset_config="$repo_root/configs/datasets/${dataset}.yaml"
  local trainer_config="$repo_root/configs/trainers/${trainer}/${cfg}.yaml"

  if [[ ! -f "$dataset_config" ]]; then
    echo "Dataset config not found: $dataset_config" >&2
    exit 1
  fi
  if [[ ! -f "$trainer_config" ]]; then
    echo "Trainer config not found: $trainer_config" >&2
    exit 1
  fi

  for seed in "${seeds[@]}"; do
    local train_dir="$output_root/train_base/$dataset/shots_$shots/$trainer/$output_cfg/seed$seed"
    echo "=== Train base | dataset=$dataset seed=$seed lastN=$image_layer_distill_last_n weight=$layer_weight lambda=$lambda loss=$loss_mode ==="
    "$python_exe" "$repo_root/train.py" \
      --root "$data_root" \
      --seed "$seed" \
      --trainer "$trainer" \
      --dataset-config-file "$dataset_config" \
      --config-file "$trainer_config" \
      --output-dir "$train_dir" \
      TRAINER.HICROPL.TEACHER_LN_MODE none \
      TRAINER.HICROPL.IMAGE_LAYER_DISTILL True \
      TRAINER.HICROPL.IMAGE_LAYER_DISTILL_LOSS "$loss_mode" \
      TRAINER.HICROPL.IMAGE_LAYER_DISTILL_WEIGHT "$layer_weight" \
      TRAINER.HICROPL.IMAGE_LAYER_DISTILL_LAST_N "$image_layer_distill_last_n" \
      TRAINER.HICROPL.LAMBD "$lambda" \
      DATALOADER.NUM_WORKERS "$num_workers" \
      DATASET.NUM_SHOTS "$shots" \
      DATASET.SUBSAMPLE_CLASSES base
  done

  for seed in "${seeds[@]}"; do
    local train_dir="$output_root/train_base/$dataset/shots_$shots/$trainer/$output_cfg/seed$seed"
    local novel_dir="$output_root/test_new/$dataset/shots_$shots/$trainer/$output_cfg/seed$seed"
    echo "=== Eval novel | dataset=$dataset seed=$seed lastN=$image_layer_distill_last_n weight=$layer_weight lambda=$lambda loss=$loss_mode ==="
    "$python_exe" "$repo_root/train.py" \
      --root "$data_root" \
      --seed "$seed" \
      --trainer "$trainer" \
      --dataset-config-file "$dataset_config" \
      --config-file "$trainer_config" \
      --output-dir "$novel_dir" \
      --model-dir "$train_dir" \
      --eval-only \
      TRAINER.HICROPL.TEACHER_LN_MODE none \
      TRAINER.HICROPL.IMAGE_LAYER_DISTILL True \
      TRAINER.HICROPL.IMAGE_LAYER_DISTILL_LOSS "$loss_mode" \
      TRAINER.HICROPL.IMAGE_LAYER_DISTILL_WEIGHT "$layer_weight" \
      TRAINER.HICROPL.IMAGE_LAYER_DISTILL_LAST_N "$image_layer_distill_last_n" \
      TRAINER.HICROPL.LAMBD "$lambda" \
      DATALOADER.NUM_WORKERS "$num_workers" \
      DATASET.NUM_SHOTS "$shots" \
      DATASET.SUBSAMPLE_CLASSES new
  done
}

summarize_setting() {
  local dataset="$1"
  local run_tag="$2"
  local output_cfg="${cfg}__${run_tag}"

  "$python_exe" "$summary_script" \
    --dataset "$dataset" \
    --trainer "$trainer" \
    --cfg "$output_cfg" \
    --shots "$shots" \
    --output-root "$output_root" \
    --seeds "${seeds[@]}"
}

for dataset in "${datasets[@]}"; do
  aggregate_file="$repo_root/benchmark_5datasets_hicropl__${dataset}__image12distill_lambda_loss_sweep.txt"
  {
    echo "HiCroPL image 12-layer distill loss sweep"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Dataset: $dataset"
    echo "Seeds: ${seeds[*]}"
    echo "Shots: $shots"
    echo "Trainer: $trainer"
    echo "Cfg: $cfg"
    echo "Teacher LN mode: none"
    echo "Lambdas: ${lambdas[*]}"
    echo "Loss modes: ${loss_modes[*]}"
    echo "Image layer distill weights: ${image_layer_distill_weights[*]}"
    echo "Image layer distill last N: $image_layer_distill_last_n"
    echo "Num workers: $num_workers"
    echo ""
  } > "$aggregate_file"

  table_header=$(printf "%-28s %8s %8s %8s %8s %8s %8s" "Setting" "Base" "Novel" "HM" "BaseStd" "NovelStd" "HMStd")

  for layer_weight in "${image_layer_distill_weights[@]}"; do
    {
      echo "=========================================="
      echo "ImageLayerDistillWeight: $layer_weight"
      echo "$table_header"
      printf '%*s\n' "${#table_header}" '' | tr ' ' '-'
    } >> "$aggregate_file"

    for lambda in "${lambdas[@]}"; do
      for loss_mode in "${loss_modes[@]}"; do
        run_tag="image12distill_last${image_layer_distill_last_n}_weight${layer_weight}_lambda${lambda}_loss_${loss_mode}"
        setting="lambda${lambda}_${loss_mode}"

        echo ""
        echo "------------------------------------------"
        echo "Dataset=$dataset | weight=$layer_weight | lastN=$image_layer_distill_last_n | lambda=$lambda | loss=$loss_mode"
        echo "------------------------------------------"

        run_train_eval_one_setting "$dataset" "$lambda" "$loss_mode" "$layer_weight" "$run_tag"
        summary_output="$(summarize_setting "$dataset" "$run_tag")"
        mean_line="$(printf '%s\n' "$summary_output" | awk '/^[[:space:]]*Mean[[:space:]]+/ {print; exit}')"
        std_line="$(printf '%s\n' "$summary_output" | awk '/^[[:space:]]*Std[[:space:]]+/ {print; exit}')"

        if [[ -z "$mean_line" || -z "$std_line" ]]; then
          echo "Could not parse summary for dataset=$dataset run_tag=$run_tag" >&2
          printf '%s\n' "$summary_output" >&2
          exit 1
        fi

        read -r _ base_mean novel_mean hm_mean <<< "$mean_line"
        read -r _ base_std novel_std hm_std <<< "$std_line"
        printf "%-28s %8s %8s %8s %8s %8s %8s\n" \
          "$setting" "$base_mean" "$novel_mean" "$hm_mean" "$base_std" "$novel_std" "$hm_std" >> "$aggregate_file"
      done
    done

    echo "" >> "$aggregate_file"
  done
done
