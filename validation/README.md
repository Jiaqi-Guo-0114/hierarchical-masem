# Computational validation

[中文](README.zh-CN.md)

The local release checks were performed on macOS with R 4.6.0 and all 46 pinned dependencies. [computational-validation.json](computational-validation.json) records the counts, source identities, numerical checks and scope. No author-owned input files or confidential local paths are included.

- **Tutorial**: 23 numerical/input groups and 4 offline CLI/reproduction groups. These cover source-code reference agreement, N accounting, correlation/covariance ordering, row permutation, renaming, direct contrasts, multiplicity, underidentification, nonconvergence, rejected unsupported data, archived-code replay and artifact tampering.
- **Intervals**: all five primary, fifteen subgroup, three pairwise and fifteen sensitivity intervals succeed. Seven intervals use fallback profiling; fourteen endpoint fits are independently checked. Both fallback solvers also reproduce successful native intervals within 2e-5.
- **Public package**: five synthetic numerical groups and four CLI/reproduction groups can run without author materials. The example has 8 studies, 10 artificial independent samples and N=2,083. It also includes two separate samples with N=169.
- **Legacy integration**: the separate personal workbench's 59 unit checks and one R integration check passed; its lockfile is unchanged. The legacy module is not part of this public repository.

Run the public checks from a clone with the locked environment already prepared:

```sh
python3 tools/validate_package.py
python3 tools/run_public_checks.py --workdir test-output
```

Pass `--setup` only when restoring dependencies is intended. The script retains logs, JSON reports and synthetic analysis artifacts in the new work directory. An optional [GitHub Actions template](../docs/github-actions.example.yml) supports package checks on pushes and a manual locked-R synthetic suite. It is provided as a template because the publishing credential lacks workflow scope; activate it under `.github/workflows/` with appropriate permissions. A local pass does not imply that a different remote/platform environment has passed.

For the optional author benchmark, use the README's checksum-verified `--tutorial-data` command. Then run `tests/acceptance.R` with the skill directory, runtime path from `check`, returned run directory, output JSON path and original XLSX path. `tests/author_reference.R` additionally needs the original R and XLSX in a user-supplied fixture directory. It preserves the originals and logs the limited adapter.

These checks establish reproducible computation for the declared cases. They do not validate statistical coverage, Type I error, power or general performance of model selection and multigroup inference. Missing matrices, continuous moderators and overlapping samples remain unsupported. Optimizer and interval failures on future data must still be retained.
