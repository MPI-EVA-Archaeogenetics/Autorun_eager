#!/usr/bin/env bash

## Bash strict mode (no -e given, since I want to use check_fail to provide informative error info manually):
set -uo pipefail

VERSION="2.0.0"

## DEPENDENCY
pandora_helper="/mnt/archgen/tools/helper_scripts/py_helpers/pyPandoraHelper/pyPandoraHelper.py"

source /mnt/archgen/Autorun_eager/scripts/helper_functions.sh

## Helptext function
function Helptext() {
  echo -ne "\t usage: $0 [options] <ind_id>\n\n"
  echo -ne "This script pulls data and metadata from Autorun_eager and creates a poseidon package with the data for the specified individual.\n\n"
  echo -ne "Options:\n"
  echo -ne "-a, --analysis_type\t\tThe analysis type from which the genotypes should be pulled. Individuals in the package will also get a suffix that denotes the analysis type.\n"
  echo -ne "-r, --root_output_directory\t\tOptional. The root directory to place the output packages in. Default: '/mnt/archgen/internal_poseidon_archives/'\n"
  echo -ne "-f, --force\t\tOptional. Force package creation even if no new genotypes are found.\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

function validate_analysis_type() {
  local input
  local valid_analyses
  local result
  local isValid
  valid_analyses=("SG" "TF" "TM" "RP" "RM")
  input=$1
  let isValid=0
  for a in ${valid_analyses[@]}; do
    if [[ ${a} == ${input} ]]; then
      let isValid=1
    fi
  done

  if [[ ${isValid} -eq 1 ]]; then
    echo ${input}
  else
    errecho "USER_ERROR: Invalid analysis type provided: ${input}"
    errecho "Valid analyses: ${valid_analyses[@]}"
    exit 1
  fi
}

## Parse CLI args.
TEMP=`getopt -q -o hfa:r:v --long help,force,analysis_type:,root_output_dir:version -n 'update_poseidon_package.sh' -- "$@"`
eval set -- "$TEMP"

## parameter defaults
force='false'
ind_id=''
contamination_snp_cutoff="100"  ## Provided to fill_in_janno.R
ss_suffix="_ss"                 ## Provided to fill_in_janno.R
geno_ploidy='haploid'           ## Provided to fill_in_janno.R
date_stamp="$(date -I)"
root_output_dir='/mnt/archgen/internal_poseidon_archives' ## Directory that includes data type, site ID and ind ID subdirs.

## Read in CLI arguments
while true ; do
  case "$1" in
    -a|--analysis_type) analysis_type=$(validate_analysis_type $2); shift 2;;
    -f|--force) force='true'; shift ;;
    -r|--root_output_dir) root_output_dir=$2; shift 2;;
    -h|--help) Helptext; exit 0 ;;
    -v|--version) echo ${VERSION}; exit 0;;
    --) ind_id="${2%${ss_suffix}}"; break ;; ## Remove the _ss suffix already if provided.
    *) echo -e "invalid option provided: $1.\n"; Helptext; exit 1;;
  esac
done

## Ensure an analysis type was provided
if [[ -z "${analysis_type}" ]]; then 
  errecho -r "[${0##*/}]: No analysis type was provided.\n"
  Helptext
  exit 1
fi

## Ensure an ind_id was provided, and eager results exist.
if [[ -z ${ind_id} ]]; then
  errecho -r "[${0##*/}]: No individual ID provided.\n"
  Helptext
  exit 1
fi

site_id=`${pandora_helper} -g site_id ${ind_id}` ## Site inferred by pyPandoraHelper

autorun_root_dir='/mnt/archgen/Autorun_eager/'
root_input_dir='/mnt/archgen/Autorun_eager/eager_outputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each site and individual.
input_dir="${root_input_dir}/${analysis_type}/${site_id}/${ind_id}/genotyping/"
output_dir="${root_output_dir}/${analysis_type}/.individuals/${site_id}/"
cred_file="${autorun_root_dir}/.eva_credentials"
trident_path="/r1/people/srv_autoeager/bin/trident-2.1.0.0"

if [[ ! -d ${input_dir} ]]; then
  errecho -r "[${0##*/}]: Expected eager output directory '${input_dir}' does not exist."
  exit 1
fi

## Additional error in case no new genotypes exist (without .txt suffix)
##    If neither genotype file exists throw an error
if [[ ! -f ${input_dir}/pileupcaller.single.geno ]] && [[ ! -f ${input_dir}/pileupcaller.double.geno ]]; then
  errecho -r "[${0##*/}]: No valid genotype files (*.geno) found in output directory."
  errecho "Are the genotypes for this individual from an older Autorun_eager version?"
  exit 1
