# Rscript --vanilla options_validation.R <skill> <runtime> <report.json>
args<-commandArgs(TRUE);root<-normalizePath(args[1]);.libPaths(c(file.path(args[2],'library'),.Library))
source(file.path(root,'scripts/data.R'))
cfg<-jread(file.path(root,'assets/example/config.json'));model<-jread(file.path(root,'assets/example/model.json'))
spec<-read_model(model,asvec(cfg$variables));results<-list()
test<-function(name,expr){
  results[[name]]<<-tryCatch({force(expr);list(status='pass')},error=function(e)list(status='fail',message=conditionMessage(e)))
}
reject<-function(c,pattern,groups=TRUE){
  message<-tryCatch({validate_analysis_options(c,spec,groups);''},error=function(e)conditionMessage(e))
  if(!nzchar(message)||!grepl(pattern,message))stop('Expected rejection: ',pattern,'; got ',message)
}
test('valid_options_and_defaults',{
  validate_analysis_options(cfg,spec,TRUE)
  validate_analysis_options(list(),spec,FALSE)
})
test('malformed_sensitivity_settings_rejected',{
  for(settings in list(list(),list(c(-.1,0)),list(c(0,1.1)),list(0),list(c('zero','one')))){
    c<-cfg;c$sensitivity$settings<-settings;reject(c,'sensitivity.settings')
  }
  c<-cfg;c$sensitivity$leave_one_study_out<-'false';reject(c,'must be true or false')
})
test('unknown_and_duplicate_path_requests_rejected',{
  c<-cfg;c$moderation$path_tests<-list('typo');reject(c,'path labels')
  c<-cfg;c$moderation$pairwise_paths<-list('b_x1','b_x1');reject(c,'path labels')
})
test('undeclared_or_inapplicable_followups_rejected',{
  c<-cfg;c$moderation$mode<-'none';reject(c,'explicit planned')
  c<-cfg;c$moderation$mode<-'registered';reject(c,'moderation.mode')
  reject(cfg,'require a categorical moderator',FALSE)
})
test('public_input_validation_uses_options_check',{
  p<-tempfile('masem-options-');dir.create(p)
  file.copy(list.files(file.path(root,'assets/example'),full.names=TRUE),p)
  c<-cfg;c$moderation$path_tests<-list('typo');jwrite(c,file.path(p,'config.json'))
  message<-tryCatch({read_inputs(p);''},error=function(e)conditionMessage(e))
  stopifnot(grepl('path labels',message),!dir.exists(file.path(p,'runs')))
  unlink(p,recursive=TRUE)
})
ok<-all(vapply(results,function(x)x$status=='pass',TRUE))
jwrite(list(status=if(ok)'pass' else 'fail',tests=results),args[3])
cat(if(ok)'pass\n' else 'fail\n');quit(status=if(ok)0L else 1L)
