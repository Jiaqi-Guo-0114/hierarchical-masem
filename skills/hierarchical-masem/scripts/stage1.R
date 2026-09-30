capture_fit <- function(expr) {
  warnings<-character()
  obj<-tryCatch(withCallingHandlers(expr,warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart('muffleWarning')}),error=function(e)e)
  list(object=if(inherits(obj,'error'))NULL else obj,error=if(inherits(obj,'error'))conditionMessage(obj) else NULL,warnings=unique(warnings))
}
pool_fit <- function(data,V,struct,rho=0,phi=0) {
  tries<-list(list(),list(optimizer='optim',optmethod='BFGS',maxiter=2000))
  history<-list()
  for(control in tries){
    f<-capture_fit(metafor::rma.mv(yi=r,V=V,data=data,mods=~type-1,
        random=list(~type|es_id,~type|study_cluster),struct=struct,
        rho=rho,phi=phi,method='REML',control=control))
    history[[length(history)+1L]]<-list(error=f$error,warnings=f$warnings)
    if(!is.null(f$object)&&all(is.finite(coef(f$object)))&&pd(vcov(f$object))){
      f$history<-history;return(f)
    }
  }
  list(object=NULL,error=paste(vapply(history,function(h)h$error %||% 'invalid fixed-effect covariance',''),collapse='; '),history=history)
}
pool_inputs <- function(f,pairs,vars) {
  b<-coef(f);names(b)<-sub('^type','',names(b))
  idx<-match(pairs$type,names(b))
  if(anyNA(idx))fail('Missing pooled correlation type.')
  R<-diag(length(vars));R[lower.tri(R)]<-b[idx];R[upper.tri(R)]<-t(R)[upper.tri(R)]
  dimnames(R)<-list(vars,vars)
  ac<-vcov(f)[idx,idx,drop=FALSE];dimnames(ac)<-list(pairs$type,pairs$type)
  if(!pd(R))fail('Pooled correlation matrix is not positive definite; no automatic repair.')
  if(!pd(ac))fail('Pooled asymptotic covariance is not positive definite.')
  list(R=R,acov=ac,b=b[idx])
}
select_pool <- function(d,V,pairs,vars) {
  structures<-list(HCS_HCS=c('HCS','HCS'),HCS_CS=c('HCS','CS'),CS_HCS=c('CS','HCS'),CS_CS=c('CS','CS'))
  fits<-lapply(structures,function(s)pool_fit(d,V,s))
  for(k in seq_along(fits))if(!is.null(fits[[k]]$object)){
    chk<-capture_fit(pool_inputs(fits[[k]]$object,pairs,vars))
    if(is.null(chk$object)){
      fits[[k]]$object<-NULL;fits[[k]]$error<-paste('Inadmissible pooled input:',chk$error)
    }
  }
  tab<-do.call(rbind,lapply(names(fits),function(nm){
    f<-fits[[nm]]$object
    data.frame(model=nm,status=if(is.null(f))'failed' else 'ok',
      AIC=if(is.null(f))NA_real_ else AIC(f),BIC=if(is.null(f))NA_real_ else BIC(f),
      parameters=if(is.null(f))NA_real_ else attr(logLik(f),'df'),
      logLik=if(is.null(f))NA_real_ else as.numeric(logLik(f)),
      message=fits[[nm]]$error %||% '',stringsAsFactors=FALSE)
  }))
  eligible<-which(tab$status=='ok' & is.finite(tab$AIC))
  if(!length(eligible))fail('All Stage 1 candidate models failed: ',paste(tab$message,collapse=' | '))
  winner<-eligible[order(tab$AIC[eligible],tab$parameters[eligible],tab$model[eligible])][1]
  nm<-tab$model[winner];tab$selected<-seq_len(nrow(tab))==winner
  lrts<-do.call(rbind,lapply(list(c('HCS_HCS','HCS_CS'),c('HCS_HCS','CS_HCS'),c('HCS_CS','CS_CS'),c('CS_HCS','CS_CS')),function(z){
    ff<-fits[[z[1]]]$object;rr<-fits[[z[2]]]$object
    if(is.null(ff)||is.null(rr))return(data.frame(full=z[1],reduced=z[2],delta=NA,df=NA,p=NA,status='fit_failed'))
    cc<-capture_fit(anova(ff,rr))
    if(is.null(cc$object))return(data.frame(full=z[1],reduced=z[2],delta=NA,df=NA,p=NA,status='comparison_failed'))
    o<-cc$object
    data.frame(full=z[1],reduced=z[2],delta=o$LRT,df=o$parms.f-o$parms.r,p=o$pval,status='asymptotic_working_model_test')
  }))
  list(fit=fits[[nm]]$object,selected=nm,structure=structures[[nm]],table=tab,lrts=lrts,attempts=lapply(fits,`[`,c('error','warnings','history')))
}
