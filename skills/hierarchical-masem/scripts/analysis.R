sensitivity <- function(x,selected,sam,primary) {
  settings<-x$cfg$sensitivity$settings %||% list(c(0,0),c(.5,.5),c(1,1))
  settings<-lapply(settings,asvec)
  if(any(lengths(settings)!=2L)||any(!is.finite(unlist(settings)))||any(unlist(settings)<0|unlist(settings)>1))
    fail('Sensitivity settings must be [rho,phi] pairs in [0,1].')
  rows<-list();diagnostics<-character();profiles<-list();hash<-digest::digest(sam$V,algo='sha256')
  for(setting in settings){
    rr<-setting[1];pp<-setting[2]
    attempt<-capture_fit({
      f<-if(rr==0&&pp==0)list(object=selected$fit) else pool_fit(sam$data,sam$V,selected$structure,rr,pp)
      if(is.null(f$object))fail(f$error)
      inp<-pool_inputs(f$object,x$pairs,x$model$variables)
      sem<-if(rr==0&&pp==0)primary else fit_sem(inp,x$model,x$checks$n_total,name='sensitivity')
      list(sem=sem,fit=f$object,b=inp$b,pooled=inp)
    })
    if(is.null(attempt$object)){
      diagnostics<-c(diagnostics,paste0('Sensitivity rho=',rr,', phi=',pp,' failed: ',attempt$error))
      rows[[length(rows)+1]]<-data.frame(rho=rr,phi=pp,path=NA_character_,estimate=NA_real_,ci_lower=NA_real_,ci_upper=NA_real_,ci_status='failed',change_from_primary=NA_real_,max_correlation_change=NA_real_,V_sha256=hash,status='failed',message=attempt$error)
    }else{
      ob<-attempt$object;tab<-ob$sem$paths
      if(!(rr==0&&pp==0)&&length(ob$sem$profiles))profiles[[paste(rr,pp,sep='/')]]<-ob
      rows[[length(rows)+1]]<-data.frame(rho=rr,phi=pp,path=tab$path,estimate=tab$estimate,ci_lower=tab$ci_lower,ci_upper=tab$ci_upper,ci_status=tab$ci_status,
        change_from_primary=tab$estimate-primary$paths$estimate[match(tab$path,primary$paths$path)],
        max_correlation_change=max(abs(ob$b-pool_inputs(selected$fit,x$pairs,x$model$variables)$b)),
        V_sha256=hash,status='ok',message='')
    }
  }
  loo<-data.frame()
  if(isTRUE(x$cfg$sensitivity$leave_one_study_out)){
    lrows<-list()
    for(study in sort(unique(x$data$study_id))){
      q<-capture_fit({
        dd<-x$data[x$data$study_id!=study,,drop=FALSE]
        if(length(unique(dd$study_id))<2L)fail('Too few studies remain.')
        ss<-x$sampling(dd);ff<-pool_fit(ss$data,ss$V,selected$structure)
        if(is.null(ff$object))fail(ff$error)
        inp<-pool_inputs(ff$object,x$pairs,x$model$variables)
        n<-sum(x$registry$n[x$registry$study_id!=study])
        fit_sem(inp,x$model,n,name='leave_one_study_out',intervals=FALSE)
      })
      if(is.null(q$object))lrows[[length(lrows)+1]]<-data.frame(omitted_study=study,path=NA_character_,estimate=NA_real_,change_from_primary=NA_real_,status='failed',message=q$error)
      else{
        tab<-q$object$paths
        lrows[[length(lrows)+1]]<-data.frame(omitted_study=study,path=tab$path,estimate=tab$estimate,
           change_from_primary=tab$estimate-primary$paths$estimate[match(tab$path,primary$paths$path)],status='ok',message='')
      }
    }
    loo<-do.call(rbind,lrows)
  }
  list(grid=do.call(rbind,rows),loo=loo,diagnostics=diagnostics,profiles=profiles)
}