else
  newest_geno=$(ls -Art -1 ${input_dir}/*geno | tail -n 1) ## Reverse order and tail to avoid broken pipe errors
fi

## Local Testing
# autorun_root_dir='/Users/lamnidis/Software/github/MPI-EVA-Archaeogenetics/Autorun_eager'
# root_input_dir='/Users/lamnidis/mount/eager_outputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each site and individual.
# root_output_dir='/Users/lamnidis/Software/github/MPI-EVA-Archaeogenetics/Autorun_eager/test_data/' ## Directory that includes data type, site ID and ind ID subdirs.
# input_dir="${root_input_dir}/${analysis_type}/${site_id}/${ind_id}/genotyping/"
# output_dir="${root_output_dir}/${analysis_type}/${site_id}/${ind_id}/"
# cred_file="/Users/lamnidis/Software/github/Schiffels-Popgen/MICROSCOPE-processing-pipeline/.credentials"
# trident_path=$(which trident)

## If the genotypes are newer than the output, create a package
## This will evaluate to TRUE when the newest AE geno is newer than the output geno, or when there is no output geno (i.e. no existing package).
if [[ ${newest_geno} -nt ${output_dir}/${ind_id}/${ind_id}.geno ]] || [[ "${force}" == 'true' ]]; then
    TEMPDIR=$(mktemp -d ${autorun_root_dir}/.tmp/v2/${ind_id}_XXXXXXXX)
    errecho -y "[${0##*/}]: Pulling genotypes for ${ind_id}."
    ## make_genotype_dataset_out_of_genotypes <out_name> <tempdir> <output_ind_suffix> <out_population> <geno_fn1> <geno_fn2> ...
    make_genotype_dataset_out_of_genotypes ${ind_id} ${TEMPDIR} .${analysis_type} ${site_id} ${input_dir}/*geno

  errecho -y "## Initial Package Creation ##"
  LOG="${TEMPDIR}/package_creation.log"
  ## Then create new poseidon pacakge in tempdir (so users dont pick up half-made packages.)
  ## The generated .bib file is template and uninformative, with an md5sum of 9edc4a757f785a8ecb59c54d16c5690a.
  ${trident_path} init \
    --snpSet 1240K \
    --genoFile ${TEMPDIR}/${ind_id}.geno \
    --snpFile ${TEMPDIR}/${ind_id}.snp \
    --indFile ${TEMPDIR}/${ind_id}.ind \
    --outPackagePath ${TEMPDIR}/${ind_id} \
    2>&1 | tee -a ${LOG} ## Save stderr/stdout to log file for future reference.

  check_fail $? "[${0##*/}]: Failed to create poseidon initial package. See: ${LOG}"
  errecho -g "## Initial Package Creation completed ##\n"
  ## Flush out bibfile contents (currently it's template bloat from trident init)
  echo -n '' >${TEMPDIR}/${ind_id}/${ind_id}.bib
  ## If a package for this individual already exists, update the packageVersion to match the live version, and copy the CHANGELOG ot the new
  if [[ -f ${output_dir}/${ind_id}/POSEIDON.yml ]]; then
    ## Port over the CHANGELOG
    cp ${output_dir}/${ind_id}/CHANGELOG.md ${TEMPDIR}/${ind_id}/
    ## Update the package version to match the live version.
    old_vn=$(grep 'packageVersion:' ${output_dir}/${ind_id}/POSEIDON.yml | cut -d' ' -f2)
    sed -i "s/packageVersion:.*/packageVersion: ${old_vn}/" ${TEMPDIR}/${ind_id}/POSEIDON.yml
    ## Make Poseidon aware of the CHANGELOG file.
    echo "changelogFile: CHANGELOG.md" >>${TEMPDIR}/${ind_id}/POSEIDON.yml
  fi

  ## Populate the janno file
  LOG="${TEMPDIR}/janno_fill.log"
  errecho -y "## Janno File Fill ##"
  ${autorun_root_dir}/scripts/fill_janno.py \
    -i ${ind_id} \
    -a ${analysis_type} \
    -j ${TEMPDIR}/${ind_id}/${ind_id}.janno \
    -c ${cred_file} \
    -s ${contamination_snp_cutoff} \
    -p ${geno_ploidy} \
    2>&1 | tee -a ${LOG} ## Save stderr/stdout to log file for future reference.

  check_fail $? "[${0##*/}]: Failed to fill janno file information. See: ${LOG}"
  errecho -g "## Janno File Fill completed ##\n"

  ## rectify package and add contributor information
  LOG="${TEMPDIR}/package_update.log"
  errecho -y "## Package Update ##"
  ${trident_path} rectify \
    -d ${TEMPDIR}/${ind_id} \
    --checksumAll \
    --logText "${date_stamp} Package creation" \
    --packageVersion Major \
    --newContributors '[Thiseas C. Lamnidis](thiseas_christos_lamnidis@eva.mpg.de);[Kay Pruefer](kay_pruefer@eva.mpg.de)' \
    2>&1 | tee -a ${LOG} ## Save stderr/stdout to log file for future reference.
  
  check_fail $? "[${0##*/}]: Failed to rectify package. See: ${LOG}"
  errecho -g "## Package Update completed ##\n"

  ## Validate finalised package
  LOG="${TEMPDIR}/package_validation.log"
  errecho -y "## Package Validation ##"
  ${trident_path} validate \
    -d ${TEMPDIR}/${ind_id} \
    2>&1 | tee -a ${LOG} ## Save stderr/stdout to log file for future reference.
  
  check_fail $? "[${0##*/}]: Failed to validate package. See: ${LOG}"
  errecho -g "## Package Validation completed ##\n"

  ## Remove live package, and publish this one
  errecho -y "## Publish Package ##"
  mkdir -p ${output_dir}
  if [[ -d ${output_dir}/${ind_id} ]]; then
    errecho "[${0##*/}]: Removing old package at '${output_dir}/${ind_id}'"
    rm -f ${output_dir}/${ind_id}/*
    rmdir ${output_dir}/${ind_id}
  fi
  errecho "[${0##*/}]: Publishing package to '${output_dir}/${ind_id}'"
  mv ${TEMPDIR}/${ind_id} ${output_dir}/${ind_id}
else
  errecho -y "[${0##*/}]: No new genotypes found for ${ind_id}. No package update needed."
fi

## TODO: Fix version file setup. 
## TODO: Create actual package.
## TODO: Finish creating and validating package
## TODO: Use poseidon doi Crossref query to fill BibTex entries for packages?
