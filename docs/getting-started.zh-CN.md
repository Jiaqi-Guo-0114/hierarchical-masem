# 入门指南

[English](getting-started.md) · [项目介绍](../README.zh-CN.md)

## 环境准备

请先安装 Python **3.9 及以上**与 R **4.6.0**。程序会按锁文件，在单独的 R 库中恢复依赖版本。当前验证平台为 macOS；其他平台安装依赖时可能需要编译器和系统库。

```sh
git clone https://github.com/Jiaqi-Guo-0114/hierarchical-masem.git
cd hierarchical-masem
python3 skills/hierarchical-masem/scripts/masem.py setup
python3 skills/hierarchical-masem/scripts/masem.py check
```

`setup` 下载锁定版本的 R 包。分析与核验命令离线运行，单独的环境不会修改其他分析项目的 R 库。

## 试跑合成示例

示例数据用于熟悉流程与检查软件，是人工生成的数据，不能把其估计值解释为心理学研究发现。

```sh
python3 skills/hierarchical-masem/scripts/masem.py demo --project my-example
```

`demo` 会创建合成示例项目、运行分析、核验结果，并返回 `report.html` 的路径。用浏览器打开文件即可查看中英双语总览，同目录还保存了表格与图形。请先完成 `setup`；`demo` 本身不安装依赖。

每次运行创建新目录，保存输入、配置、模型、实际执行代码及环境记录。目录中的 `REPRODUCE.md` 说明如何重跑已归档的分析。

## 在 Codex 中使用

克隆仓库后，安装技能：

```sh
mkdir -p ~/.codex/skills
cp -R skills/hierarchical-masem ~/.codex/skills/
```

复制前检查是否已有 `~/.codex/skills/hierarchical-masem` 目录。新开 Codex 会话后调用 `$hierarchical-masem`，或提供数据与理论模型，直接提出层级 MASEM 分析请求。

支持插件的 Codex 也可以选择以下安装方式：

```sh
codex plugin marketplace add Jiaqi-Guo-0114/hierarchical-masem
codex plugin add hierarchical-masem@hierarchical-masem-community
```

技能与插件两种方式任选其一。Codex 调用同一个分析引擎，仍需准备上述 R 环境。命令行流程无需安装 Codex。

## 准备自己的分析

```sh
python3 skills/hierarchical-masem/scripts/masem.py init --project my-analysis
```

命令会创建新项目，包含三份可编辑输入：

| 文件 | 需要填写的内容 |
| --- | --- |
| `correlations.csv` | 每个独立样本的每对变量占一行；也可以在配置中选用 XLSX |
| `config.json` | 变量顺序、列名映射、已确认的样本独立性、调节变量与敏感性设置 |
| `model.json` | 观测变量 RAM 理论路径模型 |

一个包含三个变量的样本，需要填写全部三个非对角相关。例如，以下**演示数据**构成一个完整的样本相关矩阵：

```csv
study_id,sample_id,var1,var2,r,n,overlap_group
study_01,sample_01,X1,X2,0.20,120,
study_01,sample_01,X1,Y,0.30,120,
study_01,sample_01,X2,Y,0.40,120,
```

元分析需要多项独立样本／研究，以上三行本身还不能构成元分析。同一个样本各行的研究与样本标识应保持一致；总人数按样本身份累计一次。样本独立性需根据研究报告确认，不能单凭 ID 判断。

根据[数据与模型规范](../skills/hierarchical-masem/references/data-contract.md)设置列名映射、构念方向、RAM 模型，以及预设或探索性组间比较。随后校验并分析项目：

```sh
python3 skills/hierarchical-masem/scripts/masem.py validate --project my-analysis
python3 skills/hierarchical-masem/scripts/masem.py run --project my-analysis
python3 skills/hierarchical-masem/scripts/masem.py verify --run my-analysis/runs/<返回的运行编号>
```

将 `<返回的运行编号>` 替换为 `run` 返回的目录名。校验错误用于指出拟合前需要解决的输入问题，请勿为了让模型运行成功而改变相关系数。

## 查看分析结果

每次成功运行都会保存以下文件：

| 先看这些文件 | 内容 |
| --- | --- |
| `report.html` | 可独立分享的中英双语结果总览，用浏览器打开 |
| `report.md` | 分析摘要及影响解释的诊断信息 |
| `paths.csv`、`paths.png`、`paths.pdf` | 路径估计、区间与图形 |
| `pooled_correlations.csv`、`stage1_models.csv` | 合并相关与第一阶段模型比较 |
| `moderator_*.csv` / `moderator_omnibus.json` | 指定调节分析时的组间比较 |
| `sensitivity.csv`、`study_influence.csv` | 假设及单项研究的影响 |
| `methods-building-blocks.md` | 可根据实际论文调整的分析方法素材 |
| `REPRODUCE.md` | 重跑已保存分析的说明 |

解释结果前，请检查模型与区间诊断。完整文件列表见[输出与核验说明](../skills/hierarchical-masem/references/verification.md)。

## 复现论文教程

通过[党君华（Dang，2026）论文](https://doi.org/10.1177/25152459261466637)获取原始 XLSX 补充材料。本仓库不附带作者数据、原代码或论文 PDF。[来源记录](../skills/hierarchical-masem/assets/tutorial/source.json)保存了预期文件与校验值。

```sh
python3 skills/hierarchical-masem/scripts/masem.py benchmark \
  --project tutorial-check --tutorial-data /path/to/Flow_and_BigFive.xlsx
```

基准检查使用来源记录中指定的补充材料版本。方法细节见[方法说明](method.zh-CN.md)，与作者结果的对照见[验证记录](../validation/README.zh-CN.md)。
