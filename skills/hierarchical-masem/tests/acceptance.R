# Rscript --vanilla acceptance.R <skill> <runtime> <verified-tutorial-run> <report.json> [author-XLSX]
args<-commandArgs(TRUE);root<-normalizePath(args[1]);runtime<-args[2];run<-args[3]
.libPaths(c(file.path(runtime,'library'),.Library))
suppressPackageStartupMessages(library(OpenMx));mxOption(NULL,'Number of Threads',1)
for(f in c('data.R','stage1.R','stage2.R','analysis.R'))source(file.path(root,'scripts',f))
set.seed(20260930);results<-list()
test<-function(name,expr){
  z<-tryCatch({force(expr);list(status='pass')},error=function(e)list(status='fail',message=conditionMessage(e)))
  results[[name]]<<-z;cat(name,':',z$status,'\n');flush.console()
}
reject<-function(expr,pattern){
  msg<-tryCatch({force(expr);''},error=function(e)conditionMessage(e))
  if(!nzchar(msg)||!grepl(pattern,msg,ignore.case=TRUE))stop('Expected rejection matching ',pattern,'; got ',msg)
}
close<-function(x,y,tol=1e-8)stopifnot(length(x)==length(y),all(is.finite(x)),max(abs(x-y))<tol)
cfg<-jread(file.path(root,'assets/tutorial/config.json'))
model<-jread(file.path(root,'assets/tutorial/model.json'))
author_file<-if(length(args)>=5L)args[5] else file.path(root,'assets/tutorial/Flow_and_BigFive.xlsx')
raw<-as.data.frame(readxl::read_xlsx(author_file,col_types='text'))
variant<-function(d=raw,c=cfg,m=model){
  p<-tempfile('masem-test-');dir.create(p);c$data_file<-'correlations.csv'
  cwrite(d,file.path(p,'correlations.csv'));jwrite(c,file.path(p,'config.json'));jwrite(m,file.path(p,'model.json'));p
}
base<-read_inputs(variant());sam<-base$sampling(base$data)
ob<-readRDS(file.path(run,'fit_objects.rds'))
test('author_counts_and_same_n_independent_samples',{
  stopifnot(base$checks$n_total==2377,base$checks$legacy_unique_n==2208,base$checks$n_samples==9,base$checks$n_studies==8)
  stopifnot(sum(base$registry$n==169)==2)
})
test('tutorial_published_AIC_and_paths',{
  close(ob$selected$table$AIC,c(-36.9135227,-58.1955852,-62.8755422,-78.1945676),1e-4)
  close(ob$primary$paths$estimate,c(.0532172098,.2447182849,.1338940405,-.1212396193,.0670244543),1e-6)
  close(ob$moderator$omnibus$delta_chi_square,7.57881367,1e-4)
  stopifnot(ob$moderator$omnibus$df==10,ob$primary$stats$saturated,is.null(ob$primary$stats$p))
})
test('independent_algebra_and_uncertainty_propagation',{
  stopifnot(independent_oracle(ob$pooled$R,ob$pooled$acov,base$model,ob$primary$paths)$status=='pass')
  # Subgroup algebra/delta SEs remain testable even when profile bounds fail.
  for(g in names(ob$moderator$fits))stopifnot(independent_oracle(ob$moderator$group_pool[[g]]$R,ob$moderator$group_pool[[g]]$acov,base$model,ob$moderator$fits[[g]]$paths)$status=='pass')
})
invariance<-function(p){
  x<-read_inputs(p);ss<-x$sampling(x$data)
  key<-function(s)paste(s$data$sample_key,s$data$type)
  ix<-match(key(sam),key(ss));close(sam$V,ss$V[ix,ix]);close(sam$data$r,ss$data$r[ix])
  f<-pool_fit(ss$data,ss$V,ob$selected$structure);stopifnot(!is.null(f$object))
  pp<-pool_inputs(f$object,x$pairs,x$model$variables);close(pp$b,ob$pooled$b,1e-6);close(pp$acov,ob$pooled$acov,1e-7)
  ff<-fit_sem(pp,x$model,x$checks$n_total,intervals=FALSE);close(ff$paths$estimate,ob$primary$paths$estimate,1e-6)
}
test('row_permutation_invariance',invariance(variant(raw[sample(nrow(raw)),])))
test('variable_renaming_invariance',{
  nn<-c('z agree','trait_C','e/trait','Neuro','Open','flow outcome');ren<-setNames(nn,asvec(cfg$variables))
  d<-raw;d$Var1<-unname(ren[d$Var1]);d$Var2<-unname(ren[d$Var2])
  c<-cfg;c$variables<-as.list(nn);m<-model;m$variables<-as.list(nn);invariance(variant(d,c,m))
})
test('reversed_pair_orientation_invariance',{
  d<-raw;d$Var1<-raw$Var2;d$Var2<-raw$Var1;invariance(variant(d))
})
test('missing_pair_rejected',reject(read_inputs(variant(raw[-1,])),'Incomplete correlation'))
test('duplicate_reversed_pair_rejected',{
  d<-raw[1,];d$Var1<-raw$Var2[1];d$Var2<-raw$Var1[1]
  reject(read_inputs(variant(rbind(raw,d))),'Duplicate variable pair')
})
test('nonpositive_matrix_rejected',{
  d<-raw;k<-d$Sample.id==d$Sample.id[1];d$r[k]<-'0.95';d$r[which(k)[1]]<-'-0.95'
  reject(read_inputs(variant(d)),'Non-positive-definite')
})
test('invalid_r_and_n_rejected',{
  d<-raw;d$r[1]<-'1';reject(read_inputs(variant(d)),'Correlations must')
  d<-raw;d$N[1]<-'abc';reject(read_inputs(variant(d)),'Sample sizes must')
  d<-raw;d$N[1]<-NA;reject(read_inputs(variant(d)),'Missing values in n')
  d<-raw;d$N[1]<-'5';reject(read_inputs(variant(d)),'Unequal pairwise')
})
test('overlap_and_unconfirmed_independence_rejected',{
  d<-raw;d$overlap_group<-'shared';c<-cfg;c$columns$overlap_group<-'overlap_group'
  reject(read_inputs(variant(d,c)),'Overlapping participant')
  c<-cfg;c$sample_independence<-'unknown';reject(read_inputs(variant(raw,c)),'Confirm independent')
})
test('cross_group_study_rejected',{
  d<-raw;i<-which(duplicated(base$registry$study_id))[1];sid<-base$registry$study_id[i];samp<-base$registry$sample_id[i]
  d$Flow.Questionnaire[d$Study.id==sid&d$Sample.id==samp]<-'cross-group'
  reject(read_inputs(variant(d)),'Studies occur in more than one')
})
test('continuous_moderator_rejected',{
  c<-cfg;c$moderator$type<-'continuous';reject(read_inputs(variant(raw,c)),'Continuous moderators')
})
test('malformed_start_and_cycle_rejected',{
  m<-model;m$A[[6]][[1]]<-'..*bad';reject(read_inputs(variant(raw,cfg,m)),'Nonfinite or malformed')
  m<-model;m$A[[1]][[6]]<-'0.1*back';reject(read_inputs(variant(raw,cfg,m)),'Cyclic paths')
})
test('nonconverged_optimizer_rejected',{
  f<-ob$primary$fit;f@output$status$code<-6L;reject(check_mx(f),'optimization failed')
})
test('unsuccessful_profile_limits_not_accepted',{
  f<-ob$primary$fit;f@output$confidenceIntervalCodes[1,1]<-3L
  stopifnot(ci_table(f,rownames(f@output$confidenceIntervals)[1])$ci_status=='failed')
})
test('all_tutorial_intervals_and_independent_endpoint_objectives',{
  stopifnot(all(ob$primary$paths$ci_status=='ok'),all(ob$moderator$group_paths$ci_status=='ok'),
            all(ob$moderator$pairwise$ci_status=='ok'),all(ob$sensitivity$grid$ci_status=='ok'))
  audit<-profile_records(ob)
  stopifnot(nrow(audit)==14L,all(audit$status=='pass'),max(audit$cutoff_error)<1e-4,
            max(audit$unit_diagonal_error)<1e-5,all(audit$optimizer_status%in%c(0L,1L)))
  stopifnot(length(ob$moderator$fits$g2$profiles)==5L,length(ob$moderator$contrast_profiles)==2L)
})
test('fixed_parameter_profile_agrees_with_successful_native_interval',{
  native<-ob$primary$paths[2,]
  z<-path_profile(ob$primary$fit,native$parameter,native$se)
  close(c(z$lower,z$upper),c(native$ci_lower,native$ci_upper),2e-5)
})
test('fixed_contrast_profile_agrees_with_successful_native_interval',{
  native<-ob$moderator$pairwise[2,]
  z<-contrast_profile(ob$moderator$fits,ob$moderator$group_pool,base$model,'g1','g3','b_c')
  close(c(z$lower,z$upper),c(native$ci_lower,native$ci_upper),2e-5)
})
test('failed_refit_and_try_error_are_explicitly_rejected',{
  reject(check_mx(structure('optimizer failed',class='try-error')),'did not return')
  f<-ob$primary$fit;f@output$status$code<-6L
  reject(profile_limits(0,.1,0,function(value)list(fit=f)),'optimization failed')
})
test('independent_three_variable_overidentified_model',{
  # Analytic optimum for zero residual covariance chain, with diagonal aCov:
  # target r12=.3, r23=.4, r13=.12 exactly satisfies the two-path model.
  v<-c('x','middle','end')
  m<-list(variables=as.list(v),A=list(c(0,0,0),c('0.1*a',0,0),c(0,'0.1*b',0)),
          S=list(c(1,0,0),c(0,'0.8*v2',0),c(0,0,'0.8*v3')))
  spec<-read_model(m,v);R<-matrix(c(1,.3,.12,.3,1,.4,.12,.4,1),3);dimnames(R)<-list(v,v)
  inp<-list(R=R,acov=diag(.002,3),b=R[lower.tri(R)])
  f<-fit_sem(inp,spec,600);close(f$paths$estimate,c(.3,.4),1e-5)
  stopifnot(f$stats$df==1,f$stats$chi_square<1e-8,all(f$paths$ci_status=='ok'))
  # A genuine constrained case whose analytic chain restriction is violated.
  inp$R[1,3]<-inp$R[3,1]<-.25;inp$b<-inp$R[lower.tri(inp$R)]
  q<-fit_sem(inp,spec,600,intervals=FALSE)
  stopifnot(q$stats$df==1,q$stats$chi_square>0.1,q$stats$p>0,q$stats$p<1)
})
test('underidentified_model_rejected',{
  m<-model;m$S[[6]][[1]]<-m$S[[1]][[6]]<-'0*extra_cov'
  spec<-read_model(m,asvec(cfg$variables))
  reject(fit_sem(ob$pooled,spec,2377,intervals=FALSE),'underidentified|optimization failed')
})
test('Holm_families_and_fixed_sampling_covariance',{
  close(ob$moderator$path_tests$p_holm,p.adjust(ob$moderator$path_tests$p_raw,'holm'))
  close(ob$moderator$pairwise$p_holm,p.adjust(ob$moderator$pairwise$p_raw,'holm'))
  stopifnot(length(unique(ob$sensitivity$grid$V_sha256))==1,all(ob$sensitivity$grid$status=='ok'))
  ms<-read.csv(file.path(run,'moderator_sensitivity.csv'));stopifnot(nrow(ms)==3,all(ms$status=='ok'))
})
ok<-all(vapply(results,function(z)z$status=='pass',TRUE))
jwrite(list(status=if(ok)'pass' else 'fail',tests=results),args[4])
quit(status=if(ok)0L else 1L)
