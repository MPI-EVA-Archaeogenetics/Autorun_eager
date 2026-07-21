#!/usr/bin/env bash

## Bash strict mode (no -e given, since I want to use check_fail to provide informative error info manually):
set -uo pipefail

VERSION="0.0.0"
source /mnt/archgen/Autorun_eager/scripts/helper_functions.sh

# ## Helptext function
function Helptext() {
  echo -ne "\t usage: $0 [options] -a <analysis_type> <site_id>\n\n"
  echo -ne "This script pulls data and metadata from Autorun_eager and creates a poseidon package with the data for the specified individual.\n\n"
  echo -ne "Options:\n"
  echo -ne "-a, --analysis_type\t\tThe analysis type from which the genotypes should be pulled. Individuals in the package will also get a suffix that denotes the analysis type. Defaults to SG.\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

root_poseidon_dir="/mnt/archgen/internal_poseidon_archives"
trident_path="/r1/people/srv_autoeager/bin/trident-2.1.0.0"
analysis_type="SG"
site=""
autorun_root_dir='/mnt/archgen/Autorun_eager/'

## Parse CLI args.
TEMP=`getopt -q -o ha:v --long help,analysis_type:,version -n "$0" -- "$@"`
eval set -- "$TEMP"

while true ; do
  case "$1" in
    -a|--analysis_type) analysis_type=$(validate_analysis_type $2); shift 2;;
    -h|--help) Helptext; exit 0 ;;
    -v|--version) echo ${VERSION}; exit 0;;
    --) site="${2}"; break ;; ## Remove the _ss suffix already if provided.
    *) echo -e "invalid option provided: $1.\n"; Helptext; exit 1;;
  esac
done

if [[ -z "$site" && $# -gt 0 ]]; then
  site="$1"
  shift
fi

if [[ -z "$site" ]]; then
  echo "ERROR: Missing required argument <site_id>" >&2
  Helptext
  exit 1
fi

case "$analysis_type" in
  SG|TF|TM|RP|RM)
    ;;
  *)
    echo "ERROR: Unsupported analysis type: $analysis_type" >&2
    Helptext
    exit 1
    ;;
esac

## Forge the package in a temp dir
TEMPDIR=$(mktemp -d ${autorun_root_dir}/.tmp/sites/${site}_${analysis_type}_XXXXXXXX)
output_dir="${root_poseidon_dir}/${analysis_type}/${site}"

errecho -y "## Forge Package ##"
${trident_path} forge \
  -d ${root_poseidon_dir}/${analysis_type}/.individuals.nobackup/${site} \
  -o ${TEMPDIR}/${site} \
  --outFormat EIGENSTRAT

check_fail $? "Trident forge command failed for site ${site} in analysis type ${analysis_type}."
errecho -g "## Package Forge completed ##\n"

errecho -y "## Rectify Package ##"
${trident_path} rectify \
  -d ${TEMPDIR}/${site} \
  --checksumAll \
  --logText "$(date -I) Package creation" \
  --packageVersion Major \
  --newContributors '[Thiseas C. Lamnidis](thiseas_christos_lamnidis@eva.mpg.de);[Kay Pruefer](kay_pruefer@eva.mpg.de)' \

check_fail $? "Trident rectify command failed for site ${site} in analysis type ${analysis_type}."
errecho -g "## Package Rectify completed ##\n"

## Remove live package, and publish this one
errecho -y "## Publish Package ##"
mkdir -p ${output_dir}
if [[ -d ${output_dir}/ ]]; then
  errecho "[${0##*/}]: Removing old package at '${output_dir}/'"
  rm -f ${output_dir}/*
  rmdir ${output_dir}/
fi
errecho "[${0##*/}]: Publishing package to '${output_dir}'"
mv ${TEMPDIR}/${site} ${output_dir}
check_fail $? "[${0##*/}]: Failed to publish package to '${output_dir}'"
errecho -g "## Package Publish completed ##\n"
errecho "[${0##*/}]: Removing temporary directory '${TEMPDIR}'"
rm -rf ${TEMPDIR}
