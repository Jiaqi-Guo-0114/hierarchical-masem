# Hierarchical MASEM

[简体中文](README.zh-CN.md) · [Method](skills/hierarchical-masem/references/method.md) · [Validation](validation/README.md)

A Codex skill and an executable R workflow for hierarchical two-stage meta-analytic structural equation modeling in psychology and the social sciences. It implements the core framework taught by [Dang (2026)](https://doi.org/10.1177/25152459261466637), with documented corrections and reproducibility checks. The statistical method belongs to the cited authors; this repository provides an independent implementation.

Version **0.1.0** supports complete Pearson correlation matrices from independent participant samples nested within studies, observed-variable acyclic RAM path models, and categorical moderators whose groups share no studies. Incomplete matrices, continuous moderators, overlapping participants, latent/feedback models, and automatic indirect-effect inference are outside this release.

## What it does

- Calculates the complete within-sample sampling covariance using `metafor::rcalc()` on raw correlations.
- Fits all four CS/HCS heterogeneity combinations by REML and selects the admissible minimum-AIC model; reports BIC, eligible nested comparisons, convergence and boundaries.
- Aligns pooled correlations with their covariance and fits `metaSEM::wls()` with implied unit variances and 95% likelihood-based WLS intervals.
- Tests overall, specified path and pairwise group differences directly, with separate declared Holm families.
- Keeps the full sampling covariance fixed in working-correlation sensitivity analyses and follows changes through Stage 2 and moderation.
- Saves validated inputs, estimates, figures, diagnostics, endpoint audits, executable code, a package lock and artifact hashes for each run.

When native interval search fails, a bounded fallback profiles the same WLS objective by fixing the parameter or contrast and refitting nuisance parameters. Recovered endpoints require convergence, unit variances, nonnegative residual variances, positive-definite implied correlations and an independently checked objective cutoff. Unsuccessful recovery remains an explicit failure. No Wald substitution is presented as a likelihood-based interval.

## Install as a skill

Requires Python **3.9+**, R **4.6.0**, and the 46 package versions in the included lockfile. The verified platform is macOS. Other platforms have not been certified by this release; source package installation may require compilers and system libraries.

```sh
git clone https://github.com/Jiaqi-Guo-0114/hierarchical-masem.git
cd hierarchical-masem
mkdir -p ~/.codex/skills
cp -R skills/hierarchical-masem ~/.codex/skills/
```

Use a new Codex session and invoke `$hierarchical-masem`. Inspect an existing skill folder before copying into it. For Codex installations supporting plugins, the optional equivalent route is:

```sh
codex plugin marketplace add Jiaqi-Guo-0114/hierarchical-masem
codex plugin add hierarchical-masem@hierarchical-masem-community
```

Choose either skill or plugin installation. The existing personal `psych-meta-workbench` integration can continue using its own route without installing a second copy.

## Run the synthetic example

The bundled example is artificial software test data. It is not evidence about any psychological association.

```sh
python3 skills/hierarchical-masem/scripts/masem.py setup
python3 skills/hierarchical-masem/scripts/masem.py check
python3 skills/hierarchical-masem/scripts/masem.py init --example --project my-example
python3 skills/hierarchical-masem/scripts/masem.py validate --project my-example
python3 skills/hierarchical-masem/scripts/masem.py run --project my-example
python3 skills/hierarchical-masem/scripts/masem.py verify --run my-example/runs/<returned-run-id>
```

`setup` restores a separate environment keyed by the lockfile hash; it does not modify another analysis project's library. Analysis and verification commands are offline. R itself must already be installed at the pinned version. Each run creates a new directory and archives its actual executable source. `REPRODUCE.md` explains how to rerun it independently of later skill updates.

## Analyze your data

Initialize with `init --project my-analysis`, fill the table, configuration and RAM model, then validate, run and verify as above. A long table needs `study_id`, `sample_id`, `var1`, `var2`, `r`, and `n`; CSV and XLSX column mappings are supported. Provide all off-diagonal correlations for every sample. Sample N is counted once per identity, including distinct samples with identical numeric N.

Confirm sample independence from study coding. IDs cannot prove independence. Define construct directions, duplicate-report crosswalks, the theoretical model and planned/exploratory contrasts before interpretation. See the [data contract](skills/hierarchical-masem/references/data-contract.md).

In Codex, a suitable request is: “Use hierarchical-masem to analyze these complete Pearson matrices from independent samples nested in studies. Fit my RAM model, test the specified categorical group contrasts, and deliver results, sensitivity checks and reproducibility records.”

## Reproduce the tutorial

Author data, code and article PDFs are **not redistributed**. Obtain the original supplement through the [article](https://doi.org/10.1177/25152459261466637). The [source record](skills/hierarchical-masem/assets/tutorial/source.json) identifies the expected files and SHA-256 checksums.

```sh
python3 skills/hierarchical-masem/scripts/masem.py benchmark \
  --project tutorial-check --tutorial-data /path/to/Flow_and_BigFive.xlsx
```

The verified example includes 8 studies, 9 independent samples and **N = 2,377**. The tutorial's `sum(unique(N))` yields 2,208 because two distinct samples both have N = 169. Main path estimates, pooled inputs, four AIC values and the omnibus comparison match the author-code reference within numerical tolerances. Full-V sensitivity, automated model selection, checked likelihood intervals and declared multiplicity families intentionally correct documented source behavior. See the [method and differences](skills/hierarchical-masem/references/method.md).

## Validation and inference limits

The saved local checks include 23 tutorial numerical/input test groups, 4 CLI/reproduction groups, and 5 public synthetic numerical groups. The seven previously unsuccessful tutorial intervals were recovered and independently audited. The standalone public package is also exercised using only the synthetic example. See the [validation record](validation/README.md) for exact results and commands.

This is computational validation. It does **not** establish unbiasedness, nominal coverage, Type I error or power of the integrated selection/Stage 2/multigroup procedure. Inference remains conditional on the selected Stage 1 model, with particular caution for few studies and variance boundaries. A saturated model's perfect fit does not support its theory; nonsignificance does not establish equivalence; correlation paths and study-level moderators do not identify individual causal effects.

Failed fits or intervals stay visible. The toolkit does not perform literature screening, automatic data extraction or submission administration.

## License, citation and contributions

Our implementation, documentation and synthetic example use the **MIT license**. Author materials and R dependencies have their own rights and licenses; see [third-party notices](THIRD_PARTY_NOTICES.md). Cite Dang (2026), the relevant R packages and the exact software version; [CITATION.cff](CITATION.cff) describes this release. Bug reports should include the version, a minimal synthetic example, relevant diagnostics and package information. Do not post confidential extraction data.