profile_records <- function(obj) {
  rows<-list()
  add<-function(profile,name,pools,base_objective){
    for(side in names(profile$endpoints)){
      end<-profile$endpoints[[side]];f<-end$fit;check_mx(f)
      independent<-0;unit_error<-0;mineig<-Inf;minvar<-Inf
      for(g in names(pools)){
        m<-if(g=='single')f else f[[g]];a<-profile_admissibility(m);inp<-pools[[g]]
        implied<-OpenMx::mxEvalByName('impliedS',m)
        discrepancy<-inp$R[lower.tri(inp$R)]-implied[lower.tri(implied)]
        independent<-independent+as.numeric(crossprod(discrepancy,solve(inp$acov,discrepancy)))
        unit_error<-max(unit_error,a$unit_diagonal_error);mineig<-min(mineig,a$minimum_implied_eigenvalue)
        minvar<-min(minvar,a$minimum_residual_variance)
      }
      delta<-independent-base_objective
      if(abs(independent-f@output$fit)>1e-5||abs(delta-profile$cutoff)>1e-4)fail('Independent WLS objective check failed at a profile endpoint.')
      if(!is.null(end$restriction_error)&&end$restriction_error>1e-5)fail('Saved profile contrast restriction invalid.')
      rows[[length(rows)+1]]<<-data.frame(interval=name,side=side,bound=end$value,
        objective=f@output$fit,independent_objective=independent,objective_increase=delta,
        cutoff=profile$cutoff,cutoff_error=abs(delta-profile$cutoff),optimizer_status=f@output$status$code,
        unit_diagonal_error=unit_error,minimum_implied_eigenvalue=mineig,minimum_residual_variance=minvar,
        restriction_error=end$restriction_error %||% 0,evaluations=profile$evaluations,status='pass')
    }
  }
  for(p in names(obj$primary$profiles))add(obj$primary$profiles[[p]],paste('overall',p,sep='/'),list(single=obj$pooled),obj$primary$fit@output$fit)
  mod<-obj$moderator
  if(!is.null(mod)){
    for(g in names(mod$fits))for(p in names(mod$fits[[g]]$profiles))add(mod$fits[[g]]$profiles[[p]],paste(g,p,sep='/'),list(single=mod$group_pool[[g]]),mod$fits[[g]]$fit@output$fit)
    for(p in names(mod$contrast_profiles)){
      groups<-strsplit(p,'/',fixed=TRUE)[[1]][2:3]
      add(mod$contrast_profiles[[p]],p,mod$group_pool[groups],sum(vapply(mod$fits[groups],function(z)z$fit@output$fit,0.0)))
    }
  }
  for(s in names(obj$sensitivity$profiles)){
    z<-obj$sensitivity$profiles[[s]]
    for(p in names(z$sem$profiles))add(z$sem$profiles[[p]],paste('sensitivity',s,p,sep='/'),list(single=z$pooled),z$sem$fit@output$fit)
  }
  if(length(rows))do.call(rbind,rows) else data.frame(interval=character(),side=character(),bound=numeric(),status=character())
}

independent_oracle <- function(R,acov,spec,paths) {
  # Closed-form multivariate regression oracle, independent of OpenMx.
  p<-nrow(R);outcomes<-unique(spec$paths$i)
  if(length(outcomes)!=1L||length(spec$paths$path)!=p-1L)return(list(status='not_applicable'))
  y<-outcomes[1];xx<-setdiff(seq_len(p),y)
  # This oracle is exact only for an unrestricted predictor correlation block.
  sx<-spec$Sl[xx,xx,drop=FALSE]
  if(any(!nzchar(sx[lower.tri(sx)])) || anyDuplicated(sx[lower.tri(sx)]) ||
     any(spec$S[y,xx]!='0') || any(spec$S[xx,y]!='0') ||
     any(diag(spec$S)[xx]!='1') || !nzchar(spec$Sl[y,y]))return(list(status='not_applicable'))
  fun<-function(r){m<-diag(p);m[lower.tri(m)]<-r;m[upper.tri(m)]<-t(m)[upper.tri(m)];
                   as.numeric(solve(m[xx,xx,drop=FALSE],m[xx,y]))}
  beta<-fun(R[lower.tri(R)]);J<-numDeriv::jacobian(fun,R[lower.tri(R)])
  covbeta<-J%*%acov%*%t(J)
  ix<-match(xx,paths$j)
  esterr<-max(abs(beta-paths$estimate[ix]));seerr<-max(abs(sqrt(diag(covbeta))-paths$se[ix]))
  list(status=if(esterr<5e-5 && is.finite(seerr)&&seerr<1e-4)'pass' else 'fail',
       max_estimate_error=esterr,max_se_error=seerr,estimate=beta,se=sqrt(diag(covbeta)),
       residual_variance=as.numeric(1-t(R[xx,y])%*%solve(R[xx,xx,drop=FALSE],R[xx,y])))
}

