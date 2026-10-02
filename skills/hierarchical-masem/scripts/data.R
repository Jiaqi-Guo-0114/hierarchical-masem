`%||%` <- function(a,b) if(is.null(a)) b else a
fail <- function(...) stop(paste0(...),call.=FALSE)
jread <- function(p) jsonlite::fromJSON(p,simplifyVector=FALSE)
jwrite <- function(x,p) jsonlite::write_json(x,p,pretty=TRUE,auto_unbox=TRUE,na='null',digits=16,null='null')
cwrite <- function(x,p) utils::write.csv(x,p,row.names=FALSE,na='',fileEncoding='UTF-8')
asvec <- function(x) unlist(x,use.names=FALSE)
pd <- function(x) all(is.finite(x)) && max(abs(x-t(x)))<1e-8 &&
  min(eigen(x,symmetric=TRUE,only.values=TRUE)$values)>1e-10
pair_key <- function(i,j) sprintf('r%03d_%03d',pmin(i,j),pmax(i,j))
pair_map <- function(vars) {
  ij<-which(lower.tri(matrix(0,length(vars),length(vars))),arr.ind=TRUE)
  data.frame(type=pair_key(ij[,1],ij[,2]),var1=vars[ij[,1]],var2=vars[ij[,2]],
             i=ij[,1],j=ij[,2],stringsAsFactors=FALSE)
}

validate_analysis_options <- function(cfg,spec,has_groups) {
  # Validate requests before the first statistical fit, so a typo cannot leave
  # the user waiting for a run whose requested comparisons cannot be performed.
  settings<-cfg$sensitivity$settings %||% list(c(0,0),c(.5,.5),c(1,1))
  settings<-lapply(settings,asvec)
  values<-unlist(settings,use.names=FALSE)
  if(!length(settings)||any(lengths(settings)!=2L)||!is.numeric(values)||
     any(!is.finite(values))||any(values<0|values>1))
    fail('sensitivity.settings must contain nonempty numeric [rho,phi] pairs in [0,1].')
  loo<-cfg$sensitivity$leave_one_study_out
  if(!is.null(loo)&&(!is.logical(loo)||length(loo)!=1L||is.na(loo)))
    fail('sensitivity.leave_one_study_out must be true or false.')
  mode<-cfg$moderation$mode %||% 'none'
  if(length(mode)!=1L||!is.character(mode)||!mode%in%c('none','planned','exploratory'))
    fail('moderation.mode must be none, planned, or exploratory.')
  paths<-as.character(asvec(cfg$moderation$path_tests %||% list()))
  pairwise<-as.character(asvec(cfg$moderation$pairwise_paths %||% list()))
  if(anyDuplicated(paths)||anyDuplicated(pairwise)||!all(c(paths,pairwise)%in%spec$paths$path))
    fail('Invalid or duplicate moderation path labels; use directed path labels from model.json.')
  if(length(c(paths,pairwise))){
    if(mode=='none')fail('Follow-up tests need explicit planned or exploratory mode.')
    if(!has_groups)fail('Requested moderation follow-ups require a categorical moderator in config.json.')
  }
  invisible(TRUE)
}

