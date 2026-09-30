# 层级 MASEM 元分析结构方程

[English](README.md) · [方法依据](docs/method.zh-CN.md) · [验证记录](validation/README.zh-CN.md)

这是面向心理学与社会科学的 Codex 技能及可执行 R 分析程序，实现了[党君华（Dang，2026）教程](https://doi.org/10.1177/25152459261466637)中的核心层级两阶段 MASEM 流程，并加入有记录的规范修正和复现检查。统计方法归属于所引用的作者，本仓库提供独立实现。

**0.1.0** 支持完整 Pearson 相关矩阵、独立参与者样本嵌套于研究、观测变量无环 RAM 路径模型，以及研究之间互不交叉的分类调节组。缺失相关矩阵、连续调节、参与者重叠、潜变量／反馈模型、自动间接效应推断尚未支持。

## 分析能力

- 用原始相关及 `metafor::rcalc()` 计算每个独立样本的完整抽样协方差。
- 以 REML 拟合四种 CS/HCS 异质性结构，按合格模型中的最小 AIC 选择；同时报告 BIC、适用的嵌套比较、收敛和边界情况。
- 严格对齐合并相关及其渐近协方差，用 `metaSEM::wls()` 拟合理论模型，保持隐含方差为 1，计算 95% likelihood-based WLS 区间。
- 对整体、指定路径及两两组间差异进行直接检验，在声明的不同检验族内分别使用 Holm 校正。
- 敏感性分析始终保留同一完整抽样协方差，并跟踪第二阶段路径与整体调节检验。
- 每次运行保存输入、数值表、图、诊断、区间边界审计、实际执行代码、环境锁及文件校验值。

原生区间搜索失败时，程序固定目标参数或差异，重拟合其余参数，求解同一个 WLS 目标函数的边界。恢复的边界必须满足收敛、单位方差、非负残差方差、隐含矩阵正定，并通过独立目标函数核对。恢复失败仍明确标记；不会把 Wald 区间包装成 likelihood-based 区间。

## 安装为技能

需要 Python **3.9 及以上**、R **4.6.0** 和锁文件中的 46 个包版本。本版实际验证平台为 macOS；其他平台尚未认证，源码安装可能需要编译器和系统依赖。

```sh
git clone https://github.com/Jiaqi-Guo-0114/hierarchical-masem.git
cd hierarchical-masem
mkdir -p ~/.codex/skills
cp -R skills/hierarchical-masem ~/.codex/skills/
```

新开 Codex 会话后使用 `$hierarchical-masem`。复制前检查已有同名技能目录。支持插件的 Codex 也可使用：

```sh
codex plugin marketplace add Jiaqi-Guo-0114/hierarchical-masem
codex plugin add hierarchical-masem@hierarchical-masem-community
```

技能与插件两种方式任选其一。已经接入个人 `psych-meta-workbench` 的用户可继续使用原路由，无须额外安装第二份。

## 运行合成示例

仓库示例是明确标注的人工测试数据，不能作为心理学研究结果解释。

```sh
python3 skills/hierarchical-masem/scripts/masem.py setup
python3 skills/hierarchical-masem/scripts/masem.py check
python3 skills/hierarchical-masem/scripts/masem.py init --example --project my-example
python3 skills/hierarchical-masem/scripts/masem.py validate --project my-example
python3 skills/hierarchical-masem/scripts/masem.py run --project my-example
python3 skills/hierarchical-masem/scripts/masem.py verify --run my-example/runs/<返回的运行编号>
```

`setup` 根据锁文件校验值恢复单独环境，不修改其他研究的 R 库。分析与核验离线运行；R 本身需预先安装为指定版本。每次运行创建新目录并归档实际执行的源代码，`REPRODUCE.md` 说明如何独立于后续技能更新重跑。

## 分析真实数据

用 `init --project my-analysis` 创建空白模板，填写数据、配置和 RAM 模型，然后依次校验、运行、核验。长表至少包含研究标识、独立样本标识、两个变量名、原始相关 r 和样本量 n；支持 CSV/XLSX 的列名映射。每个样本必须提供完整的非对角相关。总人数按样本身份累计，不会合并人数恰好相同的独立样本。

样本独立性需由研究编码确认，ID 本身不能证明。解释前明确构念方向、重复报告对应关系、理论模型及预设／探索性比较。详见[输入规范](skills/hierarchical-masem/references/data-contract.md)。

可直接向 Codex 提出：“用 hierarchical-masem 分析这些完整 Pearson 相关矩阵。独立样本嵌套于研究，按我提供的 RAM 理论模型拟合两阶段 MASEM，检验指定分类调节差异，并交付结果、敏感性分析和可复现记录。”

## 复现作者教程

作者原始数据、R 代码和论文 PDF **不随本开源仓库分发**。请通过[论文](https://doi.org/10.1177/25152459261466637)中的补充材料入口取得原文件。[来源记录](skills/hierarchical-masem/assets/tutorial/source.json)保存文件身份和 SHA-256 校验值。

```sh
python3 skills/hierarchical-masem/scripts/masem.py benchmark \
  --project tutorial-check --tutorial-data /path/to/Flow_and_BigFive.xlsx
```

核验示例包含 8 项研究、9 个独立样本，正确总人数为 **2,377**。原代码 `sum(unique(N))` 得到 2,208，因为两个独立样本的人数恰好都为 169。主路径估计、合并相关及其协方差、四个 AIC 和整体调节比较与作者代码在数值容差内一致。完整 V 敏感性、自动模型选择、区间核验和明确检验族属于有记录的规范修正。详见[方法与技术差异](docs/method.zh-CN.md)。

## 验证与解释范围

本地保存的检查包括 23 组教程数值／输入检查、4 组命令行／复现检查，以及 5 组公开合成示例数值检查。教程原先失败的 7 个区间已恢复，并逐项核对边界。独立公开包也仅使用合成示例贯通验证。具体记录与运行命令见[验收说明](validation/README.zh-CN.md)。

这些是计算验证，不能证明整个模型选择、第二阶段和多组检验流程具有无偏估计、标称覆盖率、第一类错误率或功效保证。推断条件于所选第一阶段模型，小研究数及方差边界尤其需要谨慎。饱和模型的完美拟合不能支持理论，非显著不能说明等效，相关路径与研究层面调节不能识别个体因果效应。

拟合和区间失败保持可见。本工具不扩展至文献筛选、自动数据提取或投稿行政流程。

## 许可、引用与参与

本项目的实现、文档和合成示例采用 **MIT 许可**。作者材料与 R 依赖遵循各自权利及许可，详见[第三方说明](THIRD_PARTY_NOTICES.md)。研究使用时请引用 Dang（2026）、相关 R 包及准确软件版本；软件引用信息见 [CITATION.cff](CITATION.cff)。反馈问题请提供版本、最小合成示例、相关诊断及包版本，不公开上传保密研究数据。