write_report <- function(x,selected,sem,mod,sens,diagnostics,out) {
  tab<-sem$paths
  synthetic<-is.character(x$cfg$data_role) && length(x$cfg$data_role)==1L &&
    grepl('^synthetic([_-]|$)',x$cfg$data_role,ignore.case=TRUE)
  synthetic_zh<-if(synthetic)'**合成数据演示：以下结果来自人工软件测试数据，不能作为心理学研究证据。**' else character()
  synthetic_en<-if(synthetic)'**SYNTHETIC DEMONSTRATION: These results use artificial software test data and are not psychological research evidence.**' else character()
  failed_intervals<-sum(!tab$ci_status %in% 'ok')+sum(!sens$grid$ci_status %in% 'ok')+
    if(is.null(mod))0L else sum(!mod$group_paths$ci_status %in% 'ok')+sum(!mod$pairwise$ci_status %in% 'ok')
  has_grid<-is.data.frame(sens$grid) && nrow(sens$grid)>0L
  sensitivity_zh<-if(has_grid)'敏感性分析保持完整抽样协方差不变，并将替代工作相关设定传递到第二阶段。' else '本次未执行工作相关设定的敏感性分析。'
  sensitivity_en<-if(has_grid)'Sensitivity analyses held the sampling covariance fixed while varying the working random-effects correlations.' else 'Working-correlation sensitivity analyses were not performed in this run.'
  has_loo<-is.data.frame(sens$loo) && nrow(sens$loo)>0L
  if(has_loo){
    loo_status<-vapply(split(sens$loo$status,sens$loo$omitted_study),function(z)all(z %in% 'ok'),TRUE)
    loo_ok<-sum(loo_status);loo_failed<-sum(!loo_status)
    loo_zh<-sprintf('逐研究删除诊断固定主分析的异质性结构；%d 项重拟合成功，%d 项失败。',loo_ok,loo_failed)
    loo_en<-sprintf('Leave-one-study-out diagnostics retained the selected heterogeneity structure; %d study-deletion refits succeeded and %d failed.',loo_ok,loo_failed)
  }else{
    loo_zh<-'本次未执行逐研究删除诊断。'
    loo_en<-'Leave-one-study-out diagnostics were not performed in this run.'
  }
  lines<-c('# 层级 MASEM 分析结果','',synthetic_zh,if(synthetic)'',sprintf('纳入 %d 项研究、%d 个独立样本、%d 个相关系数；总样本量为 %d。',x$checks$n_studies,x$checks$n_samples,x$checks$n_correlations,x$checks$n_total),'',
    '第一阶段在原始 Pearson 相关尺度上使用完整抽样协方差，比较四种 CS/HCS 随机效应结构。',
    paste0('按 AIC 选择：',selected$selected,'。第二阶段使用合并相关及其渐近协方差进行 WLS 路径分析。区间为 95% likelihood-based 区间。'),'',
    '| 路径 | 估计 | 95% 区间 | 区间状态 |','|---|---:|---|---|')
  for(i in seq_len(nrow(tab))){
    bound<-if(tab$ci_status[i]=='ok')sprintf('[%.4f, %.4f]',tab$ci_lower[i],tab$ci_upper[i]) else '未求得有效区间'
    lines<-c(lines,sprintf('| %s → %s | %.4f | %s | %s |',tab$predictor[i],tab$outcome[i],tab$estimate[i],bound,tab$ci_status[i]))
  }
  if(sem$stats$saturated)lines<-c(lines,'','该路径模型为饱和模型（df = 0），整体拟合不能用来支持理论结构。')
  else lines<-c(lines,'',sprintf('WLS χ²(%d) = %.4f，p = %.4f。',sem$stats$df,sem$stats$chi_square,sem$stats$p))
  has_followups<-!is.null(mod) && (nrow(mod$path_tests)>0L || nrow(mod$pairwise)>0L)
  if(!is.null(mod))lines<-c(lines,'',sprintf('分类调节整体检验：Δχ²(%d) = %.4f，p = %.4f。',mod$omnibus$df,mod$omnibus$delta_chi_square,mod$omnibus$p_raw),
    if(has_followups)paste0('后续比较角色：',x$cfg$moderation$mode %||% 'none','；请求的逐路径和两两比较分别在各自声明的检验族内使用 Holm 校正。'),
    if(nrow(mod$pairwise)>0L)'两两差异区间为未作同时覆盖校正的 95% 区间。',
    '非显著结果表示未检出组间差异，不构成等效性证据。')
  if(!is.null(mod)){
    nf<-sum(mod$group_paths$ci_status!='ok')+sum(mod$pairwise$ci_status!='ok')
    if(nf>0)lines<-c(lines,'',sprintf('亚组路径与组间差异中有 %d 个区间未得到有效解，已在对应表格标记为 failed；这些数值边界不能作为有效置信区间引用。',nf))
  }
  if(failed_intervals>0L)lines<-c(lines,'',sprintf('本次分析中有 %d 个请求的区间未得到有效解，详见路径、调节与敏感性表中的区间状态；失败的数值边界不能作为有效置信区间引用。',failed_intervals))
  lines<-c(lines,'',sensitivity_zh,loo_zh,
    '路径系数表示基于综合相关的条件关联；组间调节属于研究层面的比较，不提供个体层面的因果证据。',
    '本教程所整合的工作模型选择和多组检验流程尚缺系统模拟验证；推断及区间均条件于所选第一阶段模型。')
  writeLines(lines,file.path(out,'report.md'),useBytes=TRUE)
  method<-c('# Methods building blocks','',synthetic_en,if(synthetic)'',sprintf('The analysis included %d studies contributing %d independent samples (N = %d).',x$checks$n_studies,x$checks$n_samples,x$checks$n_total),
    'Raw Pearson correlation matrices were synthesized using multilevel multivariate random-effects models. Sampling covariances were calculated within independent samples using metafor::rcalc. Four combinations of compound-symmetry and heterogeneous compound-symmetry heterogeneity structures were estimated by restricted maximum likelihood, with identical fixed effects and sampling covariance inputs. The lowest-AIC admissible model was selected; BIC and nested working-model comparisons were also reported.',
    paste0('The selected structure was ',selected$selected,'. The pooled correlation vector and its estimated covariance were aligned by variable-pair identifiers before fitting the specified structural model with metaSEM::wls. Implied variances were constrained to one. Ninety-five percent likelihood-based intervals were sought using native interval searches or, when these failed, by fixing the target parameter or contrast and refitting nuisance parameters until the WLS objective increased by the 95th percentile of a one-degree-of-freedom chi-square distribution. Accepted profile endpoints were checked for convergence, unit variances, matrix admissibility, and agreement with an independently evaluated WLS objective.'),
    if(failed_intervals>0L)sprintf('%d requested intervals could not be estimated successfully and remain explicitly marked as failed in the corresponding output tables.',failed_intervals),
    sensitivity_en,loo_en,'Inference was conditional on the selected Stage 1 model; the integrated workflow has not been comprehensively evaluated in simulation.',
    if(!is.null(mod))'The categorical moderator was analyzed through independent study-disjoint groups. Equality constraints were compared using differences in the WLS fit function.',
    if(has_followups)paste0('Follow-up comparisons were classified as ',x$cfg$moderation$mode %||% 'none',', with Holm adjustment within the declared path and pairwise families.'))
  writeLines(method,file.path(out,'methods-building-blocks.md'),useBytes=TRUE)
  jwrite(list(diagnostics=diagnostics,corrections=c('N is summed once per study/sample identity, not once per distinct numeric sample size.',
    'Sampling covariance V is unchanged in rho/phi sensitivity analyses.',
    'No undefined data_DFSr or All_DataFP aliases.',
    'WLS objective differences and explicit restriction degrees of freedom are reported instead of negative raw OpenMx absolute df.',
    'Follow-up testing is explicitly classified and multiplicity families contain the actual number of comparisons.')),
    file.path(out,'technical-notes.json'))
}

