import argparse
import re
import statistics
from pathlib import Path


ACCURACY_PATTERN = re.compile(r"\* accuracy: ([\d.eE+-]+)%")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Summarize base-to-new results across multiple seeds."
    )
    parser.add_argument("--dataset", required=True, help="dataset name")
    parser.add_argument("--trainer", default="HiCroPL", help="trainer name")
    parser.add_argument("--cfg", required=True, help="trainer config stem")
    parser.add_argument("--shots", type=int, default=16, help="number of shots")
    parser.add_argument(
        "--seeds",
        type=int,
        nargs="+",
        default=[1, 2, 3],
        help="seed list to summarize",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("output") / "base2new",
        help="base2new output directory",
    )
    return parser.parse_args()


def harmonic_mean(base_score, novel_score):
    denom = base_score + novel_score
    if denom == 0:
        return 0.0
    return 2.0 * base_score * novel_score / denom


def build_seed_dir(output_root, split_dir, dataset, shots, trainer, cfg, seed):
    return (
        output_root
        / split_dir
        / dataset
        / f"shots_{shots}"
        / trainer
        / cfg
        / f"seed{seed}"
    )


def get_log_candidates(seed_dir):
    return sorted(
        (path for path in seed_dir.glob("log.txt*") if path.is_file()),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )


def extract_last_accuracy(log_path):
    text = log_path.read_text(encoding="utf-8", errors="ignore")
    matches = ACCURACY_PATTERN.findall(text)
    if not matches:
        raise ValueError(f"No accuracy found in {log_path}")
    return float(matches[-1])


def read_seed_accuracy(seed_dir):
    if not seed_dir.exists():
        raise FileNotFoundError(f"Missing directory: {seed_dir}")

    errors = []
    for log_path in get_log_candidates(seed_dir):
        try:
            return extract_last_accuracy(log_path), log_path
        except ValueError as exc:
            errors.append(str(exc))

    if errors:
        raise ValueError(errors[0])

    raise FileNotFoundError(f"No log.txt files found in {seed_dir}")


def format_stat(values):
    mean = statistics.fmean(values)
    std = statistics.stdev(values) if len(values) > 1 else 0.0
    return mean, std


def main():
    args = parse_args()
    output_root = args.output_root.resolve()

    rows = []
    for seed in args.seeds:
        base_dir = build_seed_dir(
            output_root,
            "train_base",
            args.dataset,
            args.shots,
            args.trainer,
            args.cfg,
            seed,
        )
        novel_dir = build_seed_dir(
            output_root,
            "test_new",
            args.dataset,
            args.shots,
            args.trainer,
            args.cfg,
            seed,
        )

        base_acc, base_log = read_seed_accuracy(base_dir)
        novel_acc, novel_log = read_seed_accuracy(novel_dir)
        hm = harmonic_mean(base_acc, novel_acc)

        rows.append(
            {
                "seed": seed,
                "base": base_acc,
                "novel": novel_acc,
                "hm": hm,
                "base_log": base_log,
                "novel_log": novel_log,
            }
        )

    base_values = [row["base"] for row in rows]
    novel_values = [row["novel"] for row in rows]
    hm_values = [row["hm"] for row in rows]

    base_mean, base_std = format_stat(base_values)
    novel_mean, novel_std = format_stat(novel_values)
    hm_mean, hm_std = format_stat(hm_values)

    print(
        f"Dataset={args.dataset} Trainer={args.trainer} CFG={args.cfg} "
        f"Shots={args.shots} Seeds={args.seeds}"
    )
    print("")
    print(f"{'Seed':<8}{'Base':>10}{'Novel':>10}{'HM':>10}")
    print("-" * 38)

    for row in rows:
        print(
            f"{row['seed']:<8}{row['base']:>10.2f}{row['novel']:>10.2f}{row['hm']:>10.2f}"
        )

    print("-" * 38)
    print(
        f"{'Mean':<8}{base_mean:>10.2f}{novel_mean:>10.2f}{hm_mean:>10.2f}"
    )
    print(f"{'Std':<8}{base_std:>10.2f}{novel_std:>10.2f}{hm_std:>10.2f}")
    print("")
    print("Logs used:")
    for row in rows:
        print(f"seed{row['seed']} base  -> {row['base_log']}")
        print(f"seed{row['seed']} novel -> {row['novel_log']}")


if __name__ == "__main__":
    main()
