#!/usr/bin/env bash

VERSION="1.6.0"

## DEPENDENCY
pandora_helper="/mnt/archgen/tools/helper_scripts/py_helpers/pyPandoraHelper/pyPandoraHelper.py"

## Colours for printing to terminal
Yellow=$(tput sgr0)'\033[1;33m' ## Yellow normal face
Red=$(tput sgr0)'\033[1;31m' ## Red normal face
Normal=$(tput sgr0)

## Helptext function
function Helptext() {
  echo -ne "\t usage: $0 [options] <ind_id>\n\n"
  echo -ne "This script pulls data and metadata from Autorun_eager for the TF version of the specified individual and creates a poseidon package.\n\n"
  echo -ne "Options:\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

## Print messages to stderr
function errecho() { echo -e $* 1>&2 ;}


## Parse CLI args.
TEMP=`getopt -q -o hv --long help,version -n 'update_poseidon_package.sh' -- "$@"`
eval set -- "$TEMP"

## parameter defaults
ind_id=''
contamination_snp_cutoff="100"  ## Provided to fill_in_janno.R
ss_suffix="_ss"                 ## Provided to fill_in_janno.R
geno_ploidy='haploid'           ## Provided to fill_in_janno.R
date_stamp="$(date +'%D')"

## Read in CLI arguments
while true ; do
  case "$1" in
    -h|--help) Helptext; exit 0 ;;
    -v|--version) echo ${VERSION}; exit 0;;
    --) ind_id="${2%${ss_suffix}}"; break ;; ## Remove the _ss suffix already if provided.
    *) echo -e "invalid option provided: $1.\n"; Helptext; exit 1;;
  esac
done

site_id=`${pandora_helper} -g site_id ${ind_id}` ## Site inferred by pyPandoraHelper

autorun_root_dir='/mnt/archgen/Autorun_eager/'
root_input_dir='/mnt/archgen/Autorun_eager/eager_outputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each site and individual.
root_output_dir='/mnt/archgen/Autorun_eager/poseidon_packages' ## Directory that includes data type, site ID and ind ID subdirs.
# root_output_dir='/mnt/archgen/Autorun_eager/dev/poseidon_packages' ## dev directory for testing the creation of poseidon packages.
input_dir="${root_input_dir}/TF/${site_id}/${ind_id}/genotyping/"
output_dir="${root_output_dir}/TF/${site_id}/${ind_id}/"
cred_file="${autorun_root_dir}/.eva_credentials"
trident_path="/r1/people/srv_autoeager/bin/trident-1.1.4.2"

## Local Testing
# autorun_root_dir='/Users/lamnidis/Software/github/MPI-EVA-Archaeogenetics/Autorun_eager'
# root_input_dir='/Users/lamnidis/mount/eager_outputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each site and individual.
# root_output_dir='/Users/lamnidis/Software/github/MPI-EVA-Archaeogenetics/Autorun_eager/test_data/' ## Directory that includes data type, site ID and ind ID subdirs.
# input_dir="${root_input_dir}/TF/${site_id}/${ind_id}/genotyping/"
# output_dir="${root_output_dir}/TF/${site_id}/${ind_id}/"
# cred_file="/Users/lamnidis/Software/github/Schiffels-Popgen/MICROSCOPE-processing-pipeline/.credentials"
# trident_path=$(which trident)

## Ensure an ind_id was provided, and eager results exist.
if [[ ${ind_id} == '' ]]; then
  errecho "[update_poseidon_package.sh]: No individual ID provided.\n"
  Helptext
  exit 1