plots <- function(inp,sem,out) {
  draw<-function(){
    tab<-sem$paths;tab$ci_lower[tab$ci_status!='ok']<-tab$ci_upper[tab$ci_status!='ok']<-NA_real_
    n<-nrow(tab);lo<-range(c(tab$estimate,tab$ci_lower,tab$ci_upper,0),finite=TRUE)
    if(length(lo)!=2||!all(is.finite(lo)))lo<-range(c(tab$estimate,0))
    par(mar=c(5,9,2,1));plot(tab$estimate,rev(seq_len(n)),xlim=lo+diff(lo)*c(-.08,.08),ylim=c(.5,n+.5),yaxt='n',ylab='',xlab='Conditional association (95% likelihood-based CI)',pch=19,col='#315B7D')
    axis(2,at=rev(seq_len(n)),labels=paste(tab$predictor,'->',tab$outcome),las=1,cex.axis=.85)
    segments(tab$ci_lower,rev(seq_len(n)),tab$ci_upper,rev(seq_len(n)),col='#315B7D',lwd=2);abline(v=0,lty=2,col='grey60')
    if(any(tab$ci_status!='ok'))mtext('Points without bars: interval estimation failed',side=3,cex=.7)
  }
  grDevices::png(file.path(out,'paths.png'),width=1500,height=900,res=160);draw();dev.off()
  grDevices::pdf(file.path(out,'paths.pdf'),width=9,height=5.5);draw();dev.off()
}

