#!/usr/bin/env bash


## This script removes the results for an individual while maintaining the nextflow process cache for them.
##    It is intended as a way to refresh the results directories of an individual. This can be useful either
##    to remove older files after additional libraries appear and are therefore merged, or to remove results
##    with misleading names in cases where Pandora entries get updated (e.g. protocol mixup leading to changes
##    in strandedness for a library).

## DEPENDENCY
pandora_helper="/mnt/archgen/tools/helper_scripts/py_helpers/pyPandoraHelper/pyPandoraHelper.py"

valid_analysis_types=("TF" "SG" "RP" "RM" "IM" "YC")

## Join array elements by separator given as $1
function join_array_elements() {
  local IFS="$1"
  shift
  echo "$*"
}

## Helptext function
function Helptext() {
  errecho "\t usage: $0 [options] <ind_id_list>\n"
  errecho "This script removes all output directory contents for the provided individuals, without clearing out caching, allowing for the results to be re-published.\n    This enables refreshing of result directories when changes to the input might have changes merging of libraries, thus making the directory structure inconsistent.\n"
  errecho "Options:"
  errecho "-h, --help\t\tPrint this text and exit."
  errecho "-a, --analysis_type\t\tSet the analysis type. Options: $(join_array_elements , ${valid_analysis_types[@]})."
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
  else
    colour="${Normal}"
  fi
  echo -e ${colour}$*${Normal} 1>&2
}

## Parse CLI args.
TEMP=`getopt -q -o ha: --long analysis_type:,help -n 'clear_results.sh' -- "$@"`
eval set -- "$TEMP"

## Default parameters
ind_id_list_fn=''
analysis_type=''

## Read in CLI arguments
while true ; do
  case "$1" in
    -h|--help) Helptext; exit 0 ;;
    -a|--analysis_type) analysis_type="${2}"; shift 2;;
    --) ind_id_list_fn="${2}"; break ;;
    *) echo -e "invalid option provided: $1.\n"; Helptext; exit 1;;
  esac
done

## Validate inputs
if [[ ${ind_id_list_fn} == '' ]]; then
  errecho "No individual ID list provided.\n"
  Helptext
  exit 1
fi

if [[ ${analysis_type} == '' ]]; then
  errecho "No --analysis_type was provided.\n"
  Helptext
  exit 2
elif [[ ! " ${valid_analysis_types[*]} " =~ " ${analysis_type} " ]]; then
  errecho "analysis_type must be one of: $(join_array_elements , ${valid_analysis_types[@]}). You provided: ${analysis_type}\n"
  Helptext
  exit 2
fi

root_eager_dir='/mnt/archgen/Autorun_eager/eager_outputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each site and individual.

## Read all individual IDs into an array
input_iids=($(cat ${ind_id_list_fn}))

## Remove all dirs except for 'work' and 'pipeline_info'. 
##    Both needed for caching. 
##    Also leave '1240k.imputed' and 'GTL_output' alone.
for ind_id in ${input_iids[@]}; do
  site_id=`${pandora_helper} -g site_id ${ind_id}` ## Site inferred by pyPandoraHelper
  dirs_to_delete=$(ls -1 -d ${root_eager_dir}/${analysis_type}/${site_id}/${ind_id}/* | grep -vw -e 'work' -e '1240k.imputed' -e 'GTL_output' -e 'pipeline_info')
  for dir in ${dirs_to_delete}; do
    errecho "Deleting results in: ${dir}"
    rm -r ${dir} ## Delete the specific result directory and all its contents
  done
done