elif [[ ! -d ${input_dir} ]]; then
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
  
  errecho "${Yellow}[update_poseidon_package.sh]: Creating new mixed geno package for: ${ind_id}${Normal}"
  ## Create temp dir to put merged genos in
  TEMPDIR=$(mktemp -d ${autorun_root_dir}/.tmp/${ind_id}_XXXXXXXX)
  ## Paste together genos with null delimiter ('\0') to paste the two together
  paste -d '\0' ${input_dir}/pileupcaller.double.geno ${input_dir}/pileupcaller.single.geno >${TEMPDIR}/${ind_id}.geno
  ## snp file is the same, so just copy the dsDNA one
  cp ${input_dir}/pileupcaller.double.snp ${TEMPDIR}/${ind_id}.snp
  ## Finally concatenate ind files
  cat ${input_dir}/pileupcaller.double.ind ${input_dir}/pileupcaller.single.ind >${TEMPDIR}/${ind_id}.ind

  errecho "${Yellow}## Package Creation ##${Normal}"
  ## Then create new poseidon pacakge in tempdir (so users dont pick up half-made packages.)
  ${trident_path} init \
    --inFormat EIGENSTRAT \
    --snpSet 1240K \
    --genoFile ${TEMPDIR}/${ind_id}.geno \
    --snpFile ${TEMPDIR}/${ind_id}.snp \
    --indFile ${TEMPDIR}/${ind_id}.ind \
    --outPackagePath ${TEMPDIR}/${ind_id}

  ## Populate the janno file
  errecho "${Yellow}## Populating janno file ##${Normal}"
  ${autorun_root_dir}/scripts/fill_in_janno.R \
    -j ${TEMPDIR}/${ind_id}/${ind_id}.janno \
    -i ${ind_id} \
    -c ${cred_file} \
    -s ${contamination_snp_cutoff} \
    -p ${geno_ploidy} \
    -S ${ss_suffix}

  ## Mirror sex and group_name information to ind file.
  errecho "${Yellow}## Updating indFile ##${Normal}"
  ${autorun_root_dir}/scripts/update_dataset_from_janno.R -y ${TEMPDIR}/${ind_id}/POSEIDON.yml

  ## Use trident update to get correct md5sums and add log info
  ##    Also add TCL and KP as contributors. Can be changed before publishing the package if users want.
  errecho "${Yellow}## Trident update ##${Normal}"
  ${trident_path} update \
    -d ${TEMPDIR}/${ind_id} \
    --logText "${date_stamp} Package creation" \
    --versionComponent Major \
    --newContributors '[Thiseas C. Lamnidis](thiseas_christos_lamnidis@eva.mpg.de)' \
    --newContributors '[Kay Pruefer](kay_pruefer@eva.mpg.de)'

  if [[ $? != 0 ]]; then
    errecho "${Red}Problem updating package${Normal}"
    exit 1
  fi

  ## Validate package to ensure it works
  errecho "${Yellow}## Trident validate ##${Normal}"
  ${trident_path} validate -d ${TEMPDIR}/${ind_id}

  ## Only move package dir to live output_dir if validation passed
  if [[ $? == 0 ]]; then
    errecho "${Yellow}## Moving temp package to live ##${Normal}"
    ## Create directory for poseidon package if necessary (used to be trident could not create multiple dirs deep structure)
    ##  Only created now to not trip up the script if execution did not run through fully.
    mkdir -p $(dirname ${output_dir})

    ## Add AE version file to package
    echo "${VERSION}" > ${TEMPDIR}/${ind_id}/AE_version.txt

    ## Move package to live
    mv ${TEMPDIR}/${ind_id}/    ${output_dir}/

    ## Then remove temp files
    errecho "${Yellow}## Removing temp directory ##${Normal}"
    ## Playing it safe by avoiding rm -r
    rm ${TEMPDIR}/${ind_id}.*
    rmdir ${TEMPDIR}
  fi