analyze <- function(project,out) {
  x<-read_inputs(project);set.seed(x$cfg$seed %||% 20260930)
  OpenMx::mxOption(NULL,'Number of Threads',1)
  sam<-x$sampling(x$data)
  cat('Fitting four Stage 1 working models\n')
  selected<-select_pool(sam$data,sam$V,x$pairs,x$model$variables)
  inp<-pool_inputs(selected$fit,x$pairs,x$model$variables)
  cat('Stage 2 and likelihood-based intervals\n')
  sem<-fit_sem(inp,x$model,x$checks$n_total)
  diagnostics<-c('The ES-level identifier is unique per row, so rho does not induce cross-effect covariance at that level; phi varies the study-level working covariance.',
    'Variance-component likelihood comparisons use asymptotic reference distributions; boundary estimates can invalidate ordinary reference calibration.')
  if(x$checks$few_studies)diagnostics<-c(diagnostics,'Fewer than ten studies: heterogeneity and moderator inference can be imprecise; no automatic publication-bias inference.')
  if(any(selected$table$status!='ok'))diagnostics<-c(diagnostics,'Some candidate Stage 1 models failed; selection uses only eligible models. See stage1_attempts.json.')
  if(any(sem$paths$ci_status!='ok'))diagnostics<-c(diagnostics,'Some primary likelihood-based intervals failed; see paths.csv. No substituted intervals are reported.')
  if(any(selected$fit$tau2<1e-8)||any(selected$fit$gamma2<1e-8))diagnostics<-c(diagnostics,'At least one heterogeneity variance is on or close to its lower boundary.')
  cwrite(selected$table,file.path(out,'stage1_models.csv'));cwrite(selected$lrts,file.path(out,'stage1_comparisons.csv'))
  jwrite(selected$attempts,file.path(out,'stage1_attempts.json'))
  cwrite(cbind(variable=rownames(inp$R),as.data.frame(inp$R)),file.path(out,'pooled_correlations.csv'))
  cwrite(cbind(pair=rownames(inp$acov),as.data.frame(inp$acov)),file.path(out,'pooled_acov.csv'))
  pooled<-x$pairs;pooled$estimate<-as.numeric(inp$b);pooled$se<-sqrt(diag(inp$acov))
  pooled$ci_lower<-pooled$estimate-qnorm(.975)*pooled$se;pooled$ci_upper<-pooled$estimate+qnorm(.975)*pooled$se
  cwrite(pooled,file.path(out,'pooled_pairs.csv'));cwrite(sem$paths,file.path(out,'paths.csv'))
  cwrite(x$registry,file.path(out,'sample_registry.csv'));jwrite(x$checks,file.path(out,'data_checks.json'))
  cat('Sensitivity and study influence diagnostics\n')
  sens<-sensitivity(x,selected,sam,sem);diagnostics<-c(diagnostics,sens$diagnostics)
  if(any(sens$grid$ci_status!='ok'))diagnostics<-c(diagnostics,'Sensitivity interval failures are retained explicitly.')
  if(nrow(sens$loo)&&any(sens$loo$status!='ok'))diagnostics<-c(diagnostics,'Some leave-one-study-out refits failed; see study_influence.csv.')
  cwrite(sens$grid,file.path(out,'sensitivity.csv'));cwrite(sens$loo,file.path(out,'study_influence.csv'))
  bic<-selected$table$model[which.min(selected$table$BIC)]
  alt<-NULL
  if(bic!=selected$selected){
    af<-pool_fit(sam$data,sam$V,strsplit(bic,'_',fixed=TRUE)[[1]])
    aa<-capture_fit(fit_sem(pool_inputs(af$object,x$pairs,x$model$variables),x$model,x$checks$n_total,name='BIC_alternative'))
    diagnostics<-c(diagnostics,paste0('AIC/BIC select different structures; BIC chooses ',bic,'.'))
    if(!is.null(aa$object)){alt<-aa$object$paths;cwrite(alt,file.path(out,'bic_alternative_paths.csv'))}
    else diagnostics<-c(diagnostics,paste0('BIC alternative Stage 2 failed: ',aa$error))
  }
  mod<-NULL
  if('group'%in%names(x$data)){
    cat('Independent multigroup WLS and direct contrasts\n')
    mod<-moderation(x,selected);diagnostics<-c(diagnostics,mod$diagnostics)
    cwrite(mod$group_paths,file.path(out,'group_paths.csv'));cwrite(mod$path_tests,file.path(out,'moderator_path_tests.csv'));cwrite(mod$pairwise,file.path(out,'moderator_pairwise.csv'))
    for(g in names(mod$group_pool)){
      cwrite(cbind(variable=rownames(mod$group_pool[[g]]$R),as.data.frame(mod$group_pool[[g]]$R)),file.path(out,paste0(g,'_correlations.csv')))
      cwrite(cbind(pair=rownames(mod$group_pool[[g]]$acov),as.data.frame(mod$group_pool[[g]]$acov)),file.path(out,paste0(g,'_acov.csv')))
    }
    if(any(mod$group_paths$ci_status!='ok')||any(mod$path_tests$status!='ok')||any(mod$pairwise$status!='ok')||any(mod$pairwise$ci_status!='ok'))diagnostics<-c(diagnostics,'Some moderator fits/intervals failed; inspect group_paths and moderator tables.')
    jwrite(list(groups=mod$groups,omnibus=mod$omnibus,role=x$cfg$moderation$mode %||% 'none'),file.path(out,'moderator_omnibus.json'))
    msrows<-list()
    for(setting in x$cfg$sensitivity$settings %||% list(c(0,0),c(.5,.5),c(1,1))){
      setting<-asvec(setting)
      mm<-if(all(setting==0))list(object=mod,error=NULL) else capture_fit(moderation(x,selected,setting[1],setting[2],intervals=FALSE,followups=FALSE))
      if(is.null(mm$object)){
        diagnostics<-c(diagnostics,paste0('Moderator sensitivity failed: ',mm$error))
        msrows[[length(msrows)+1]]<-data.frame(rho=setting[1],phi=setting[2],delta_chi_square=NA,df=NA,p_raw=NA,status='failed',message=mm$error)
      }else{
        for(g in names(mod$groups))if(!identical(mod$groups[[g]]$V_sha256,mm$object$groups[[g]]$V_sha256))fail('Subgroup sampling V changed in sensitivity.')
        msrows[[length(msrows)+1]]<-data.frame(rho=setting[1],phi=setting[2],as.data.frame(mm$object$omnibus),message='')
      }
    }
    cwrite(do.call(rbind,msrows),file.path(out,'moderator_sensitivity.csv'))
  }
  oracle<-independent_oracle(inp$R,inp$acov,x$model,sem$paths)
  if(oracle$status=='fail')fail('Independent algebra/delta-method oracle disagrees with primary SEM.')
  jwrite(oracle,file.path(out,'independent_oracle.json'))
  objects<-list(input=x,selected=selected,pooled=inp,primary=sem,moderator=mod,sensitivity=sens)
  profile_audit<-profile_records(objects)
  cwrite(profile_audit,file.path(out,'profile_audit.csv'))
    versions<-setNames(lapply(c('metafor','metaSEM','OpenMx','readxl','renv'),function(p)utils::packageDescription(p)$Version),c('metafor','metaSEM','OpenMx','readxl','renv'))
  result<-list(schema_version=1,data_role=x$cfg$data_role %||% 'user_supplied',status=if(length(diagnostics))'complete_with_diagnostics' else 'complete',
    n_studies=x$checks$n_studies,n_samples=x$checks$n_samples,n_total=x$checks$n_total,stage1_model=selected$selected,
    stage2=list(status=sem$status,fit=sem$stats,optimizer_status=sem$fit@output$status$code,
       intervals_complete=all(sem$paths$ci_status=='ok')),moderation=if(is.null(mod))NULL else mod$omnibus,
    failed_interval_count=sum(sem$paths$ci_status!='ok')+sum(sens$grid$ci_status!='ok')+
        if(is.null(mod))0L else sum(mod$group_paths$ci_status!='ok')+sum(mod$pairwise$ci_status!='ok'),
    recovered_profile_interval_count=nrow(profile_audit)/2,
    diagnostics=unique(diagnostics),runtime=list(r_version=as.character(getRversion()),packages=versions),
    sampling_covariance_sha256=digest::digest(sam$V,algo='sha256'))
  jwrite(result,file.path(out,'results.json'));saveRDS(objects,file.path(out,'fit_objects.rds'))
  writeLines(capture.output(sessionInfo()),file.path(out,'sessionInfo.txt'))
  write_report(x,selected,sem,mod,sens,unique(diagnostics),out);plots(inp,sem,out)
  invisible(result)
}

