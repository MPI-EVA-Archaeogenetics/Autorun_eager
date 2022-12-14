#!/use/bin/env bash

VERSION="1.1.2"


## Helptext function
function Helptext() {
  echo -ne "\t usage: $0 [options] <ind_id>\n\n"
  echo -ne "This script pulls data and metadata from Autorun_eager for the TF version of the specified individual and creates a poseidon package.\n\n"
  echo -ne "Options:\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

## Print messages to stderr
function errecho() { echo $* 1>&2 ;}


## Parse CLI args.
TEMP=`getopt -q -o hv --long help,version -n 'update_poseidon_package.sh' -- "$@"`
eval set -- "$TEMP"

## parameter default
ind_id=''

## Read in CLI arguments
while true ; do
  case "$1" in
    -h|--help) Helptext; exit 0 ;;
    -v|--version) echo ${VERSION}; exit 0;;
    --) ind_id="${2%_ss}"; break ;; ## Remove the _ss suffix already if provided.
    *) echo -e "invalid option provided: $1.\n"; Helptext; exit 1;;
  esac
done

autorun_root_dir='/mnt/archgen/Autorun_eager/'
root_input_dir='/mnt/archgen/Autorun_eager/eager_outputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each site and individual.
root_output_dir='/mnt/archgen/Autorun_eager/poseidon_packages' ## Directory that includes data type, site ID and ind ID subdirs.
input_dir="${root_input_dir}/TF/${ind_id:0:3}/${ind_id}/genotyping/"
output_dir="${root_output_dir}/TF/${ind_id:0:3}/${ind_id}/"

## Ensure an ind_id was provided, and eager results exist.
if [[ ${ind_id} == '' ]]; then
  errecho "[update_poseidon_package.sh]: No individual ID provided.\n"
  Helptext
  exit 1
elif [[ -d ${input_dir} ]]; then
  errecho "[update_poseidon_package.sh]: Expected eager output directory '${input_dir}' does not exist."
  exit 1
fi

## Additional error in case no new genotypes exist (without .txt suffix)
##    If neither genotype file exists throw an error
if [[ ! -f ${input_dir}/pileupcaller.single.geno ]] && [[ ! -f ${input_dir}/pileupcaller.double.geno ]]; then
  errecho "[update_poseidon_package.sh]: No valid genotype files (*.geno) found in output directory."
  errecho "Are the genotypes for this individual from an older eager version?"
  exit 1
fi

## If no poseidon package exists, make one
if [[ ! -d ${output_dir} ]] && [[ -f ${input_dir}/pileupcaller.single.geno ]] && [[ -f ${input_dir}/pileupcaller.double.geno ]]; then
  ###############################
  ## No package, both ds & ss ##
  ###############################
  
  errecho "Creating new mixed geno package for: ${ind_id}"
  ## Create temp dir to put merged genos in
  TEMPDIR=$(mktemp -d ${autorun_root_dir}/.tmp/${ind_id}_XXXXXXXX)
  ## Paste together genos with null delimiter ('\0') to paste the two together
  paste -d '\0' ${input_dir}/pileupcaller.double.geno ${input_dir}/pileupcaller.single.geno >${TEMPDIR}/${ind_id}.geno
  ## snp file is the same, so just copy the dsDNA one
  cp ${input_dir}/pileupcaller.double.snp ${TEMPDIR}/${ind_id}.snp
  ## Finally concatenate ind files
  cat ${input_dir}/pileupcaller.double.ind ${input_dir}/pileupcaller.single.ind >${TEMPDIR}/${ind_id}.ind

  ## Create directory for poseidon package if necessary (used to be trident could not create multiple dirs deep structure)
  mkdir -p $(dirname ${output_dir})

  ## Then create new poseidon pacakge in tempdir (so users dont pick up half-made packages.)
  trident init \
    --inFormat EIGENSTRAT \
    --snpSet "1240K" \
    --genoFile ${TEMPDIR}/${ind_id}.geno \
    --snpFile ${TEMPDIR}/${ind_id}.snp \
    --indFile ${TEMPDIR}/${ind_id}.ind \
    --outPackagePath ${TEMPDIR}/${ind_id}/

  ## TODO Populate the janno file

  ## TODO Use trident update to get correct md5sums and add log info
  ## TODO move package dir to live output_dir

  ## Then remove temp files
  rm ${TEMPDIR}/${ind_id}.*
  ## Playing extra safe by avoiding rm -r
  rmdir ${TEMPDIR}

