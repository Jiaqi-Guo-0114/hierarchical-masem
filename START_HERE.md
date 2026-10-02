# 从这里开始 · Start here

## 中文

这个分析包包含 Codex 技能、R 分析程序、输入模板、合成示例和中英文指南。

1. 解压后，在终端进入这个 `hierarchical-masem` 文件夹。
2. 安装 Python 3.9 及以上、R 4.6.0；包内不含这两个运行环境。当前验证平台为 macOS。
3. 依次运行下方命令。首次 `setup` 需要联网获取锁定的 R 包；后续示例分析离线运行。

```sh
python3 skills/hierarchical-masem/scripts/masem.py setup
python3 skills/hierarchical-masem/scripts/masem.py check
python3 skills/hierarchical-masem/scripts/masem.py demo --project my-example
```

完成后，用浏览器打开命令返回的 `report.html`。示例使用合成数据，用于熟悉软件。

准备自己的数据或安装 Codex 技能，请看[中文入门指南](docs/getting-started.zh-CN.md)。

## English

This package includes the Codex skill, R analysis code, input templates, a synthetic example, and bilingual guides.

1. Extract the ZIP and open a terminal in this `hierarchical-masem` folder.
2. Install Python 3.9+ and R 4.6.0; neither runtime is bundled. The verified platform is macOS.
3. Run the three commands above. Initial `setup` downloads the locked R packages; the example analysis then runs offline.

Open the returned `report.html` path in a browser. The example uses synthetic data to demonstrate the software.

To prepare your own data or install the Codex skill, see the [getting-started guide](docs/getting-started.md).
