args <- commandArgs(TRUE)
stopifnot(length(args)==2L)
runtime <- args[1]; lock <- args[2]
if (as.character(getRversion())!='4.6.0') stop('This release is tested and locked to R 4.6.0.')
dir.create(runtime,recursive=TRUE,showWarnings=FALSE)
lib<-file.path(runtime,'library');dir.create(lib,showWarnings=FALSE)
bootstrap<-file.path(runtime,'bootstrap');dir.create(bootstrap,showWarnings=FALSE)
.libPaths(c(lib,bootstrap,.Library))
options(repos=c(CRAN='https://cloud.r-project.org'),timeout=600)
if (!requireNamespace('renv',quietly=TRUE) || as.character(packageVersion('renv'))!='1.2.3') {
  install.packages('https://cran.r-project.org/src/contrib/Archive/renv/renv_1.2.3.tar.gz',
                   repos=NULL,type='source',lib=bootstrap)
  .libPaths(c(bootstrap,lib,.Library))
}
renv::restore(project=runtime,library=lib,lockfile=lock,prompt=FALSE)
file.copy(lock,file.path(runtime,'renv.lock'),overwrite=TRUE)
cat('Environment restored. Analysis commands are offline.\n')
