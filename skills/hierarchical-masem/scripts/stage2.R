ram_matrices <- function(spec,suffix='',R=NULL) {
  rename<-function(m){z<-m;if(nzchar(suffix))z[grepl('*',z,fixed=TRUE)]<-paste0(z[grepl('*',z,fixed=TRUE)],suffix);z}
  A<-metaSEM::as.mxMatrix(rename(spec$A),name='Amatrix')
  S<-metaSEM::as.mxMatrix(rename(spec$S),name='Smatrix')
  if(!is.null(R)){
    # Regression/residual starting values improve constrained WLS conditioning.
    for(i in seq_len(nrow(R))){
      parent<-which(A@free[i,]|A@values[i,]!=0)
      if(length(parent)){
        beta<-solve(R[parent,parent,drop=FALSE],R[parent,i])
        fr<-which(A@free[i,parent]);if(length(fr))A@values[i,parent[fr]]<-beta[fr]
      }
    }
    residual<-(diag(nrow(R))-A@values)%*%R%*%t(diag(nrow(R))-A@values)
    for(lab in unique(S@labels[S@free]))S@values[which(S@labels==lab)]<-mean(residual[which(S@labels==lab)])
  }
  # Nonnegative residual variances are substantive admissibility constraints.
  idx<-which(diag(S@free));S@lbound[cbind(idx,idx)]<-0
  list(A=A,S=S)
}
check_mx <- function(fit) {
  if(!inherits(fit,'MxModel'))fail('OpenMx did not return a fitted MxModel.')
  code<-fit@output$status$code
  if(is.null(code)||!code %in% c(0L,1L))fail('OpenMx optimization failed (status ',code %||% 'missing',').')
  if(!is.finite(fit@output$fit))fail('Nonfinite WLS objective.')
  if(any(!is.finite(OpenMx::omxGetParameters(fit))))fail('Nonfinite structural parameter.')
  TRUE
}
run_mx <- function(model,intervals=FALSE) {
  model<-OpenMx::mxOption(model,'Feasibility tolerance',1e-8)
  model<-OpenMx::mxOption(model,'Optimality tolerance',1e-10)
  first<-capture_fit(OpenMx::mxRun(model,silent=TRUE,intervals=intervals))
  if(inherits(first$object,'MxModel')&&first$object@output$status$code %in% c(0L,1L))return(first$object)
  # Bounded, seeded retry; never silently accept a nonconverged fit.
  second<-capture_fit(OpenMx::mxTryHard(model,extraTries=2,intervals=intervals,silent=TRUE,
                                       greenOK=TRUE,checkHess=FALSE))
  if(!inherits(second$object,'MxModel'))fail('OpenMx failed to return a fitted model: ',second$error %||% first$error %||% 'bounded retries exhausted')
  check_mx(second$object);second$object
}

# A likelihood-based WLS endpoint is a restricted optimum whose objective
# increase equals chi-square(.95, 1). Failed native searches are never replaced
# with Wald intervals. These bounded refits preserve R, aCov and unit variances.
profile_admissibility <- function(fit) {
  check_mx(fit)
  implied<-OpenMx::mxEvalByName('impliedS',fit)
  ss<-OpenMx::mxEvalByName('Smatrix',fit)
  err<-max(abs(diag(implied)-1))
  if(err>1e-5||!pd(implied)||any(diag(ss)< -1e-8))fail('Profile refit violates unit variance or matrix admissibility.')
  list(unit_diagonal_error=err,minimum_implied_eigenvalue=min(eigen(implied,symmetric=TRUE,only.values=TRUE)$values),
       minimum_residual_variance=min(diag(ss)),optimizer_status=fit@output$status$code)
}