read_inputs <- function(project) {
  cfg<-jread(file.path(project,'config.json'))
  if (!identical(cfg$schema_version,1L)) fail('Unsupported config schema_version; expected 1.')
  vars<-as.character(asvec(cfg$variables))
  if (length(vars)<2L || anyNA(vars) || any(!nzchar(vars)) || anyDuplicated(vars)) fail('variables must be distinct nonempty names.')
  if (!identical(cfg$sample_independence,'confirmed_independent'))
    fail('Confirm independent participant samples from study coding: sample_independence must be confirmed_independent. Repeated/overlapping samples need another method.')
  if (!identical(cfg$correlation_type,'pearson')) fail('This release supports raw Pearson correlations only.')
  path<-file.path(project,cfg$data_file)
  if (grepl('\\.xlsx$',path,ignore.case=TRUE)) {
    raw<-as.data.frame(readxl::read_xlsx(path,col_types='text',.name_repair='minimal',
                              na=c('','NA','NA.00','-99')),stringsAsFactors=FALSE)
  } else if(grepl('\\.csv$',path,ignore.case=TRUE)) {
    raw<-read.csv(path,colClasses='character',check.names=FALSE,na.strings=c('','NA','NA.00','-99'))
  } else fail('Input must be CSV or XLSX.')
  if(anyDuplicated(names(raw))) fail('Duplicate column names.')
  required<-c('study_id','sample_id','var1','var2','r','n')
  cols<-cfg$columns %||% as.list(setNames(required,required))
  if (!all(required %in% names(cols))) fail('columns mapping must contain study_id, sample_id, var1, var2, r, n.')
  if (!all(asvec(cols) %in% names(raw))) fail('Mapped columns are missing from input.')
  d<-as.data.frame(raw[,asvec(cols),drop=FALSE],stringsAsFactors=FALSE);names(d)<-names(cols)
  for(nm in required) if(anyNA(d[[nm]])||any(!nzchar(trimws(d[[nm]])))) fail('Missing values in ',nm,'. Partial matrices are outside this release; no automatic deletion or imputation.')
  for(nm in c('study_id','sample_id','var1','var2'))if(any(d[[nm]]!=trimws(d[[nm]])))fail('Leading/trailing whitespace in ',nm,'; reconcile identifiers explicitly.')
  for(nm in c('r','n'))d[[nm]]<-suppressWarnings(as.numeric(d[[nm]]))
  if(any(!is.finite(d$r))||any(abs(d$r)>=1)) fail('Correlations must be finite and strictly between -1 and 1.')
  if(any(!is.finite(d$n))||any(d$n<5)||any(d$n!=floor(d$n))) fail('Sample sizes must be integer counts >=5 for rcalc().')
  if(!all(c(d$var1,d$var2) %in% vars))fail('Unrecognized variable; harmonize construct names explicitly.')
  if(any(d$var1==d$var2))fail('Do not include diagonal correlations.')
  d$type<-pair_key(match(d$var1,vars),match(d$var2,vars))
  d$sample_key<-paste0(nchar(d$study_id),':',d$study_id,'|',nchar(d$sample_id),':',d$sample_id)
  if(anyDuplicated(paste(d$sample_key,d$type,sep='/')))fail('Duplicate variable pair within a sample, including reversed pairs or duplicate reports.')
  if('effect_id' %in% names(d) && anyDuplicated(d$effect_id))fail('Duplicate effect_id.')
  pairs<-pair_map(vars)
  d<-d[order(d$sample_key,match(d$type,pairs$type)),,drop=FALSE];rownames(d)<-NULL
  samples<-split(d,d$sample_key)
  for(s in samples) {
    if(nrow(s)!=nrow(pairs)||!setequal(s$type,pairs$type))fail('Incomplete correlation matrix for sample ',s$sample_key[1],'.')
    if(length(unique(s$n))!=1L)fail('Unequal pairwise sample sizes within ',s$sample_key[1],'; reconcile actual sample size before analysis.')
    m<-diag(length(vars));m[cbind(match(s$var1,vars),match(s$var2,vars))]<-s$r
    m[cbind(match(s$var2,vars),match(s$var1,vars))]<-s$r
    if(!pd(m))fail('Non-positive-definite correlation matrix: ',s$sample_key[1],'. No automatic nearPD repair.')
  }
  registry<-do.call(rbind,lapply(samples,function(s)s[1,c('study_id','sample_id','sample_key','n'),drop=FALSE]))
  rownames(registry)<-NULL
  if(length(unique(d$study_id))<2L)fail('At least two independent studies are required for between-study random effects.')
  if('overlap_group' %in% names(d)){
    for(s in samples)if(length(unique(na.omit(s$overlap_group)))>1L)fail('Inconsistent overlap_group within sample.')
    og<-vapply(samples,function(s){v<-unique(na.omit(s$overlap_group));if(length(v))v[1] else ''},'')
    if(anyDuplicated(og[nzchar(og)]))fail('Overlapping participant samples detected by overlap_group. This workflow cannot treat them as independent.')
  }
  mod<-cfg$moderator %||% NULL
  if(!is.null(mod)){
    if(!identical(mod$type,'categorical'))fail('Continuous moderators require a separately validated one-stage MASEM workflow; do not categorize automatically.')
    if(!mod$column %in% names(raw))fail('Moderator column missing.')
    lookup<-setNames(raw[[mod$column]],paste0(nchar(raw[[cols$study_id]]),':',raw[[cols$study_id]],'|',nchar(raw[[cols$sample_id]]),':',raw[[cols$sample_id]],'/',
          pair_key(match(raw[[cols$var1]],vars),match(raw[[cols$var2]],vars))))
    d$group<-unname(lookup[paste(d$sample_key,d$type,sep='/')])
    if(anyNA(d$group)||any(!nzchar(d$group)))fail('Missing moderator values.')
    if(length(unique(d$group))<2L)fail('Moderator needs at least two groups.')
    if(any(vapply(split(d$group,d$study_id),function(x)length(unique(x))!=1L,TRUE)))
      fail('Studies occur in more than one moderator group; independent multigroup WLS is invalid. Joint cross-group covariance is required.')
    if(any(vapply(split(d,d$group),function(s)length(unique(s$study_id))<2L,TRUE)))
      fail('Each moderator group requires at least two independent studies.')
  }
  d$es_id<-seq_len(nrow(d));d$type<-factor(d$type,levels=pairs$type)
  d$study_cluster<-factor(d$study_id);d$sample_cluster<-factor(d$sample_key)
  # rcalc returns dat and V together. Explicitly join the former back to the coded data.
  sampling<-function(x){
    z<-metafor::rcalc(r~var1+var2|sample_key,ni=n,data=x,rtoz=FALSE)
    kk<-paste(z$dat$sample_key,pair_key(match(z$dat$var1,vars),match(z$dat$var2,vars)),sep='/')
    idx<-match(kk,paste(x$sample_key,x$type,sep='/'))
    if(anyNA(idx)||anyDuplicated(idx)||length(idx)!=nrow(x))fail('Could not align rcalc data and sampling covariance.')
    dd<-x[idx,,drop=FALSE]
    if(max(abs(dd$r-z$dat$yi))>1e-12||!pd(z$V))fail('Invalid or misaligned sampling covariance matrix.')
    list(data=dd,V=unname(z$V))
  }
  model<-jread(file.path(project,cfg$model_file %||% 'model.json'))
  spec<-read_model(model,vars)
  validate_analysis_options(cfg,spec,!is.null(mod))
  report<-list(status='valid',n_studies=length(unique(d$study_id)),n_samples=nrow(registry),
       n_correlations=nrow(d),n_total=sum(registry$n),legacy_unique_n=sum(unique(d$n)),
       sample_independence=cfg$sample_independence,variables=vars,
       complete_matrices=TRUE,positive_definite=TRUE,
       groups=if(is.null(mod)) NULL else as.list(table(d$group)/nrow(pairs)),
       few_studies=length(unique(d$study_id))<10L)
  list(cfg=cfg,data=d,registry=registry,pairs=pairs,sampling=sampling,model=spec,checks=report)
}

