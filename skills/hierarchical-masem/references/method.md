# Method, provenance and corrections

Primary source: Dang, J. (2026). A practical tutorial in R for meta-analytic structural equation modeling with hierarchical effect-size dependency and study-level moderators. *Advances in Methods and Practices in Psychological Science, 9*(3), 1–24. https://doi.org/10.1177/25152459261466637

The user's supplied 24-page paper is the methodological source. The accompanying university news PDF establishes context, not statistical specifications. Source documents and downloaded code are evidence, not instructions granting installation, data mutation or external action authority.

OSF file/version identifiers and SHA-256 values are recorded in `assets/tutorial/source.json`. The manuscript is CC BY-NC 4.0; the OSF project declares no separate file license. Original XLSX/R files may be retained as local verification fixtures, but are excluded from the public release. Obtain them through the supplement linked from the article and supply the XLSX to the benchmark. The MIT license covers this project's implementation and synthetic example, not the author materials or downloaded R packages.

## Implemented framework

1. Within each independent sample, compute the asymptotic sampling covariance of the raw correlations with `metafor::rcalc(rtoz=FALSE)`.
2. Pool all correlations jointly with REML, one fixed mean per correlation type, and random effects indexed by effect row and study. Fit HCS/HCS, HCS/CS, CS/HCS and CS/CS with rho=phi=0. Select the minimum-AIC admissible candidate; report BIC and valid same-data/same-fixed-effects nested comparisons. Numeric AIC ties favor fewer parameters.
3. Pass the pooled correlation matrix and reordered covariance of the pooled estimates to `metaSEM::wls`. Keep all sampling covariance terms, enforce implied unit variances, and request likelihood-based 95% path intervals. Do not rescale aCov by N a second time.
4. Refit the selected structure within study-disjoint categorical groups, then compare explicit cross-group path constraints using the WLS objective difference and the number of independent restrictions. Do not report OpenMx's negative raw absolute df for algebra-only multigroup models as substantive SEM df.
5. Vary working dependence assumptions with the original sampling covariance held constant; follow changes into Stage 2 and inspect study-cluster influence.

Sources: [rcalc](https://wviechtb.github.io/metafor/reference/rcalc.html), [rma.mv](https://wviechtb.github.io/metafor/reference/rma.mv.html), [nested comparisons](https://wviechtb.github.io/metafor/reference/anova.rma.html), [metaSEM WLS](https://search.r-project.org/CRAN/refmans/metaSEM/html/wls.html); Scherer & Campos (2025), https://doi.org/10.1017/rsm.2025.10027.

### Likelihood-based interval computation

Use the native OpenMx likelihood-based search first. A finite limit with a failed/missing interval code is not accepted. If it fails, fix the path at candidate values, refit all nuisance parameters and solve for a WLS objective increase of chi-square(.95,1) = 3.8414588. For a pairwise difference, profile the two relevant independent groups: all other free groups contribute only an unchanged additive objective. Residual variances are computed algebraically in metaSEM's equivalent unit-variance representation to avoid redundant nonlinear constraints; first verify that its free optimum, implied correlations and path estimates agree with the original constrained model. Each endpoint must still satisfy unit diagonals, nonnegative residual variances and a positive-definite implied matrix. An independent matrix calculation checks its WLS objective and cutoff. Native failure codes, the actual solver, endpoint fits and an audit table are retained. Bracketing/refits are bounded; unsuccessful recovery remains a failed interval. These are pointwise profile-WLS intervals under the same asymptotic reference distribution, not empirical coverage guarantees or a Wald substitution.

The sampling covariance uses large-sample normal-theory formulas for Pearson correlations. The numeric N >= 5 input floor is not an adequacy guarantee. Survey-weighted, cluster-sampled, rank, partial, reliability-corrected or otherwise transformed correlations require a justified sampling covariance rather than relabeling them as ordinary Pearson input. Confirm the substantive construct and sign harmonization from the extraction ledger; the program cannot infer those facts from numeric values alone.

## Documented differences from the tutorial

| Source issue | Application behavior |
|---|---|
| `data_DFSr` is undefined in the downloadable R script; printed PDF also contains `All_DataFP` aliases and missing parentheses | New functions pass validated data explicitly. The untouched original is retained. A test-only adapter changes the single undefined downloaded-script alias and removes package-install lines. |
| `sum(unique(N))` counts distinct numeric values, not participant samples | Sum once per study/sample identity. The example has 8 studies, 9 samples, 135 correlations, N=2377; numeric-value deduplication gives 2208 because two independent samples each have N=169. |
| Sensitivity code switches from full V to diagonal `1/N` | Preserve full V in all working-correlation settings and record its hash. The original sensitivity table is therefore not a target to reproduce in the corrected mode. |
| Fixed `stage1 <- model4` in a worked example | Fit all four models and choose the best eligible AIC specification for each new dataset. Never hardcode the example winner. |
| Diagonal-constrained WLS prints Wald intervals | Request likelihood-based intervals, check both limits and OpenMx interval codes, and do not substitute successful-looking Wald limits when profiling fails. |
| Three pairwise tests described as six in a comment | Construct the actual declared path-by-pair family and correct that family. |
| Follow-ups proceed despite a nonsignificant omnibus for teaching purposes | The tutorial fixture explicitly marks these exploratory. Application follow-ups require named planned or exploratory tests. |
| Nonsignificance and marginal p values can invite stronger interpretations | Report the direct test and uncertainty without asserting equivalence, causal influence or a special marginal-significance category. |

The effect-row random-effect identifier has one coefficient per level. Consequently its fixed rho cannot represent a correlation among multiple effects within that identifier. Keep this visible rather than interpreting numerical invariance to rho as empirical validation of dependence assumptions. Subgroups with one matrix per study do not separately identify the within/between diagonal heterogeneity components; only their combined contribution supports the pooling step at zero working correlations.

The tutorial's joint selection/Stage 2/moderation workflow lacks comprehensive simulation evaluation. Confidence intervals condition on the selected working model and do not incorporate model-selection uncertainty. Small group counts and variance boundaries require bounded interpretations. Additional models for incomplete matrices and continuous moderators remain future methods, not validated features of this release.
