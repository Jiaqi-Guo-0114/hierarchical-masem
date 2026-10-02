# 层级 MASEM 元分析结构方程

**把多项研究的相关数据，转化为可复现的理论路径模型分析。**

[**下载完整分析包 ZIP**](https://github.com/Jiaqi-Guo-0114/hierarchical-masem/releases/latest/download/hierarchical-masem.zip) · [先看示例报告](https://github.com/Jiaqi-Guo-0114/hierarchical-masem/releases/latest/download/example-report.html) · [所有版本](https://github.com/Jiaqi-Guo-0114/hierarchical-masem/releases/latest)

[English](README.md) · [开始使用](docs/getting-started.zh-CN.md) · [方法依据](docs/method.zh-CN.md) · [验证记录](validation/README.zh-CN.md)

Hierarchical MASEM 面向心理学与社会科学研究者，帮助你综合多个变量之间的关系、拟合理论路径模型，并比较不同研究类别的路径差异。它处理独立样本嵌套于研究的层级结构，并把合并相关的不确定性传递到路径分析。

你可以把数据和研究问题交给 **Codex 技能**，也可以通过命令行运行同一套 **R 分析程序**。

## 它能帮你回答什么问题？

- **把已有研究放在一起，变量之间是什么关系？** 在考虑研究与样本层级的基础上，合并一组相关系数。
- **我的理论模型与综合证据是否一致？** 估计观测变量间的路径及其不确定性；模型存在可检验约束时，评估模型拟合。
- **不同研究类别的路径是否存在差异？** 直接检验整体、指定路径和两两组间差异。
- **结论对分析选择有多敏感？** 检查工作相关假设、影响较大的研究，以及最终路径估计的变化。

## 从提取数据到分析结果

| 你提供 | 你获得 |
| --- | --- |
| CSV 或 XLSX 完整相关矩阵，以及研究／样本标识和样本量 | 数据检查、样本统计与合并相关矩阵 |
| 变量定义与理论路径模型 | 路径估计、95% likelihood-based 区间及 PNG/PDF 图 |
| 可选的分类调节变量与预设比较 | 直接组间比较及 Holm 校正后的检验结果 |
| 配置文件中的分析选择 | 浏览器可读的结果总览、敏感性结果、Methods 写作素材与可复现运行档案 |

## 为什么选择这套工作流？

**一次配置，贯通分析。** 数据检查、相关合并、路径估计、组间比较和敏感性分析共享同一套输入与配置。

**围绕你的研究模型。** 变量与路径可以替换成自己的观测变量模型，分析不局限于教程示例。

**结果可检查，也便于协作。** 中英双语结果页、可编辑表格与适合论文使用的图形，配套诊断信息、实际运行代码和锁定的 R 环境。每次分析单独保存，便于团队核查与复现。

## 开始使用

也可以先[下载示例结果报告](https://github.com/Jiaqi-Guo-0114/hierarchical-masem/releases/latest/download/example-report.html)，直观看到分析交付效果。用浏览器打开下载的 HTML 即可；示例使用明确标注的合成数据。

先运行仓库自带的合成示例，无需准备真实研究数据。按[入门指南](docs/getting-started.zh-CN.md)准备环境后，使用 `demo` 即可试跑并查看结果页。需要 Python 3.9 及以上、R 4.6.0；当前已验证的平台为 macOS。

[安装 Codex 技能](docs/getting-started.zh-CN.md#在-codex-中使用)后，可以直接提出：

> 用 hierarchical-masem 分析这些完整 Pearson 相关矩阵。独立样本嵌套于研究，请按我的理论路径模型拟合，比较指定研究类别，并交付路径估计、图表、敏感性分析和可复现文件。

习惯运行脚本？[命令行指南](docs/getting-started.zh-CN.md#试跑合成示例)使用同一个分析引擎，并提供完整示例。

## 适合你的研究吗？

本版支持 **完整 Pearson 相关矩阵**、**独立参与者样本嵌套于研究**、**观测变量无环路径模型**，以及 **研究之间互不交叉的分类调节组**。

缺失相关矩阵、连续调节、样本重叠、潜变量或反馈模型，以及自动间接效应推断，需要其他分析流程。准备新数据前，请查看[输入规范](skills/hierarchical-masem/references/data-contract.md)。

计算验证支持结果复现，不能证明完整流程在所有情形下的统计表现；相关路径也不能建立因果关系。[方法说明](docs/method.zh-CN.md)介绍了适用假设与解释边界，包括研究数量较少和饱和模型时的限制。

## 方法、许可与引用

本项目基于[党君华（Dang，2026）教程](https://doi.org/10.1177/25152459261466637)中的层级两阶段 MASEM 框架，使用 `metafor`、`metaSEM` 和 `OpenMx`，提供独立实现。

实现、文档与合成示例采用 **MIT 许可**。研究使用时请引用原方法、相关 R 包和实际使用的软件版本，参见 [CITATION.cff](CITATION.cff) 与[第三方说明](THIRD_PARTY_NOTICES.md)。作者教程材料请通过论文获取，本仓库不附带分发。

欢迎[反馈问题或提出改进建议](https://github.com/Jiaqi-Guo-0114/hierarchical-masem/issues)。附上最小合成示例，能帮助我们复现问题。
