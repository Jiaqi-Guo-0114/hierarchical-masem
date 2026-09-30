# Execute author code in an isolated environment; the original file is untouched.
# Only strip installation lines and correct its single undefined data_DFSr alias.
args<-commandArgs(TRUE);root<-normalizePath(args[1]);runtime<-args[2];out<-normalizePath(args[3])
fixture<-if(length(args)>=4L)normalizePath(args[4]) else file.path(root,'assets/tutorial')
.libPaths(c(file.path(runtime,'library'),.Library))
suppressPackageStartupMessages(library(OpenMx));mxOption(NULL,'Number of Threads',1);set.seed(20260930)
source<-jsonlite::fromJSON(file.path(root,'assets/tutorial/source.json'))
for(i in seq_len(nrow(source$files)))if(digest::digest(file=file.path(fixture,source$files$file[i]),algo='sha256')!=source$files$sha256[i])stop('Author source checksum mismatch.')
txt<-readLines(file.path(fixture,'code-original.R'),warn=FALSE)
txt<-txt[!grepl('install.packages',txt,fixed=TRUE)]
txt<-gsub('data_DFSr','data_DFS',txt,fixed=TRUE)
writeLines(txt,file.path(out,'author-code-test-adapter.R'))
file.copy(file.path(fixture,'Flow_and_BigFive.xlsx'),out,overwrite=TRUE)
setwd(out);source('author-code-test-adapter.R',echo=FALSE)
res<-list(AIC=c(AIC(model1),AIC(model2),AIC(model3),AIC(model4)),
   R=cordat,acov=Acov,paths=unname(omxGetParameters(stage2$mx.fit)[c('b16','b26','b36','b46','b56')]),
   optimizer_status=stage2$mx.fit@output$status$code,
   original_multigroup_free_status=fit_free3@output$status$code,
   original_n=sum(unique(data$N)),
   omnibus=mxCompare(fit_free3,fit_constrained3)[2,c('diffLL','diffdf','p')],
   per_path=per_path_tests,pairwise=pair_df,sensitivity=sens_tab)
saveRDS(res,'author-results.rds');jsonlite::write_json(res,'author-results.json',pretty=TRUE,digits=16)