## If no package exists, but only one of the two genos exists create pacakge without pasting
elif [[ ! -d ${output_dir} ]]; then
  ################################
  ## No package, one of ds | ss ##
  ################################

  errecho "${Yellow}[update_poseidon_package.sh]: Creating new package for: ${ind_id}${Normal}"
  ## Create temp dir to put renamed symlinks in
  TEMPDIR=$(mktemp -d ${autorun_root_dir}/.tmp/${ind_id}_XXXXXXXX)
  
  ln -s ${input_dir}/pileupcaller*geno ${TEMPDIR}/${ind_id}.geno
  ln -s ${input_dir}/pileupcaller*snp  ${TEMPDIR}/${ind_id}.snp
  ln -s ${input_dir}/pileupcaller*ind  ${TEMPDIR}/${ind_id}.ind

  ## Then create new poseidon pacakge
  errecho "${Yellow}## Package Creation ##${Normal}"
  ${trident_path} init \
    --inFormat EIGENSTRAT \
    --snpSet 1240K \
    --genoFile ${TEMPDIR}/${ind_id}.geno \
    --snpFile ${TEMPDIR}/${ind_id}.snp \
    --indFile ${TEMPDIR}/${ind_id}.ind \
    --outPackagePath  ${TEMPDIR}/${ind_id}

  ## Populate the janno file
  errecho "${Yellow}## Populating janno file ##${Normal}"
  ${autorun_root_dir}/scripts/fill_in_janno.R \
    -j ${TEMPDIR}/${ind_id}/${ind_id}.janno \
    -i ${ind_id} \
    -c ${cred_file} \
    -s ${contamination_snp_cutoff} \
    -p ${geno_ploidy} \
    -S ${ss_suffix}

  ## Mirror sex and group_name information to ind file.
  errecho "${Yellow}## Updating indFile ##${Normal}"
  ${autorun_root_dir}/scripts/update_dataset_from_janno.R -y ${TEMPDIR}/${ind_id}/POSEIDON.yml

  ## Use trident update to get correct md5sums and add log info
  ##    Also add TCL and KP as contributors. Can be changed before publishing the package if users want.
  errecho "${Yellow}## Trident update ##${Normal}"
  ${trident_path} update \
    -d ${TEMPDIR}/${ind_id} \
    --logText "${date_stamp} Package creation" \
    --versionComponent Major \
    --newContributors '[Thiseas C. Lamnidis](thiseas_christos_lamnidis@eva.mpg.de)' \
    --newContributors '[Kay Pruefer](kay_pruefer@eva.mpg.de)'

  if [[ $? != 0 ]]; then
    errecho "${Red}Problem updating package${Normal}"
    exit 1
  fi

  ## Validate package to ensure it works
  errecho "${Yellow}## Trident validate ##${Normal}"
  ${trident_path} validate -d ${TEMPDIR}/${ind_id}

  ## Only move package dir to live output_dir if validation passed
  if [[ $? == 0 ]]; then
    errecho "${Yellow}## Moving temp package to live ##${Normal}"
    ## Create directory for poseidon package if necessary (used to be trident could not create multiple dirs deep structure)
    ##  Only created now to not trip up the script if execution did not run through fully.
    mkdir -p $(dirname ${output_dir})

    ## Add AE version file to package
    echo "${VERSION}" > ${TEMPDIR}/${ind_id}/AE_version.txt

    ## Move package to live
    mv ${TEMPDIR}/${ind_id}/    ${output_dir}/

    ## Then remove temp files
    errecho "${Yellow}## Removing temp directory ##${Normal}"
    rm ${TEMPDIR}/${ind_id}.*
    ## Playing extra safe by avoiding rm -r
    rmdir ${TEMPDIR}
  fi