## If no package exists, but only one of the two genos exists create pacakge without pasting
elif [[ ! -d ${output_dir} ]]; then
  ################################
  ## No package, one of ds | ss ##
  ################################

  errecho "Creating new package for: ${ind_id}"
  ## Create temp dir to put renamed symlinks in
  TEMPDIR=$(mktemp -d ${autorun_root_dir}/.tmp/${ind_id}_XXXXXXXX)
  
  ln -s ${input_dir}/pileupcaller*geno ${TEMPDIR}/${ind_id}.geno
  ln -s ${input_dir}/pileupcaller*snp  ${TEMPDIR}/${ind_id}.snp
  ln -s ${input_dir}/pileupcaller*ind  ${TEMPDIR}/${ind_id}.ind

  ## Create directory for poseidon package if necessary (used to be trident could not create multiple dirs deep structure)
  mkdir -p $(dirname ${output_dir})

  ## Then create new poseidon pacakge
  trident init \
    --inFormat EIGENSTRAT \
    --snpSet "1240K" \
    --genoFile ${TEMPDIR}/${ind_id}.geno \
    --snpFile ${TEMPDIR}/${ind_id}.snp \
    --indFile ${TEMPDIR}/${ind_id}.ind \
    --outPackagePath  ${TEMPDIR}/${ind_id}/

  ## TODO Populate the janno file

  ## TODO Use trident update to get correct md5sums and add log info
  ## TODO move package dir to live output_dir

  ## Then remove temp files
  rm ${TEMPDIR}/${ind_id}.*
  ## Playing extra safe by avoiding rm -r
  rmdir ${TEMPDIR}

## The test -nt checks that file 1 is NEWER THAN file 2. non existing files are considered older than existing files.
elif [[ -d ${output_dir} ]] && [[ ( -f ${input_dir}/pileupcaller.single.geno && -f ${input_dir}/pileupcaller.double.geno ) ]] && [[ ( ${input_dir}/pileupcaller.single.geno -nt ${output_dir}/${ind_id}.geno || ${input_dir}/pileupcaller.double.geno -nt ${output_dir}/${ind_id}.geno ) ]] ; then
  ##########################################################################
  ## Package exists, both ds & ss, either one is newer than package .geno ##
  ##########################################################################
  
  errecho "Updating mixed-geno package for: ${ind_id}"

  ## Create temp dir to put package in for updating, so users dont get a half-baked package.
  TEMPDIR=$(mktemp -d ${autorun_root_dir}/.tmp/${ind_id}_XXXXXXXX)
  
  ## Copy over poseidon package files excluding the dataset
  mkdir ${TEMPDIR}/${ind_id}
  cp ${output_dir}/*.bib        ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/CHANGELOG.md ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/*.janno      ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/POSEIDON.yml ${TEMPDIR}/${ind_id}/

  ## Paste together genos with null delimiter ('\0') to paste the two together. Output goes in temp poseidon package
  paste -d '\0' ${input_dir}/pileupcaller.double.geno ${input_dir}/pileupcaller.single.geno >${TEMPDIR}/${ind_id}/${ind_id}.geno
  ## snp file is the same, so just copy the dsDNA one
  cp ${input_dir}/pileupcaller.double.snp ${TEMPDIR}/${ind_id}/${ind_id}.snp
  ## Finally concatenate ind files
  cat ${input_dir}/pileupcaller.double.ind ${input_dir}/pileupcaller.single.ind >${TEMPDIR}/${ind_id}/${ind_id}.ind

  ## TODO Populate the janno file

  ## TODO Use trident update to get correct md5sums and add log info
  ## TODO move package dir to live output_dir

  ## Remove live version of poseidon package, and move temp version to live.
  rm    ${output_dir}/*
  rmdir ${output_dir}
  mv    ${TEMPDIR}/${ind_id}/    ${output_dir}/

## The test -nt checks that file 1 is NEWER THAN file 2. non existing files are considered older than existing files. 
## If either genotype file is newer than the package, update. The file that does not exist will not be newer than the poseidon pacakge. If both exist, the previous conditional chunk ran.
elif [[ -d ${output_dir} ]] && [[ ( ${input_dir}/pileupcaller.single.geno -nt ${output_dir}/${ind_id}.geno || ${input_dir}/pileupcaller.double.geno -nt ${output_dir}/${ind_id}.geno ) ]] ; then
  ############################################################################
  ## Package exists, one of ds & ss, either one is newer than package .geno ##
  ############################################################################

  errecho "Updating package for: ${ind_id}"

  ## Create temp dir to put package in for updating, so users dont get a half-baked package.
  TEMPDIR=$(mktemp -d ${autorun_root_dir}/.tmp/${ind_id}_XXXXXXXX)
  
  ## Copy over poseidon package files excluding the dataset
  mkdir ${TEMPDIR}/${ind_id}
  cp ${output_dir}/*.bib        ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/CHANGELOG.md ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/*.janno      ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/POSEIDON.yml ${TEMPDIR}/${ind_id}/

  ## Copy over new genotype data to poseidon package dir
  cp ${input_dir}/pileupcaller*geno ${TEMPDIR}/${ind_id}/${ind_id}.geno
  cp ${input_dir}/pileupcaller*snp  ${TEMPDIR}/${ind_id}/${ind_id}.snp
  cp ${input_dir}/pileupcaller*ind  ${TEMPDIR}/${ind_id}/${ind_id}.ind

  ## TODO Populate the janno file

  ## TODO Use trident update to get correct md5sums and add log info
  ## TODO move package dir to live output_dir

  ## Remove live version of poseidon package, and move temp version to live.
  rm    ${output_dir}/*
  rmdir ${output_dir}
  mv    ${TEMPDIR}/${ind_id}/    ${output_dir}/
