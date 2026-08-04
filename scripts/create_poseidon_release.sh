#!/usr/bin/env bash

## Bash strict mode (no -e given, since I want to use check_fail to provide informative error info manually):
set -uo pipefail

VERSION="2.0.0"

## Dependency
source /mnt/archgen/Autorun_eager/scripts/helper_functions.sh

## Helptext function
function Helptext() {
  echo -ne "\t usage: $0 [options] <release_name>\n\n"
  echo -ne "This creates a dated release of all poseidon packages in each analysis type.\n\n"
  echo -ne "Options:\n"
  echo -ne "-d, --packageDate\t\tOptional.The ISO formatted date the letter packages were created. Assumed to be today if not provided."
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

## Parse CLI args.
TEMP=`getopt -q -o dhv --long packageDate,help,version -n 'create_poseidon_releases.sh' -- "$@"`  
eval set -- "$TEMP"

## parameter defaults
trident_path="/r1/people/srv_autoeager/bin/trident-2.1.0.0"
scratch_dir='/mnt/archgen/scratch/srv_autoeager/.releases'
root_poseidon_dir="/mnt/archgen/internal_poseidon_archives"
release_dir="${root_poseidon_dir}/releases/"
date_stamp="$(date -I)"
input_date="${date_stamp}"
dependency=''

## Read in CLI arguments
while true ; do
  case "$1" in
    -h|--help) Helptext; exit 0 ;;
    -v|--version) echo ${VERSION}; exit 0;;
    -d|--packageDate) input_date="$2"; shift 2;;
    --) break ;;
    *) echo -e "invalid option provided: $1.\n"; Helptext; exit 1;;
  esac
done

joblist_fn="${scratch_dir}/.joblists/${date_stamp}_release.joblist"
echo -n '' > ${joblist_fn} ##Flush out list if it exists.

for a in SG TF TM RP RM; do
  TEMPDIR=$(mktemp -d ${scratch_dir}/${date_stamp}/release)
  LOG=${TEMPDIR}/forge.log
  ${trident_path} --logMode SimpleLog 
    forge \
    --outFormat EIGENSTRAT \
    -d ${scratch_dir}/${input_date} \
    -o ${TEMPDIR}/${a} \
    2>&1 | tee -a ${LOG} ## Save stderr/stdout to log file for future reference.
  
  check_fail "Package Forge failed for package in: ${TEMPDIR}/${a}"
  errecho -g "## Package Forge completed ##\n"

  if [[ -f ${release_dir}/${a}/POSEIDON.yml ]]; then
    ## If a release already exists, update it.
    cp ${release_dir}/${a}/POSEIDON.yml ${TEMPDIR}/${a}/
  fi
  LOG=${TEMPDIR}/rectify.log
  ${trident_path} --logMode SimpleLog rectify \
    --checksumAll \
    -d ${TEMPDIR}/${a} \
    --logText "${a} release: ${date_stamp}" \
    --packageVersion Major \
    2>&1 | tee -a ${LOG} ## Save stderr/stdout to log file for future reference.

  check_fail $? "Trident rectify command failed for package in: ${TEMPDIR}/${a}."
  errecho -g "## Package Rectify completed ##\n"

  LOG=${TEMPDIR}/validate.log
  ${trident_path} --logMode SimpleLog validate \
    -d ${TEMPDIR}/${a} \
    2>&1 | tee -a ${LOG} ## Save stderr/stdout to log file for future reference.
  
  check_fail $? "Trident validation command failed for package in: ${TEMPDIR}/${a}."
  errecho -g "## Package validation completed ##\n"

  ## Move release to live directory
  mkdir -p ${release_dir}
  if [[ -d ${release_dir}/${a} ]]; then
    errecho "[${0##*/}]: Removing old package at '${release_dir}/${a}/'"
    rm -f ${release_dir}/${a}/*
    rmdir ${release_dir}/${a}/
  fi
  errecho "[${0##*/}]: Publishing package to '${release_dir}/${a}'"
  mv ${TEMPDIR}/${a} ${release_dir}/${a}
  check_fail $? "[${0##*/}]: Failed to publish package to '${release_dir}/${a}'"
  errecho -g "## Package Publish completed ##\n"
  errecho "[${0##*/}]: Removing temporary directory '${TEMPDIR}'"
  rm -rf ${TEMPDIR}
done
