# HiCroPL: Hierarchical Cross-modal Prompt Learning for Vision-Language Models [ICCV 2025]

> This is the official implementation of the paper " [Hierarchical Cross-modal Prompt Learning for Vision-Language Models](https://arxiv.org/pdf/2507.14976)".
>
> Authors: Hao Zheng, Shunzhi Yang, Zhuoxin He, Jinfeng Yang, Zhenhua Huang

------

## Overview

![motivation](docs/motivation.png)

**HiCroPL** is a hierarchical cross-modal prompt learning framework for adapting frozen vision-language models such as CLIP.

Unlike uni-modal prompting methods or one-way coupling designs, HiCroPL builds **bidirectional knowledge flow** between the textual and visual branches. The core idea is simple:

- In early layers, textual prompts transfer relatively clear semantic priors to the visual branch.
- In later layers, visually grounded prompts refine the textual branch and improve cross-modal alignment.
- A hierarchical knowledge mapper and lightweight layer-specific proxy tokens enable prompt interaction across layers while preserving transferable shallow semantics.

## Highlights

- **Bidirectional cross-modal prompting.** HiCroPL enables prompt interaction in both text-to-vision and vision-to-text directions instead of relying on isolated or one-way adaptation.
- **Hierarchical knowledge flow across layers.** Prompt interaction is distributed through the encoder, allowing shallow transferable semantics and deeper task-relevant cues to cooperate.
- **Layer-specific proxy tokens.** Lightweight proxy tokens make cross-modal interaction efficient without introducing heavy additional modules.
- **Strong downstream performance.** HiCroPL delivers competitive generalization and is especially strong in low-shot adaptation settings.

## Method

HiCroPL is built on three key ingredients:

| Component | Role |
| --- | --- |
| Cross-modal prompt learner | Maintains textual and visual prompt tokens across layers. |
| Layer-specific knowledge proxy | Summarizes prompt information at each layer for efficient interaction. |
| Hierarchical knowledge mapper | Transfers prompt information across modalities in a bidirectional and layer-aware way. |

A high-level forward pipeline is:

1. Initialize textual and visual prompts across multiple layers.
2. Refine visual prompts in early layers with text-to-vision knowledge flow.
3. Refine textual prompts in later layers with vision-to-text knowledge flow.
4. Inject the resulting prompts into the CLIP encoders for prediction.

## Running HiCroPL

### Environment

```bash
conda create -n hicropl python=3.10 -y
conda activate hicropl
pip install -r requirements.txt
```
Recommended PyTorch versions: `1.13.0` or `2.2.0`.

### Data

Prepare datasets following the standard [CoOp dataset setup](https://github.com/KaiyangZhou/CoOp/blob/main/DATASETS.md) setup and update the dataset root in the shell scripts under `scripts/hicropl/`:

```bash
DATA="/path/to/dataset/folder"
```

### Quick Start

Base-to-Novel training:

```bash
sh scripts/hicropl/base2new_train_hicropl.sh imagenet 1
```

Base-to-Novel evaluation:

```bash
sh scripts/hicropl/base2new_test_hicropl.sh imagenet 1
```

Few-shot training:

```bash
sh scripts/hicropl/few_shot.sh oxford_pets 16
```

Cross-dataset training:

```bash
sh scripts/hicropl/xd_train.sh caltech101 1
```

Cross-dataset evaluation:

```bash
sh scripts/hicropl/xd_test.sh caltech101 1
```

## Results

Average base-to-novel results across 11 datasets:

| Method                                                       | Base  | Novel | HM    |
| ------------------------------------------------------------ | ----- | ----- | ----- |
| [CLIP](https://arxiv.org/abs/2103.00020)                     | 69.34 | 74.22 | 71.70 |
| [CoOp](https://arxiv.org/abs/2109.01134)                     | 82.69 | 63.22 | 71.66 |
| [CoCoOp](https://arxiv.org/pdf/2203.05557)                   | 80.47 | 71.69 | 75.83 |
| [KgCoOp](https://arxiv.org/pdf/2303.13283)                   | 80.73 | 73.60 | 77.00 |
| [MaPLe](https://arxiv.org/abs/2210.03117)                    | 82.28 | 75.14 | 78.55 |
| [PromptSRC](https://arxiv.org/abs/2307.06948)                | 84.26 | 76.10 | 79.97 |
| [TCP](https://arxiv.org/abs/2311.18231)                      | 84.13 | 75.36 | 79.50 |
| [MMA](https://openaccess.thecvf.com/content/CVPR2024/papers/Yang_MMA_Multi-Modal_Adapter_for_Vision-Language_Models_CVPR_2024_paper.pdf) | 83.20 | 76.80 | 79.87 |
| [CoPrompt](https://arxiv.org/abs/2306.01195)                 | 84.00 | 77.23 | 80.47 |
| [HiCroPL](https://arxiv.org/pdf/2507.14976)                  | 85.89 | 77.99 | 81.75 |


HiCroPL achieves the best harmonic mean among these compared methods, showing a strong balance between adapting to base classes and preserving transferability to novel classes.

## Citation

If you find our work helpful for your research, please consider citing the following BibTeX entry.

```
@inproceedings{zheng2025hierarchical,
  title={Hierarchical cross-modal prompt learning for vision-language models},
  author={Zheng, Hao and Yang, Shunzhi and He, Zhuoxin and Yang, Jinfeng and Huang, Zhenhua},
  booktitle={Proceedings of the IEEE/CVF International Conference on Computer Vision},
  pages={1891--1901},
  year={2025}
}
```

## Acknowledgements

Our code is based on [Co-CoOp, CoOp](https://github.com/KaiyangZhou/CoOp) and [MaPLe](https://github.com/muzairkhattak/multimodal-prompt-learning). We thank the authors for releasing their code. If you use our code, please consider citing these works as well.