## The test -nt checks that file 1 is NEWER THAN file 2. non existing files are considered older than existing files.
elif [[ -d ${output_dir} ]] && [[ ( -f ${input_dir}/pileupcaller.single.geno && -f ${input_dir}/pileupcaller.double.geno ) ]] && [[ ( ${input_dir}/pileupcaller.single.geno -nt ${output_dir}/${ind_id}.geno || ${input_dir}/pileupcaller.double.geno -nt ${output_dir}/${ind_id}.geno ) ]] ; then
  ##########################################################################
  ## Package exists, both ds & ss, either one is newer than package .geno ##
  ##########################################################################
  
  errecho "${Yellow}[update_poseidon_package.sh]: Updating mixed-geno package for: ${ind_id}${Normal}"

  ## Create temp dir to put package in for updating, so users dont get a half-baked package.
  TEMPDIR=$(mktemp -d ${autorun_root_dir}/.tmp/${ind_id}_XXXXXXXX)
  
  ## Copy over poseidon package files excluding the dataset
  errecho "${Yellow}## Copying package backbone ##${Normal}"
  mkdir ${TEMPDIR}/${ind_id}
  cp ${output_dir}/${ind_id}.bib    ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/CHANGELOG.md     ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/${ind_id}.janno  ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/POSEIDON.yml     ${TEMPDIR}/${ind_id}/

  errecho "${Yellow}## Pulling new dataset ##${Normal}"
  ## Paste together genos with null delimiter ('\0') to paste the two together. Output goes in temp poseidon package
  paste -d '\0' ${input_dir}/pileupcaller.double.geno ${input_dir}/pileupcaller.single.geno >${TEMPDIR}/${ind_id}/${ind_id}.geno
  ## snp file is the same, so just copy the dsDNA one
  cp ${input_dir}/pileupcaller.double.snp ${TEMPDIR}/${ind_id}/${ind_id}.snp
  ## Finally concatenate ind files
  cat ${input_dir}/pileupcaller.double.ind ${input_dir}/pileupcaller.single.ind >${TEMPDIR}/${ind_id}/${ind_id}.ind

  ## Populate the janno file
  errecho "${Yellow}## Populating janno file ##${Normal}"
  ${autorun_root_dir}/scripts/fill_in_janno.R \
    -j ${TEMPDIR}/${ind_id}/${ind_id}.janno \
    -i ${ind_id} \
    -c ${cred_file} \
    -s ${contamination_snp_cutoff} \
    -p ${geno_ploidy} \
    -S ${ss_suffix}

  ## Mirror sex and group_name information to ind file.
  errecho "${Yellow}## Updating indFile ##${Normal}"
  ${autorun_root_dir}/scripts/update_dataset_from_janno.R -y ${TEMPDIR}/${ind_id}/POSEIDON.yml

  ## Use trident update to get correct md5sums and add log info
  errecho "${Yellow}## Trident update ##${Normal}"
  ${trident_path} update \
    -d ${TEMPDIR}/${ind_id} \
    --logText "${date_stamp} Update genotypes" \
    --versionComponent Major

  if [[ $? != 0 ]]; then
    errecho "${Red}Problem updating package${Normal}"
    exit 1
  fi

  ## Validate package to ensure it works
  errecho "${Yellow}## Trident validate ##${Normal}"
  ${trident_path} validate -d ${TEMPDIR}/${ind_id}

  ## Only delete live version and replace with temp if validation passed
  if [[ $? == 0 ]]; then
    errecho "${Yellow}## Deleting live package ##${Normal}"
    ## Playing it safe by avoiding rm -r
    rm ${output_dir}/*
    rmdir ${output_dir}

    ## Add AE version file to package
    echo "${VERSION}" > ${TEMPDIR}/${ind_id}/AE_version.txt

    ## Move package dir to live output_dir
    errecho "${Yellow}## Moving temp package to live ##${Normal}"
    mv    ${TEMPDIR}/${ind_id}/    ${output_dir}/
    
    ## Then remove temp files
    errecho "${Yellow}## Removing temp directory ##${Normal}"
    ## Playing it safe by avoiding rm -r
    rm ${TEMPDIR}/${ind_id}.*
    rmdir ${TEMPDIR}
  fi

## The test -nt checks that file 1 is NEWER THAN file 2. non existing files are considered older than existing files. 
## If either genotype file is newer than the package, update. The file that does not exist will not be newer than the poseidon pacakge. If both exist, the previous conditional chunk ran.
elif [[ -d ${output_dir} ]] && [[ ( ${input_dir}/pileupcaller.single.geno -nt ${output_dir}/${ind_id}.geno || ${input_dir}/pileupcaller.double.geno -nt ${output_dir}/${ind_id}.geno ) ]] ; then
  ############################################################################
  ## Package exists, one of ds & ss, either one is newer than package .geno ##
  ############################################################################

  errecho "${Yellow}[update_poseidon_package.sh]: Updating package for: ${ind_id}${Normal}"

  ## Create temp dir to put package in for updating, so users dont get a half-baked package.
  TEMPDIR=$(mktemp -d ${autorun_root_dir}/.tmp/${ind_id}_XXXXXXXX)
  
  ## Copy over poseidon package files excluding the dataset
  errecho "${Yellow}## Copying package backbone ##${Normal}"
  mkdir ${TEMPDIR}/${ind_id}
  cp ${output_dir}/${ind_id}.bib    ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/CHANGELOG.md     ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/${ind_id}.janno  ${TEMPDIR}/${ind_id}/
  cp ${output_dir}/POSEIDON.yml     ${TEMPDIR}/${ind_id}/

  ## Copy over new genotype data to poseidon package dir
  errecho "${Yellow}## Pulling new dataset ##${Normal}"
  cp ${input_dir}/pileupcaller*geno ${TEMPDIR}/${ind_id}/${ind_id}.geno
  cp ${input_dir}/pileupcaller*snp  ${TEMPDIR}/${ind_id}/${ind_id}.snp
  cp ${input_dir}/pileupcaller*ind  ${TEMPDIR}/${ind_id}/${ind_id}.ind

  ## Populate the janno file
  errecho "${Yellow}## Populating janno file ##${Normal}"
  ${autorun_root_dir}/scripts/fill_in_janno.R \
    -j ${TEMPDIR}/${ind_id}/${ind_id}.janno \
    -i ${ind_id} \
    -c ${cred_file} \
    -s ${contamination_snp_cutoff} \
    -p ${geno_ploidy} \
    -S ${ss_suffix}

  ## Mirror sex and group_name information to ind file.
  errecho "${Yellow}## Updating indFile ##${Normal}"
  ${autorun_root_dir}/scripts/update_dataset_from_janno.R -y ${TEMPDIR}/${ind_id}/POSEIDON.yml

  ## Use trident update to get correct md5sums and add log info
  errecho "${Yellow}## Trident update ##${Normal}"
  ${trident_path} update \
    -d ${TEMPDIR}/${ind_id} \
    --logText "${date_stamp} Update genotypes" \
    --versionComponent Major

  if [[ $? != 0 ]]; then
    errecho "${Red}Problem updating package${Normal}"
    exit 1
  fi

  ## Validate package to ensure it works
  errecho "${Yellow}## Trident validate ##${Normal}"
  ${trident_path} validate -d ${TEMPDIR}/${ind_id}

  ## Only delete live version and replace with temp if validation passed
  if [[ $? == 0 ]]; then
    errecho "${Yellow}## Deleting live package ##${Normal}"
    ## Playing it safe by avoiding rm -r
    rm ${output_dir}/*
    rmdir ${output_dir}

    ## Add AE version file to package
    echo "${VERSION}" > ${TEMPDIR}/${ind_id}/AE_version.txt

    ## Move package dir to live output_dir
    errecho "${Yellow}## Moving temp package to live ##${Normal}"
    mv    ${TEMPDIR}/${ind_id}/    ${output_dir}/
    
    ## Then remove temp files
    errecho "${Yellow}## Removing temp directory ##${Normal}"
    ## Playing it safe by avoiding rm -r
    rm ${TEMPDIR}/${ind_id}.*
    rmdir ${TEMPDIR}
  fi

else
  errecho "[update_poseidon_package.sh]: No changes needed for: ${ind_id}"
fi
