#!/usr/bin/env bash

## DEPENDENCY
pandora_helper="/mnt/archgen/tools/helper_scripts/py_helpers/pyPandoraHelper/pyPandoraHelper.py"

## Helptext function
function Helptext() {
  echo -ne "\t usage: $0 [options] <sensitive_seqIds_list>\n\n"
  echo -ne "This script pulls the Pandora individual IDs from the list of sensitive sequencing IDs, and\n    removes all Autorun_eager input and outputs from those individuals (if any).\n    This ensures that no results are available even if marking samples as sensitive was done late.\n\n"
  echo -ne "Options:\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
}

## Print messages to stderr, optionally with colours
function errecho() {
  local Normal
  local Red
  local Yellow
  local colour

  Normal=$(tput sgr0)
  Red=$(tput sgr0)'\033[1;31m' ## Red normal face
  Yellow=$(tput sgr0)'\033[1;33m' ## Yellow normal face

  colour=''
  if [[ ${1} == '-y' ]]; then
    colour="${Yellow}"
    shift 1
  elif [[ ${1} == '-r' ]]; then
    colour="${Red}"
    shift 1
  fi
  echo -e ${colour}$*${Normal} 1>&2
}

## Parse CLI args.
TEMP=`getopt -q -o h --long help -n 'ethical_sample_scrub.sh' -- "$@"`
eval set -- "$TEMP"

## Read in CLI arguments
while true ; do
  case "$1" in
    -h|--help) Helptext; exit 0 ;;
    --) sensitive_seq_id_list="${2}"; break ;;
    *) echo -e "invalid option provided: $1.\n"; Helptext; exit 1;;
  esac
done

## Hardcoded paths
root_input_dir='/mnt/archgen/Autorun_eager/eager_inputs'   ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each site and individual.
root_output_dir='/mnt/archgen/Autorun_eager/eager_outputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each site and individual.


if [[ ${sensitive_seq_id_list} = '' ]]; then
    echo -e "No input file provided.\n"
    Helptext
    exit 1
fi

if [[ ! -f ${sensitive_seq_id_list} ]]; then
  echo "File not found: ${sensitive_seq_id_list}"
  exit 1
else
  ## Create list of unique individual IDs from the list of sensitive seq_ids
  scrub_me=($(cut -d '.' -f 1 ${sensitive_seq_id_list} | sort -u ))

  ## If the individuals were flagged as sensitive AFTER processing started, both the inputs and outputs should be made inaccessible.
  for raw_iid in ${scrub_me[@]}; do
    for analysis_type in "SG" "TF" "RP" "RM"; do
      ## EAGER_INPUTS
      site_id=`${pandora_helper} -g site_id ${raw_iid}` ## Site inferred by pyPandoraHelper
      eager_input_tsv="${root_input_dir}/${analysis_type}/${site_id}/${raw_iid}/${raw_iid}.tsv"
      ## If the eager inpput exists, hide the entire directory and make it inaccessible
      if [[ -f ${eager_input_tsv} ]]; then
        old_name=$(dirname ${eager_input_tsv})
        new_name=$(dirname ${old_name})/.${raw_iid}
        mv -v ${old_name} ${new_name} ## Hide the input directory
        chmod 0700 ${new_name}        ## Restrict the directory contents
      fi

      ## EAGER_OUTPUTS
      eager_output_dir="${root_output_dir}/${analysis_type}/${site_id}/${raw_iid}/"
      if [[ -d ${eager_output_dir} ]]; then
        new_outdir_name=$(dirname ${eager_output_dir})/.${raw_iid}
        mv -v ${eager_output_dir} ${new_outdir_name} ## Hide the output directory
        chmod 0700 ${new_outdir_name}                ## Restrict the directory contents
      fi
    done
  done
fi

