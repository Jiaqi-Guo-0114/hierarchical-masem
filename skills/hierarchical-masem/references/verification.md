# Verification and saved outputs

The v0.2.0 release passed 23 tutorial numerical/input groups and the 43 public example, CLI, configuration and report checks on 2026-10-02; see the [saved validation record](validation-record.json). All requested tutorial intervals succeeded, including seven recovered by checked profile refits. Earlier schema-1 archives remain verifiable. This is computational validation, not simulation validation of coverage or error rates.

`check` verifies the R version and all 46 locked package versions in the isolated library. Runtime paths are keyed by the lockfile hash. The old workbench lock is untouched. `setup` restores this new environment; other commands do not download or update software.

`run` first validates inputs, then creates a new timestamped run directory. It snapshots data, model, config, lockfile and executable scripts. It never overwrites an earlier run. Failed runs retain `failure.json` and logs and have no success manifest.

Successful runs contain:

- `data_checks.json`, `sample_registry.csv`: actual study/sample/N accounting.
- `stage1_models.csv`, `stage1_comparisons.csv`, `stage1_attempts.json`: selection, nested comparisons, and candidate failures.
- `pooled_pairs.csv`, `pooled_correlations.csv`, `pooled_acov.csv`: estimates and correctly aligned Stage 2 inputs.
- `paths.csv`, `paths.png`, `paths.pdf`: model paths and checked likelihood-based intervals.
- `profile_audit.csv`: recovered profile endpoints, convergence, independent WLS objectives, chi-square cutoffs, unit-variance errors and admissibility.
- `group_paths.csv`, group matrices, `moderator_omnibus.json`, `moderator_path_tests.csv`, `moderator_pairwise.csv` when moderation applies.
- `sensitivity.csv`, `moderator_sensitivity.csv`, `study_influence.csv`, and BIC-alternative path output when the criteria select different models.
- `report.html`: standalone bilingual overview with paths, direct comparisons and robustness results; no external assets or network access.
- `report.md`, `methods-building-blocks.md`: result summary and analysis-only Methods building blocks; no invented search strategy, ethics declaration, or preregistration.
- `technical-notes.json`, `results.json`, `fit_objects.rds`, `sessionInfo.txt`, `run.log`, `manifest.json`, input and code snapshots.

`verify` checks all artifact hashes, required outputs, N reconciliation, saved model estimates, matrix definiteness, diagonal constraints, interval integrity and sampling-V invariance. Recovered endpoints are independently evaluated with discrepancy-transpose inverse(aCov) discrepancy; the objective cutoff tolerance is 1e-4, unit-diagonal tolerance 1e-5. For a saturated multiple-predictor regression it independently evaluates beta = inverse(Rxx) Rxy, residual variance and the delta-method covariance J aCov J-transpose. Estimate tolerance is 5e-5, SE tolerance 1e-4. These checks detect ordering, covariance-scaling and numerical errors; they do not demonstrate nominal statistical coverage.

The acceptance suite tests the author fixture, row permutations and construct renaming; complete-matrix counts and same-N independent samples; duplicate/reversed pairs, missing correlations, non-PD matrices, overlap, continuous moderators, cross-group studies, underidentification and nonconvergence; offline execution and manifest tampering. Repeat runs compare scientific outputs rather than timestamps or optimizer log wording.

Preserve failed optimizers and confidence intervals as failures. A boundary heterogeneity estimate or small group count can be a valid diagnostic rather than a software defect. Do not erase them to make the report appear clean. The human-readable report contains inference-relevant limitations; detailed internal repair history stays in the technical record.

Run the saved numerical acceptance suite with `Rscript --vanilla <skill>/tests/acceptance.R <skill> <runtime> <tutorial-run> <acceptance.json> <author-XLSX>`. Run the author-code comparison separately with `tests/author_reference.R <skill> <runtime> <existing-output-directory> <user-supplied-fixture-dir>`; this checks both source hashes and never modifies the original author code. Its legacy multigroup fit can return status 6 on the locked runtime, which must be reported rather than treated as a verified optimum. The fixture directory needs the two original filenames recorded in source.json. Public `tests/example_acceptance.R` and `tests/cli_acceptance.py` use synthetic data without author fixtures.