profile_limits <- function(center,se,objective,evaluate) {
  cutoff<-qchisq(.95,1);cache<-new.env(parent=emptyenv());count<-0L
  refit<-function(value){
    key<-sprintf('%.17g',value)
    if(exists(key,cache,inherits=FALSE))return(get(key,cache,inherits=FALSE))
    count<<-count+1L;if(count>100L)fail('Profile refit limit exceeded.')
    z<-evaluate(value);check_mx(z$fit)
    delta<-z$fit@output$fit-objective
    if(delta< -1e-6)fail('Profile refit improves on the free optimum.')
    z$delta<-max(0,delta);assign(key,z,cache);z
  }
  at<-refit(center)
  if(at$delta>1e-5)fail('Profile parameterization disagrees with the free optimum.')
  endpoints<-list();bounds<-numeric()
  for(direction in c(-1,1)){
    width<-if(is.finite(se)&&se>0)2*se else .1
    bracketed<-FALSE
    for(step in seq_len(8)){
      edge<-center+direction*width
      z<-refit(edge)
      if(z$delta>=cutoff){bracketed<-TRUE;break}
      width<-width*1.5
    }
    if(!bracketed)fail('Could not bracket a finite likelihood-based profile limit.')
    f<-function(v)refit(v)$delta-cutoff
    boundary<-uniroot(f,sort(c(center,edge)),tol=1e-7,maxiter=50)$root
    end<-refit(boundary)
    if(abs(end$delta-cutoff)>1e-4)fail('Profile endpoint does not attain the objective cutoff.')
    end$value<-boundary;end$cutoff_error<-abs(end$delta-cutoff)
    endpoints[[if(direction<0)'lower' else 'upper']]<-end;bounds<-c(bounds,boundary)
  }
  list(lower=bounds[1],upper=bounds[2],cutoff=cutoff,evaluations=count,endpoints=endpoints)
}

path_profile <- function(fit,label,se) {
  base<-fit;base@intervals<-list();center<-unname(OpenMx::omxGetParameters(base)[label])
  profile_limits(center,se,base@output$fit,function(value){
    f<-run_mx(OpenMx::omxSetParameters(base,labels=label,free=FALSE,values=value))
    audit<-profile_admissibility(f)
    if(abs(OpenMx::omxGetParameters(f,free=FALSE)[label]-value)>1e-8)fail('Fixed profile parameter changed.')
    list(fit=f,admissibility=list(audit))
  })
}

equivalent_unit_model <- function(inp,spec,old,name,suffix) {
  ram<-ram_matrices(spec,suffix,inp$R)
  # metaSEM computes free residual variances algebraically in this equivalent
  # representation. Unit diagonals and nonnegative residuals are still checked.
  m<-metaSEM::wls(Cov=inp$R,aCov=inp$acov,n=old$n,Amatrix=ram$A,Smatrix=ram$S,
     cor.analysis=TRUE,diag.constraints=FALSE,intervals.type='LB',run=FALSE,model.name=name)
  m@intervals<-list();f<-run_mx(m);profile_admissibility(f)
  labels<-paste0(spec$paths$path,suffix)
  if(max(abs(OpenMx::omxGetParameters(f)[labels]-old$paths$estimate))>1e-5||
     abs(f@output$fit-old$fit@output$fit)>1e-5||
     max(abs(OpenMx::mxEvalByName('impliedS',f)-old$identification$implied))>1e-5)
    fail('Algebraic unit-variance model is not equivalent to the original WLS optimum.')
  f
}

contrast_profile <- function(fits,pool,spec,g1,g2,path) {
  groups<-c(g1,g2);models<-lapply(groups,function(g)equivalent_unit_model(pool[[g]],spec,fits[[g]],g,paste0('_',g)))
  names(models)<-groups
  base<-run_mx(OpenMx::mxModel('contrast_profile',models,OpenMx::mxFitFunctionMultigroup(groups)))
  pos<-spec$paths[spec$paths$path==path,,drop=FALSE]
  expr<-sprintf('%s.Amatrix[%d,%d] - %s.Amatrix[%d,%d]',g1,pos$i,pos$j,g2,pos$i,pos$j)
  base<-OpenMx::mxModel(base,OpenMx::mxAlgebraFromString(expr,name='profile_difference'))
  ix<-match(path,spec$paths$path)
  center<-fits[[g1]]$paths$estimate[ix]-fits[[g2]]$paths$estimate[ix]
  se<-sqrt(fits[[g1]]$paths$se[ix]^2+fits[[g2]]$paths$se[ix]^2)
  original<-sum(vapply(fits[groups],function(z)z$fit@output$fit,0.0))
  if(abs(base@output$fit-original)>1e-5)fail('Pairwise profile free objective is not equivalent.')
  profile_limits(center,se,original,function(value){
    initial<-base
    for(g in groups)initial<-OpenMx::omxSetParameters(initial,labels=paste0(path,'_',g),
      values=fits[[g]]$paths$estimate[ix]+if(g==g1)(value-center)/2 else -(value-center)/2)
    m<-OpenMx::mxModel(initial,OpenMx::mxMatrix('Full',1,1,free=FALSE,values=value,name='profile_target'),
       OpenMx::mxConstraint(profile_difference==profile_target,name='profile_restriction'))
    f<-run_mx(m)
    restriction_error<-abs(as.numeric(OpenMx::mxEvalByName('profile_difference',f))-value)
    if(restriction_error>1e-5)fail('Pairwise profile restriction violated.')
    audit<-lapply(groups,function(g)profile_admissibility(f[[g]]));names(audit)<-groups
    list(fit=f,admissibility=audit,restriction_error=restriction_error)
  })
}

