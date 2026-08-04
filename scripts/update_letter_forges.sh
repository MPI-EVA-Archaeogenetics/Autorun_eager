#!/usr/bin/env bash

## Bash strict mode (no -e given, since I want to use check_fail to provide informative error info manually):
set -uo pipefail

VERSION="0.0.1"

## Dependency
source /mnt/archgen/Autorun_eager/scripts/helper_functions.sh

## Helptext function
function Helptext() {
  echo -ne "\t usage: $0 [options] <release_name>\n\n"
  echo -ne "This creates a dated release of all poseidon packages in each analysis type.\n\n"
  echo -ne "Options:\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

## Parse CLI args.
TEMP=`getopt -q -o hv --long help,version -n 'create_poseidon_releases.sh' -- "$@"`  
eval set -- "$TEMP"

## parameter defaults
trident_path="/r1/people/srv_autoeager/bin/trident-2.1.0.0"
scratch_dir='/mnt/archgen/scratch/srv_autoeager/.releases'
root_poseidon_dir="/mnt/archgen/internal_poseidon_archives"
release_dir="${root_poseidon_dir}/releases/"
date_stamp="$(date -I)"

## Read in CLI arguments
while true ; do
  case "$1" in
    -h|--help) Helptext; exit 0 ;;
    -v|--version) echo ${VERSION}; exit 0;;
    --) break ;;
    *) echo -e "invalid option provided: $1.\n"; Helptext; exit 1;;
  esac
done

joblist_fn="${scratch_dir}/.joblists/${date_stamp}_letters.joblist"
echo -n '' > ${joblist_fn} # #Flush out list if it exists.

for a in SG TF TM RP RM; do
  ## First do a forge per first letter of the site, then merge across all sites, so be kinder to the I/O
  for l in {A..Z}; do
    ## Check that sites with that letter exist for the analysis. if not, skip this letter.
    _=$(cd ${root_poseidon_dir}/${a}; ls -d -1 ${l}* 2>/dev/null)
    if [[ ! $? -eq 0 ]]; then errecho -y "Skipping ${a}, ${l}"; continue; fi

    errecho -y "Processing ${a}, ${l}"
    mkdir -p ${scratch_dir}/${date_stamp}
    TEMPDIR=$(mktemp -d ${scratch_dir}/${date_stamp}/${a}_${l}_XXXXXXXX)
    ## cd first to only get relative paths. does not affect PWD since it is a subshell
    $( (cd ${root_poseidon_dir}/${a}; ls -d -1 ${l}* | xargs -I{} echo '*'{}'*') > ${TEMPDIR}/forgelist.txt )
    
    forge_cmd="${trident_path} --logMode SimpleLog \
      forge \
      --outFormat EIGENSTRAT \
      -d ${root_poseidon_dir}/${a} \
      --forgeFile ${TEMPDIR}/forgelist.txt \
      -o ${TEMPDIR}/${date_stamp}_${a}_${l}/"
    echo ${forge_cmd} | tr -s " " >> ${joblist_fn}
  done
done

jn=$(wc -l < ${joblist_fn})
sbatch_cmd="sbatch -t 4:00:00 --mem=4GB -p short --cpus-per-task=1 --job-name=release_letter_forge_$(basename ${joblist_fn}) --output=${scratch_dir}/.logs/$(basename ${joblist_fn})/%x.po%A.%a --array 1-${jn} /mnt/archgen/Autorun_eager/scripts/submit_as_array.sh ${joblist_fn}"
errecho "${sbatch_cmd}"
${sbatch_cmd}