verify_numerical <- function(out) {
  obj<-readRDS(file.path(out,'fit_objects.rds'));check_mx(obj$primary$fit)
  if(!pd(obj$pooled$R)||!pd(obj$pooled$acov))fail('Invalid saved matrices.')
  if(sum(obj$input$registry$n)!=obj$input$checks$n_total)fail('N registry mismatch.')
  if(length(unique(obj$sensitivity$grid$V_sha256))!=1L)fail('Sampling covariance changed across sensitivity settings.')
  pt<-read.csv(file.path(out,'paths.csv'),check.names=FALSE)
  if(max(abs(pt$estimate-obj$primary$paths$estimate))>1e-10)fail('Path table disagrees with saved model.')
  if(any(pt$ci_status=='ok'&(!is.finite(pt$ci_lower)|!is.finite(pt$ci_upper)|pt$ci_lower>pt$estimate|pt$ci_upper<pt$estimate)))fail('Invalid successful confidence interval.')
  if(obj$primary$stats$saturated && !is.null(obj$primary$stats$p))fail('Saturated fit incorrectly given a model-fit p value.')
  or<-independent_oracle(obj$pooled$R,obj$pooled$acov,obj$input$model,obj$primary$paths)
  if(or$status=='fail')fail('Independent numerical oracle failed.')
  id<-identification(obj$input$model,obj$primary$fit)
  if(!is.null(obj$moderator)){
    tabs<-list(obj$moderator$group_paths,obj$moderator$pairwise)
    for(tab in tabs)if(nrow(tab)){
      center<-if('difference'%in%names(tab))tab$difference else tab$estimate
      if(any(tab$ci_status=='ok'&(!is.finite(tab$ci_lower)|!is.finite(tab$ci_upper)|tab$ci_lower>center|tab$ci_upper<center)))fail('Invalid successful subgroup/contrast interval.')
    }
  }
  audit<-profile_records(obj)
  if(file.exists(file.path(out,'profile_audit.csv'))){
    saved<-read.csv(file.path(out,'profile_audit.csv'))
    if(nrow(saved)!=nrow(audit)||!identical(as.character(saved$interval),as.character(audit$interval)))fail('Profile audit disagrees with saved endpoint fits.')
    if(nrow(saved)&&max(abs(saved$bound-audit$bound))>1e-8)fail('Saved profile bounds disagree.')
  }
  invisible(TRUE)
}