identification <- function(spec,fit) {
  pars<-OpenMx::omxGetParameters(fit)
  A<-fit$Amatrix;S<-fit$Smatrix
  fun<-function(theta){
    aa<-A@values;ss<-S@values
    for(nm in names(theta)){
      aa[which(A@labels==nm)]<-theta[nm];ss[which(S@labels==nm)]<-theta[nm]
    }
    B<-solve(diag(nrow(aa))-aa);implied<-B%*%ss%*%t(B)
    c(implied[lower.tri(implied)],diag(implied)[spec$free_diag])
  }
  J<-numDeriv::jacobian(fun,pars)
  rank<-qr(J,tol=1e-7)$rank
  if(rank<length(pars))fail('Structural model is locally underidentified (Jacobian rank ',rank,' < ',length(pars),').')
  rows<-length(spec$variables)*(length(spec$variables)-1)/2
  c_rank<-if(length(spec$free_diag))qr(J[seq.int(rows+1,nrow(J)),,drop=FALSE],tol=1e-7)$rank else 0L
  Avals<-A@values;Svals<-S@values;B<-solve(diag(nrow(Avals))-Avals)
  implied<-B%*%Svals%*%t(B)
  if(max(abs(diag(implied)-1))>1e-5)fail('Structural correlation diagonal constraints violated.')
  if(!pd(implied)||any(diag(Svals)< -1e-8))fail('Inadmissible implied matrix or residual variance.')
  list(rank=rank,free_parameters=length(pars),constraint_rank=c_rank,df=rows-length(pars)+c_rank,
       implied=implied,residual_variances=diag(Svals))
}

ci_table <- function(fit,labels) {
  vals<-OpenMx::omxGetParameters(fit)
  ci<-fit@output$confidenceIntervals;codes<-fit@output$confidenceIntervalCodes
  do.call(rbind,lapply(labels,function(nm){
    cirow<-if(!is.null(ci)&&nm %in% rownames(ci))ci[nm,] else c(NA,NA,NA)
    cd<-if(!is.null(codes)&&nm %in% rownames(codes))as.integer(codes[nm,]) else c(NA_integer_,NA_integer_)
    se<-tryCatch(as.numeric(OpenMx::mxSE(nm,fit,silent=TRUE)),error=function(e)NA_real_)
    lower<-cirow[1];upper<-cirow[length(cirow)]
    ok<-all(is.finite(c(lower,upper)))&&all(!is.na(cd)&cd==0L)&&lower<=vals[nm]&&upper>=vals[nm]
    data.frame(parameter=nm,estimate=unname(vals[nm]),se=se,ci_lower=unname(lower),ci_upper=unname(upper),
      ci_method='likelihood_based_WLS',ci_status=if(ok)'ok' else 'failed',
      ci_code_lower=cd[1],ci_code_upper=cd[length(cd)],ci_solver='OpenMx_native',
      native_ci_code_lower=cd[1],native_ci_code_upper=cd[length(cd)],ci_message='',stringsAsFactors=FALSE)
  }))
}