read_model <- function(model,vars) {
  if(!identical(as.character(asvec(model$variables)),vars))fail('Model variables and config variables must have identical order.')
  p<-length(vars)
  mat<-function(x) {
    if(length(x)!=p||any(lengths(x)!=p))fail('RAM matrices must be square with one row/column per observed variable.')
    m<-matrix(as.character(asvec(x)),nrow=p,byrow=TRUE,dimnames=list(vars,vars))
    if(any(!grepl('^[-+]?[0-9.]+([eE][-+]?[0-9]+)?(\\*[A-Za-z][A-Za-z0-9_]*)?$',m)))fail('RAM cells must be numeric or start*parameter_label.')
    if(any(!is.finite(suppressWarnings(as.numeric(sub('\\*.*$','',m))))))fail('Nonfinite or malformed RAM starting value.')
    m
  }
  A<-mat(model$A);S<-mat(model$S)
  if(!identical(S,t(S)))fail('RAM S must be symmetric.')
  label<-function(m)ifelse(grepl('*',m,fixed=TRUE),sub('^[^*]+\\*','',m),'')
  Al<-label(A);Sl<-label(S);dim(Al)<-dim(Sl)<-c(p,p)
  if(any(diag(Al)!='')||any(suppressWarnings(as.numeric(diag(A)))!=0))fail('Self-directed RAM paths are unsupported.')
  # This release supports observed-variable recursive path models, not feedback/latent models.
  adj<-matrix(grepl('*',A,fixed=TRUE)|suppressWarnings(as.numeric(A))!=0,p,p);adj[is.na(adj)]<-TRUE
  reach<-adj
  for(k in seq_len(p))reach<-reach|(outer(reach[,k],reach[k,],`&`))
  if(any(diag(reach)))fail('Cyclic paths require separate identification and stability checks; use an acyclic observed-variable RAM model.')
  a_labels<-Al[nzchar(Al)]
  if(anyDuplicated(a_labels))fail('Use unique labels for directed paths; this release applies equality constraints only in group comparisons.')
  all_labels<-unique(c(a_labels,Sl[nzchar(Sl)]))
  if(any(a_labels %in% Sl))fail('A and S parameters must have distinct labels.')
  free_diag<-which(nzchar(diag(Sl)))
  if(any(!nzchar(diag(Sl)) & suppressWarnings(as.numeric(diag(S)))!=1,na.rm=TRUE))fail('Fixed RAM S diagonal entries must be 1.')
  ij<-which(Al!='',arr.ind=TRUE)
  paths<-data.frame(path=Al[ij],outcome=vars[ij[,1]],predictor=vars[ij[,2]],i=ij[,1],j=ij[,2],stringsAsFactors=FALSE)
  if(!nrow(paths))fail('Model contains no directed paths.')
  list(A=A,S=S,Al=Al,Sl=Sl,labels=all_labels,paths=paths,free_diag=free_diag,variables=vars)
}
