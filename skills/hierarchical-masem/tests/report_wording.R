# Fast report consistency checks; base R only, no statistical fitting required.
args <- commandArgs(TRUE)
if(length(args)!=1L)stop('Usage: Rscript report_wording.R <skill-directory>')
source(file.path(args[1],'scripts','analysis.R'))
`%||%` <- function(a,b) if(is.null(a)) b else a
# The technical-note sidecar is outside these prose checks.
jwrite <- function(x,p) writeLines('Technical-note serialization stub for report wording checks.',p)
checks <- 0L
check <- function(ok,label){
  if(!isTRUE(ok))stop(label,call.=FALSE)
  checks <<- checks+1L
}
contains <- function(text,needle)grepl(needle,text,fixed=TRUE)
base_x <- list(cfg=list(data_role='research_data',moderation=list(mode='none')),
  checks=list(n_studies=3L,n_samples=4L,n_correlations=12L,n_total=500L))
base_sem <- list(paths=data.frame(predictor=c('X1','X2'),outcome=c('Y','Y'),
    estimate=c(.2,.3),ci_lower=c(.1,.2),ci_upper=c(.3,.4),ci_status=c('ok','ok')),
  stats=list(saturated=TRUE))
base_sens <- list(grid=data.frame(ci_status=c('ok','ok')),loo=data.frame())
render <- function(x=base_x,sem=base_sem,sens=base_sens,mod=NULL){
  out<-tempfile('masem-report-');dir.create(out)
  on.exit(unlink(out,recursive=TRUE))
  write_report(x,list(selected='CS_CS'),sem,mod,sens,character(),out)
  list(report=paste(readLines(file.path(out,'report.md'),warn=FALSE),collapse='\n'),
       methods=paste(readLines(file.path(out,'methods-building-blocks.md'),warn=FALSE),collapse='\n'))
}
r<-render()
check(contains(r$report,'本次未执行逐研究删除诊断。') &&
      contains(r$methods,'Leave-one-study-out diagnostics were not performed') &&
      !contains(r$methods,'diagnostics retained the selected heterogeneity structure'),
      'Disabled LOO is inaccurately described as performed.')
check(!contains(r$report,'合成数据演示') && !contains(r$methods,'SYNTHETIC DEMONSTRATION'),
      'Research input was incorrectly labeled synthetic.')
for(role in c('synthetic_software_example','synthetic_software_tests','synthetic_test')){
  x<-base_x;x$cfg$data_role<-role;r<-render(x=x)
  check(contains(r$report,'**合成数据演示：') && contains(r$methods,'**SYNTHETIC DEMONSTRATION:') &&
        contains(r$methods,'not psychological research evidence'),paste('Synthetic label missing for',role))
}
sens<-base_sens
# Each deletion produces one row per path: count deletion attempts, not rows.
sens$loo<-data.frame(omitted_study=c('S1','S1','S2','S2'),status=rep('ok',4))
r<-render(sens=sens)
check(contains(r$report,'2 项重拟合成功，0 项失败') &&
      contains(r$methods,'2 study-deletion refits succeeded and 0 failed'),
      'Successful LOO refits were counted by path rows instead of omitted studies.')
sens$loo<-data.frame(omitted_study=c('S1','S1','S2'),status=c('ok','ok','failed'))
r<-render(sens=sens)
check(contains(r$report,'1 项重拟合成功，1 项失败') &&
      contains(r$methods,'1 study-deletion refits succeeded and 1 failed'),
      'Partial LOO failure is not faithfully described.')
sens$loo<-data.frame(omitted_study=c('S1','S2'),status=c('failed','failed'))
r<-render(sens=sens)
check(contains(r$report,'0 项重拟合成功，2 项失败') &&
      contains(r$methods,'0 study-deletion refits succeeded and 2 failed'),
      'All failed LOO refits were described as successful.')
sem<-base_sem;sem$paths$ci_status[1]<-'failed';sem$paths$ci_lower[1]<-NA_real_
sens<-base_sens;sens$grid$ci_status[1]<-'failed'
r<-render(sem=sem,sens=sens)
check(contains(r$report,'2 个请求的区间未得到有效解') &&
      contains(r$methods,'2 requested intervals could not be estimated successfully') &&
      !contains(r$methods,'intervals were obtained'),
      'Failed intervals were described as successfully obtained.')
mod<-list(omnibus=list(df=2L,delta_chi_square=1,p_raw=.61),path_tests=data.frame(),
          pairwise=data.frame(),group_paths=data.frame(ci_status=c('ok','ok')))
r<-render(mod=mod)
check(!contains(r$report,'Holm') && !contains(r$methods,'Holm') &&
      contains(r$methods,'Equality constraints were compared'),
      'An omnibus-only run claimed unrequested Holm-adjusted follow-ups.')
sens<-base_sens;sens$grid<-data.frame();r<-render(sens=sens)
check(contains(r$report,'本次未执行工作相关设定的敏感性分析。') &&
      contains(r$methods,'Working-correlation sensitivity analyses were not performed'),
      'No sensitivity refits were inaccurately reported as performed.')
cat(sprintf('PASS: %d report wording checks.\n',checks))
