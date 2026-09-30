args<-commandArgs(TRUE)
tryCatch({
  if(length(args)<3L)stop('Usage: main.R action runtime skill-root [paths]')
  action<-args[1];runtime<-args[2];root<-args[3]
  lib<-file.path(runtime,'library')
  if(!dir.exists(lib))stop('Runtime missing. Run masem.py setup first; analysis never installs packages.')
  .libPaths(c(lib,.Library))
  if(!requireNamespace('jsonlite',quietly=TRUE))stop('Incomplete runtime; run setup.')
  lock<-jsonlite::fromJSON(file.path(root,'assets/renv.lock'),simplifyVector=FALSE)
  if(as.character(getRversion())!=lock$R$Version)stop('R version differs from the tested lockfile.')
  for(p in names(lock$Packages)){
    installed<-tryCatch(utils::packageDescription(p,lib.loc=lib)$Version,error=function(e)'missing')
    if(installed!=lock$Packages[[p]]$Version)stop(paste('Runtime package mismatch:',p,installed,'expected',lock$Packages[[p]]$Version))
  }
  suppressPackageStartupMessages(library(OpenMx));OpenMx::mxOption(NULL,'Number of Threads',1)
  for(f in c('data.R','stage1.R','stage2.R','analysis.R'))source(file.path(root,'scripts',f),local=globalenv())
  if(action=='check')cat(jsonlite::toJSON(list(status='ready',R=as.character(getRversion()),runtime=runtime,locked_packages=length(lock$Packages)),auto_unbox=TRUE))
  else if(action=='validate'){x<-read_inputs(args[4]);cat(jsonlite::toJSON(x$checks,auto_unbox=TRUE))}
  else if(action=='run')analyze(args[4],args[5])
  else if(action=='verify'){verify_numerical(args[4]);cat('{"status":"pass"}')}
  else if(action=='benchmark'){
    out<-args[4];verify_numerical(out);ob<-readRDS(file.path(out,'fit_objects.rds'))
    if(ob$input$checks$n_total!=2377||ob$input$checks$n_samples!=9||ob$input$checks$n_studies!=8)fail('Tutorial identity/count benchmark failed.')
    or<-independent_oracle(ob$pooled$R,ob$pooled$acov,ob$input$model,ob$primary$paths)
    if(or$status!='pass')fail('Tutorial oracle failed.')
    if(max(abs(ob$selected$table$AIC-c(-36.9135227,-58.1955852,-62.8755422,-78.1945676)))>1e-4 ||
       max(abs(ob$primary$paths$estimate-c(.0532172098,.2447182849,.1338940405,-.1212396193,.0670244543)))>1e-6 ||
       abs(ob$moderator$omnibus$delta_chi_square-7.57881367)>1e-4)
      fail('Tutorial numerical benchmark differs from the verified author baseline.')
    cat(jsonlite::toJSON(list(status='pass',n=2377,legacy_n=2208,oracle=or),auto_unbox=TRUE))
  } else stop('Unknown action')
},error=function(e){cat(conditionMessage(e),'\n',file=stderr());quit(status=1)})
