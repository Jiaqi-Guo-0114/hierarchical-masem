# Hierarchical MASEM

**Turn correlations from multiple studies into a reproducible analysis of your theoretical path model.**

[简体中文](README.zh-CN.md) · [Get started](docs/getting-started.md) · [Method](skills/hierarchical-masem/references/method.md) · [Validation](validation/README.md)

Hierarchical MASEM helps psychology and social-science researchers synthesize relationships among several variables, fit a path model, and compare that model across study categories. It handles independent samples nested within studies and carries uncertainty from correlation pooling into the path analysis.

Use it as a **Codex skill** with your data and research question, or run the same **R analysis workflow** from the command line.

## Questions it helps you answer

- **What do the studies say together?** Pool a set of correlations while accounting for the study and sample hierarchy.
- **How does my theoretical model fit the pooled evidence?** Estimate observed-variable paths, their uncertainty, and model fit where the model has testable restrictions.
- **Do paths differ across study categories?** Test overall, specified-path, and pairwise group differences directly.
- **How stable are the conclusions?** Examine working-correlation assumptions, influential studies, and changes in the final path estimates.

## From extraction table to results

| You provide | You receive |
| --- | --- |
| Complete correlation matrices in CSV or XLSX, with study/sample IDs and sample sizes | Data checks, sample accounting, and a pooled correlation matrix |
| Your variables and theoretical path model | Path estimates, 95% likelihood-based intervals, and PNG/PDF figures |
| Optional categorical moderators and planned comparisons | Direct group comparisons with Holm-adjusted tests |
| Analysis choices recorded in a configuration file | A browser-readable results overview, sensitivity results, Methods building blocks, and a reproducible run archive |

## Why use this workflow?

**One connected analysis.** Data checks, correlation pooling, path estimation, group comparisons, and sensitivity analysis use the same inputs and configuration.

**Your research model.** Replace the variables and paths with your own observed-variable model; you are not limited to the tutorial example.

**Results you can inspect and share.** A bilingual results page, editable tables, and publication-friendly figures come with diagnostics, saved code, and a locked R environment. Each run is saved separately so collaborators can inspect and reproduce it.

## Try it

[Download an example results report](https://github.com/Jiaqi-Guo-0114/hierarchical-masem/releases/download/v0.2.0/example-report.html) to see the output before installing. Open the downloaded HTML in a browser; it uses clearly labeled synthetic data.

Start with the bundled synthetic example—no research data required. Follow the [quick start](docs/getting-started.md) to prepare the runtime, then use `demo` to run the example and get a browser-ready results page. Python 3.9+ and R 4.6.0 are required; the current verified platform is macOS.

After [installing the Codex skill](docs/getting-started.md#use-with-codex), you can ask:

> Use hierarchical-masem to analyze these complete Pearson correlation matrices. Independent samples are nested within studies. Fit my theoretical path model, compare the specified study categories, and deliver path estimates, figures, sensitivity results, and reproducibility files.

Prefer a script? The [command-line guide](docs/getting-started.md#try-the-synthetic-example) uses the same analysis engine and includes a complete example.

## Is it right for your study?

This release supports **complete Pearson correlation matrices**, **independent participant samples nested within studies**, **observed-variable acyclic path models**, and **categorical moderator groups that share no studies**.

Incomplete matrices, continuous moderators, overlapping samples, latent or feedback models, and automatic indirect-effect inference need a different workflow. See the [input specification](skills/hierarchical-masem/references/data-contract.md) before preparing a new analysis.

Computational checks support reproducibility; they do not establish the statistical performance of the full procedure in every setting. Correlational paths do not establish causation. The [method guide](skills/hierarchical-masem/references/method.md) explains assumptions and interpretation, including small-study and saturated-model limits.

## Method, license, and citation

Based on the hierarchical two-stage MASEM framework taught by [Dang (2026)](https://doi.org/10.1177/25152459261466637), using `metafor`, `metaSEM`, and `OpenMx`. This repository provides an independent implementation.

The implementation, documentation, and synthetic example are **MIT licensed**. Cite the method, relevant R packages, and the software version used; see [CITATION.cff](CITATION.cff) and [third-party notices](THIRD_PARTY_NOTICES.md). Author tutorial materials are available through the article and are not bundled here.

[Report a bug or suggest an improvement](https://github.com/Jiaqi-Guo-0114/hierarchical-masem/issues). A minimal synthetic example makes a problem easier to reproduce.
