# Public synthetic fixture: no author-owned dataset is needed.
# Rscript --vanilla example_acceptance.R <skill> <runtime> <run> <report.json>
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
  if(!nzchar(msg)||!grepl(pattern,msg,ignore.case=TRUE))stop('Expected rejection: ',pattern,'; got ',msg)
}
ob<-readRDS(file.path(run,'fit_objects.rds'));cfg<-jread(file.path(run,'inputs/config.json'))
model<-jread(file.path(run,'inputs/model.json'));raw<-read.csv(file.path(run,'inputs/correlations.csv'),colClasses='character')
variant<-function(d=raw,c=cfg,m=model){
  p<-tempfile('masem-example-test-');dir.create(p)
  cwrite(d,file.path(p,'correlations.csv'));jwrite(c,file.path(p,'config.json'));jwrite(m,file.path(p,'model.json'));p
}
x<-read_inputs(variant());sam<-x$sampling(x$data)
test('counts_same_n_and_independent_algebra',{
  stopifnot(x$checks$n_samples==10,x$checks$n_studies==8,x$checks$n_total==2083,sum(x$registry$n==169)==2)
  stopifnot(independent_oracle(ob$pooled$R,ob$pooled$acov,x$model,ob$primary$paths)$status=='pass')
  stopifnot(all(ob$primary$paths$ci_status=='ok'),all(ob$moderator$group_paths$ci_status=='ok'),all(ob$moderator$pairwise$ci_status=='ok'))
  verify_numerical(run)
})
test('permutation_and_variable_renaming',{
  d<-raw[sample(nrow(raw)),];ren<-setNames(c('renamed x','trait/two','outcome'),asvec(cfg$variables))
  d$var1<-unname(ren[d$var1]);d$var2<-unname(ren[d$var2]);c<-cfg;c$variables<-as.list(unname(ren))
  m<-model;m$variables<-c$variables;y<-read_inputs(variant(d,c,m));ss<-y$sampling(y$data)
  key<-function(z)paste(z$data$sample_key,z$data$type);ix<-match(key(sam),key(ss))
  stopifnot(max(abs(sam$V-ss$V[ix,ix]))<1e-12)
})
test('invalid_data_and_unsupported_scope_rejected',{
  reject(read_inputs(variant(raw[-1,])),'Incomplete correlation')
  reject(read_inputs(variant(rbind(raw,raw[1,]))),'Duplicate variable pair')
  d<-raw;d$r[1:3]<-c('.95','.95','-.95');reject(read_inputs(variant(d)),'Non-positive-definite')
  d<-raw;d$overlap_group<-'shared';reject(read_inputs(variant(d)),'Overlapping participant')
  c<-cfg;c$moderator$type<-'continuous';reject(read_inputs(variant(raw,c)),'Continuous moderators')
  d<-raw;d$group[1]<-'Beta';reject(read_inputs(variant(d)),'Studies occur in more than one')
})
test('profile_solvers_agree_with_native_intervals',{
  row<-ob$primary$paths[1,];p<-path_profile(ob$primary$fit,row$parameter,row$se)
  stopifnot(max(abs(c(p$lower,p$upper)-c(row$ci_lower,row$ci_upper)))<2e-5)
  row<-ob$moderator$pairwise[1,];p<-contrast_profile(ob$moderator$fits,ob$moderator$group_pool,x$model,'g1','g2',row$path)
  stopifnot(max(abs(c(p$lower,p$upper)-c(row$ci_lower,row$ci_upper)))<2e-5)
})
test('optimizer_failure_and_multiplicity_checks',{
  f<-ob$primary$fit;f@output$status$code<-6L;reject(check_mx(f),'optimization failed')
  reject(check_mx(structure('error',class='try-error')),'did not return')
  stopifnot(max(abs(ob$moderator$path_tests$p_holm-p.adjust(ob$moderator$path_tests$p_raw,'holm')))<1e-12)
  stopifnot(length(unique(ob$sensitivity$grid$V_sha256))==1)
})
ok<-all(vapply(results,function(z)z$status=='pass',TRUE))
jwrite(list(status=if(ok)'pass' else 'fail',data_role='synthetic_software_test',tests=results),args[4])
quit(status=if(ok)0L else 1L)
