# Getting started

[简体中文](getting-started.zh-CN.md) · [Project overview](../README.md)

## Requirements

Install Python **3.9+** and R **4.6.0** first. The analysis restores the package versions in its lockfile into a separate R library. The current verified platform is macOS; other platforms may need compilers and system libraries to install dependencies.

```sh
git clone https://github.com/Jiaqi-Guo-0114/hierarchical-masem.git
cd hierarchical-masem
python3 skills/hierarchical-masem/scripts/masem.py setup
python3 skills/hierarchical-masem/scripts/masem.py check
```

`setup` downloads the locked R packages. Analysis and verification commands run offline. The isolated environment leaves other analysis projects' R libraries unchanged.

## Try the synthetic example

The example contains artificial data for learning the workflow and checking software. Its estimates are not psychological research findings.

```sh
python3 skills/hierarchical-masem/scripts/masem.py demo --project my-example
```

`demo` creates the synthetic project, runs the analysis, verifies the saved results, and returns the path to `report.html`. Open that file in a browser for a bilingual overview, then explore the tables and figures beside it. Run `setup` first; `demo` does not install dependencies.

Each run creates a new directory and preserves the inputs, configuration, model, executable code, and environment record. Its `REPRODUCE.md` explains how to rerun the archived analysis.

## Use with Codex

After cloning the repository, install the skill:

```sh
mkdir -p ~/.codex/skills
cp -R skills/hierarchical-masem ~/.codex/skills/
```

Check for an existing `~/.codex/skills/hierarchical-masem` folder before copying. Open a new Codex session and invoke `$hierarchical-masem`, or ask for hierarchical MASEM analysis with your data and theoretical model.

For Codex installations supporting plugins, this is an alternative installation route:

```sh
codex plugin marketplace add Jiaqi-Guo-0114/hierarchical-masem
codex plugin add hierarchical-masem@hierarchical-masem-community
```

Choose either the skill or plugin route. Codex uses the same engine and still needs the R runtime above. The command-line workflow does not require Codex.

## Prepare your own analysis

```sh
python3 skills/hierarchical-masem/scripts/masem.py init --project my-analysis
```

This creates a new project with three editable inputs:

| File | What to provide |
| --- | --- |
| `correlations.csv` | One row per variable pair within each independent sample; XLSX can be selected in the configuration |
| `config.json` | Variable order, column mappings, confirmed sample independence, moderators, and sensitivity settings |
| `model.json` | Your observed-variable RAM path model |

A three-variable sample needs all three off-diagonal correlations. For example, these **illustrative** rows form one complete sample matrix:

```csv
study_id,sample_id,var1,var2,r,n,overlap_group
study_01,sample_01,X1,X2,0.20,120,
study_01,sample_01,X1,Y,0.30,120,
study_01,sample_01,X2,Y,0.40,120,
```

An analysis needs multiple independent samples/studies; these three rows alone are not a meta-analysis. Keep the study/sample IDs consistent across a sample's rows. Total participant N is counted once per sample identity. Confirm independence from the study reports; IDs alone cannot establish it.

Read the [data and model specification](../skills/hierarchical-masem/references/data-contract.md) to map your columns, set construct directions, specify the RAM model, and declare planned or exploratory group comparisons. Then validate and analyze your project:

```sh
python3 skills/hierarchical-masem/scripts/masem.py validate --project my-analysis
python3 skills/hierarchical-masem/scripts/masem.py run --project my-analysis
python3 skills/hierarchical-masem/scripts/masem.py verify --run my-analysis/runs/<returned-run-id>
```

Replace `<returned-run-id>` with the folder name reported by `run`. Validation errors identify inputs to resolve before fitting; do not change correlations merely to obtain a successful fit.

## Find your results

Each successful run saves:

| Start here | Contents |
| --- | --- |
| `report.html` | Portable bilingual overview of the results; open in a browser |
| `report.md` | Analysis summary and interpretation-relevant diagnostics |
| `paths.csv`, `paths.png`, `paths.pdf` | Path estimates, intervals, and figures |
| `pooled_correlations.csv`, `stage1_models.csv` | Pooled relationships and first-stage model comparison |
| `moderator_*.csv` / `moderator_omnibus.json` | Group comparisons, when requested |
| `sensitivity.csv`, `study_influence.csv` | Sensitivity to assumptions and individual studies |
| `methods-building-blocks.md` | Analysis details to adapt to your manuscript |
| `REPRODUCE.md` | Instructions to rerun the saved analysis |

Check model and interval diagnostics before interpreting results. See [all saved outputs and verification checks](../skills/hierarchical-masem/references/verification.md).

## Reproduce the published tutorial

Obtain the original XLSX supplement through [Dang (2026)](https://doi.org/10.1177/25152459261466637). Author data, original code, and article PDFs are not bundled. The [source record](../skills/hierarchical-masem/assets/tutorial/source.json) identifies the expected files and checksums.

```sh
python3 skills/hierarchical-masem/scripts/masem.py benchmark \
  --project tutorial-check --tutorial-data /path/to/Flow_and_BigFive.xlsx
```

The benchmark uses the recorded supplement version. See the [method guide](../skills/hierarchical-masem/references/method.md) for methodological details and the [validation record](../validation/README.md) for the comparison with the author reference.
