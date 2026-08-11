#!/usr/bin/env bash

## Bash strict mode (no -e given, since I want to use check_fail to provide informative error info manually):
set -uo pipefail

VERSION="2.0.0"

## Dependency
source /mnt/archgen/Autorun_eager/scripts/helper_functions.sh

## Helptext function
function Helptext() {
  echo -ne "\t usage: $0 [options]\n\n"
  echo -ne "This creates a dated snapshot of all poseidon packages in the requested analysis type.\n\n"
  echo -ne "Options:\n"
  echo -ne "-a, --analysis_type\tThe analysis type for which a snapshot should be prepared.\n"
  echo -ne "-d, --packageDate\tOptional.The ISO formatted date the letter packages were created. Assumed to be today if not provided.\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

## Parse CLI args.
TEMP=`getopt -q -o a:d:hv --long analysis_type:,packageDate:,help,version -n "$0" -- "$@"`
eval set -- "$TEMP"

## parameter defaults
trident_path="/r1/people/srv_autoeager/bin/trident-2.1.0.0"
scratch_dir='/mnt/archgen/scratch/srv_autoeager/.snapshots'
root_poseidon_dir="/mnt/archgen/internal_poseidon_archives"
snapshot_dir="${root_poseidon_dir}/snapshots/"
date_stamp="$(date -I)"
input_date="${date_stamp}"
analysis=''

## Read in CLI arguments
while true ; do
  case "$1" in
    -h|--help) Helptext; exit 0 ;;
    -v|--version) echo ${VERSION}; exit 0;;
    -d|--packageDate) input_date="$2"; shift 2;;
    -a|--analysis_type) analysis="$2"; shift 2;;
    --) break ;;
    *) echo -e "invalid option provided: $1.\n"; Helptext; exit 1;;
  esac
done

if [[ -z "${analysis}" ]]; then
  errecho "No analysis type was provided. Valid analyses: SG TF TM RP RM."
  exit 1
fi
## From helper_functions.sh
validate_analysis_type ${analysis}

errecho -y "## Forge Snapshot ##\n"
mkdir -p ${scratch_dir}/${date_stamp}/
TEMPDIR=$(mktemp -d ${scratch_dir}/${date_stamp}/snapshot_${analysis}_XXXX)
LOG=${TEMPDIR}/forge.log
${trident_path} --logMode SimpleLog forge \
  --outFormat EIGENSTRAT \
  -d ${scratch_dir}/${input_date}/${analysis} \
  -o ${TEMPDIR}/${analysis} \
  -n ${analysis}_snapshot_eva_internal \
  2>&1 | tee -a ${LOG} ## Save stderr/stdout to log file for future reference.

check_fail $? "Package Forge failed for package in: ${TEMPDIR}/${analysis}"
errecho -g "## Package Forge completed ##\n"

if [[ -f ${snapshot_dir}/${analysis}/POSEIDON.yml ]]; then
  errecho -y "## Copying Existing YAML for package ##\n"
  ## If a snapshot already exists, update it.
  cp ${snapshot_dir}/${analysis}/POSEIDON.yml ${TEMPDIR}/${analysis}/
fi
errecho -y "## Rectify Snapshot ##\n"
LOG=${TEMPDIR}/rectify.log
${trident_path} --logMode SimpleLog rectify \
  --checksumAll \
  -d ${TEMPDIR}/${analysis} \
  --logText "${analysis} snapshot: ${date_stamp}" \
  --packageVersion Major \
  --newContributors '[Thiseas C. Lamnidis](thiseas_christos_lamnidis@eva.mpg.de);[Kay Pruefer](kay_pruefer@eva.mpg.de)' \
  2>&1 | tee -a ${LOG} ## Save stderr/stdout to log file for future reference.

check_fail $? "Trident rectify command failed for package in: ${TEMPDIR}/${analysis}."
errecho -g "## Package Rectify completed ##\n"

errecho -y "## Validate Snapshot ##\n"
LOG=${TEMPDIR}/validate.log
${trident_path} --logMode SimpleLog validate \
  -d ${TEMPDIR}/${analysis} \
  2>&1 | tee -a ${LOG} ## Save stderr/stdout to log file for future reference.

check_fail $? "Trident validation command failed for package in: ${TEMPDIR}/${analysis}."
errecho -g "## Package validation completed ##\n"

## Move snapshot to live directory
mkdir -p ${snapshot_dir}
if [[ -d ${snapshot_dir}/${analysis} ]]; then
  errecho "[${0##*/}]: Removing old package at '${snapshot_dir}/${analysis}/'"
  rm -f ${snapshot_dir}/${analysis}/*
  rmdir ${snapshot_dir}/${analysis}/
fi
errecho "[${0##*/}]: Publishing package to '${snapshot_dir}/${analysis}'"
mv ${TEMPDIR}/${analysis} ${snapshot_dir}/${analysis}
check_fail $? "[${0##*/}]: Failed to publish package to '${snapshot_dir}/${analysis}'"
errecho -g "## Package Publish completed ##\n"
errecho "[${0##*/}]: Removing temporary directory '${TEMPDIR}'"
rm -rf ${TEMPDIR}