fit_sem <- function(inp,spec,n,name='overall',suffix='',intervals=TRUE) {
  ram<-ram_matrices(spec,suffix,inp$R)
  base<-metaSEM::wls(Cov=inp$R,aCov=inp$acov,n=n,Amatrix=ram$A,Smatrix=ram$S,
                    cor.analysis=TRUE,diag.constraints=TRUE,intervals.type='LB',run=FALSE,
                    model.name=name,suppressWarnings=FALSE)
  base@intervals<-list()
  labs<-paste0(spec$paths$path,suffix)
  if(intervals)base<-OpenMx::mxModel(base,OpenMx::mxCI(labs,interval=.95))
  fit<-run_mx(base,intervals=intervals);check_mx(fit)
  id<-identification(spec,fit)
  profiles<-list()
  if(intervals){
    pt<-ci_table(fit,labs)
    for(i in which(pt$ci_status!='ok')){
      q<-capture_fit(path_profile(fit,labs[i],pt$se[i]))
      if(!is.null(q$object)){
        profiles[[labs[i]]]<-q$object
        pt$ci_lower[i]<-q$object$lower;pt$ci_upper[i]<-q$object$upper
        pt$ci_status[i]<-'ok';pt$ci_code_lower[i]<-pt$ci_code_upper[i]<-0L
        pt$ci_solver[i]<-'fixed_parameter_profile'
      }else pt$ci_message[i]<-q$error %||% 'Profile refit failed.'
    }
  }else{
    pars<-OpenMx::omxGetParameters(fit)
    pt<-data.frame(parameter=labs,estimate=unname(pars[labs]),se=NA_real_,ci_lower=NA_real_,ci_upper=NA_real_,ci_method='not_requested',ci_status='not_requested')
  }
  pt<-cbind(spec$paths,pt);pt$group<-name
  chisq<-fit@output$fit;df<-id$df
  indep<-as.numeric(inp$b%*%solve(inp$acov,inp$b));idf<-length(inp$b)
  fitstats<-list(chi_square=chisq,df=df,p=if(df>0)pchisq(chisq,df,lower.tail=FALSE) else NULL,
    RMSEA=if(df>0)sqrt(max(0,(chisq-df)/((n-1)*df))) else NULL,
    CFI=if(df>0 && indep>idf)1-max(0,chisq-df)/max(chisq-df,indep-idf) else NULL,
    SRMR=sqrt(mean((inp$R[lower.tri(inp$R)]-id$implied[lower.tri(id$implied)])^2)),
    saturated=df==0L,fit_interpretation=if(df==0L)'Saturated: overall fit cannot support the theory.' else 'Working-model conditional WLS fit.')
  list(fit=fit,paths=pt,stats=fitstats,identification=id,status='ok',n=n,profiles=profiles)
}

compare_equal <- function(free,labels,newlabel,df) {
  con<-free;con@intervals<-list()
  for(k in seq_along(labels))con<-OpenMx::omxSetParameters(con,labels=labels[[k]],newlabels=newlabel[k])
  con<-OpenMx::omxAssignFirstParameters(con)
  fit<-run_mx(con);check_mx(fit)
  delta<-fit@output$fit-free@output$fit
  if(delta< -1e-6)fail('Constrained WLS model improves on the free optimum; comparison is invalid.')
  delta<-max(0,delta)
  list(delta_chi_square=delta,df=df,p_raw=pchisq(delta,df,lower.tail=FALSE),status='ok')
}

moderation <- function(x,selected,rho=0,phi=0,intervals=TRUE,followups=TRUE) {
  d<-x$data;groups<-sort(unique(d$group));G<-length(groups)
  fits<-list();pool<-list();info<-list();diags<-character()
  for(k in seq_along(groups)){
    label<-groups[k];g<-paste0('g',k);dd<-d[d$group==label,,drop=FALSE]
    sam<-x$sampling(dd);f<-pool_fit(sam$data,sam$V,selected$structure,rho,phi)
    if(is.null(f$object))fail('Stage 1 subgroup failed (',label,'): ',f$error)
    pp<-pool_inputs(f$object,x$pairs,x$model$variables)
    nn<-sum(x$registry$n[x$registry$sample_key %in% dd$sample_key])
    ff<-fit_sem(pp,x$model,nn,name=g,suffix=paste0('_',g),intervals=intervals)
    ff$paths$group<-label;fits[[g]]<-ff;pool[[g]]<-pp
    info[[g]]<-list(group=label,n_studies=length(unique(dd$study_id)),n_samples=length(unique(dd$sample_key)),n=nn,V_sha256=digest::digest(sam$V,algo='sha256'))
    if(length(unique(dd$sample_key))==length(unique(dd$study_id)))diags<-c(diags,paste0('Group ',label,': no studies contribute multiple samples; within/between heterogeneity components are not separately interpretable at rho=phi=0.'))
  }
  sub<-lapply(fits,`[[`,'fit');for(k in seq_along(sub))sub[[k]]@intervals<-list()
  free<-OpenMx::mxModel('multigroup',sub,OpenMx::mxFitFunctionMultigroup(names(fits)))
  free<-OpenMx::omxAssignFirstParameters(free);free<-run_mx(free);check_mx(free)
  paths<-x$model$paths$path
  labels<-function(p)paste0(p,'_',names(fits))
  omni<-compare_equal(free,lapply(paths,labels),paths,(G-1)*length(paths))
  mode<-x$cfg$moderation$mode %||% 'none'
  if(!mode %in% c('none','planned','exploratory'))fail('moderation.mode must be none, planned, or exploratory.')
  testpaths<-as.character(asvec(x$cfg$moderation$path_tests %||% list()))
  pairpaths<-as.character(asvec(x$cfg$moderation$pairwise_paths %||% list()))
  if(!followups){testpaths<-pairpaths<-character()}
  if(anyDuplicated(testpaths)||anyDuplicated(pairpaths)||!all(c(testpaths,pairpaths)%in%paths))fail('Invalid or duplicate moderation path labels.')
  if(mode=='none'&&length(c(testpaths,pairpaths)))fail('Follow-up tests need explicit planned or exploratory mode.')
  per<-data.frame();pair<-data.frame();contrast_profiles<-list()
  if(length(testpaths)){
    per<-do.call(rbind,lapply(testpaths,function(p){
      q<-capture_fit(compare_equal(free,list(labels(p)),p,G-1))
      z<-q$object %||% list(delta_chi_square=NA_real_,df=G-1,p_raw=NA_real_,status='failed')
      data.frame(path=p,as.data.frame(z),message=q$error %||% '',stringsAsFactors=FALSE)
    }))
    per$p_holm<-p.adjust(per$p_raw,'holm',n=length(testpaths));per$family<-'all_requested_path_tests';per$analysis_role<-mode
  }
  if(length(pairpaths)){
    pairs<-combn(seq_len(G),2,simplify=FALSE);n_tests<-length(pairpaths)*length(pairs)
    rows<-list()
    for(p in pairpaths)for(ij in pairs){
      g1<-names(fits)[ij[1]];g2<-names(fits)[ij[2]]
      q<-capture_fit(compare_equal(free,list(c(paste0(p,'_',g1),paste0(p,'_',g2))),paste0(p,'_equal'),1))
      z<-q$object %||% list(delta_chi_square=NA_real_,df=1,p_raw=NA_real_,status='failed')
      pos<-x$model$paths[x$model$paths$path==p,,drop=FALSE]
      expr<-sprintf('%s.Amatrix[%d,%d] - %s.Amatrix[%d,%d]',g1,pos$i,pos$j,g2,pos$i,pos$j)
      cm<-OpenMx::mxModel(free,OpenMx::mxAlgebraFromString(expr,name='path_difference'),OpenMx::mxCI('path_difference',interval=.95))
      cf<-capture_fit(run_mx(cm,intervals=TRUE))
      ix<-match(p,paths)
      val<-fits[[g1]]$paths$estimate[ix]-fits[[g2]]$paths$estimate[ix]
      lb<-ub<-NA_real_;cistatus<-'failed';solver<-'OpenMx_native';native_lower<-native_upper<-NA_integer_
      if(!is.null(cf$object)){
        val<-as.numeric(OpenMx::mxEvalByName('path_difference',cf$object))
        ci<-cf$object@output$confidenceIntervals;cd<-cf$object@output$confidenceIntervalCodes
        at<-grep('path_difference',rownames(ci))
        if(length(at)==1){
          lb<-ci[at,1];ub<-ci[at,3]
          if(!is.null(cd)){native_lower<-cd[at,1];native_upper<-cd[at,2]}
          if(!is.null(cd)&&all(is.finite(c(lb,ub)))&&all(!is.na(cd[at,])&cd[at,]==0)&&lb<=val&&ub>=val)cistatus<-'ok'
        }
      }
      fallback_error<-''
      if(cistatus!='ok'){
        cp<-capture_fit(contrast_profile(fits,pool,x$model,g1,g2,p))
        if(!is.null(cp$object)){
          contrast_profiles[[paste(p,g1,g2,sep='/')]]<-cp$object
          lb<-cp$object$lower;ub<-cp$object$upper;cistatus<-'ok';solver<-'fixed_contrast_profile_equivalent_unit_diagonal'
        }else fallback_error<-cp$error %||% 'Contrast profile failed.'
      }
      rows[[length(rows)+1]]<-data.frame(path=p,group1=groups[ij[1]],group2=groups[ij[2]],difference=val,
           ci_lower=lb,ci_upper=ub,ci_status=cistatus,ci_solver=solver,native_ci_code_lower=native_lower,native_ci_code_upper=native_upper,
           as.data.frame(z),message=paste(q$error %||% '',cf$error %||% '',fallback_error),stringsAsFactors=FALSE)
    }
    pair<-do.call(rbind,rows);pair$p_holm<-p.adjust(pair$p_raw,'holm',n=n_tests)
    pair$family<-'all_requested_pairwise_tests';pair$analysis_role<-mode
  }
  list(omnibus=omni,path_tests=per,pairwise=pair,group_paths=do.call(rbind,lapply(fits,`[[`,'paths')),
       groups=info,group_pool=pool,fits=fits,free=free,diagnostics=diags,contrast_profiles=contrast_profiles)
}
