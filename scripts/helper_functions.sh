## This file contains helper functions that for other scripts to use, to avoid code duplication.
## 2026-06-30 
## Thiseas C. Lamnidis

## Print coloured messages to stderr
#   errecho -r will print in red
#   errecho -y will print in yellow
#   errecho -g will print in green
function errecho() {
  local Normal
  local Red
  local Yellow
  local Green
  local colour
  local echo_options
  local TEMP
  TEMP=`getopt -q -o nryg -n 'errecho' -- "$@"`
  eval set -- "$TEMP"


  Normal=$(tput sgr0)
  Red=$(tput sgr0)'\033[1;31m' ## Red normal face
  Yellow=$(tput sgr0)'\033[1;33m' ## Yellow normal face
  Green=$(tput sgr0)'\033[1;32m' ## Green normal face
  options=""
  colour=''
  echo_options=''

  while true; do
    case $1 in
      -y) colour="${Yellow}" ; shift 1 ;;
      -r) colour="${Red}" ; shift 1 ;;
      -g) colour="${Green}" ; shift 1 ;;
      -n) echo_options+="-n"; shift 1 ;;
      --) shift 1; break;;
    esac
  done
  
  echo ${echo_options} -e ${colour}$*${Normal} 1>&2
}

## Function to validate input analysis types as valid for poseidon package creation. If valid, returns the input. If invalid, prints an error and exits.
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

## Function to check failure and stop execution
function check_fail() {
  if [[ ${1} != 0 ]]; then 
    errecho -r "${2}"
    exit ${1}
  fi
}

## A function to make a genotype dataset for the output package out of an array of genotype files.
## Usage make_genotype_dataset_out_of_genotypes <out_name> <tempdir> <output_ind_suffix> <out_population> <geno_fn1> <geno_fn2> ...
##   out_name:  The name of the output genotype dataset.
##   tempdir:   The temporary directory to use for mixing the genotypes.
##   output_ind_suffix: An optional suffix to add to individual IDs in the resulting genotype data. use '' to not add one.
##   out_population: The desired Group_Name to be set in the ind file. If an empty string is specified, it is set to "Unknown".
##   geno_fn*:  The genotype files to merge together. The format is inferred from the suffix.
## Note: Adapted from poseidon-eager. Assumes that the input files are on the exact same SNP set, and that the order between datasets is consistent.
function make_genotype_dataset_out_of_genotypes() {
  local format
  local tempdir
  local out_name
  local input_fns
  local input_fn
  local base_fn
  local ind_fns
  local geno_top_length
  local geno_bot_length
  local normalized_input_fn
  local input_suffix
  local inferred_suffix
  local output_ind_suffix
  local out_population

  out_name=${1}
  tempdir=${2}
  output_ind_suffix=${3}
  out_population=${4}
  shift 4
  input_fns=("${@}")
  inferred_suffix=''

  ## Gzipped inputs are not supported yet. Throw error.
  for input_fn in ${input_fns[@]}; do
    if [[ ${input_fn} == *.gz ]]; then
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Gzipped genotype inputs are not supported: '${input_fn}'."
      exit 1
    fi
  done

  ## Ensure the provided temp dir exists
  if [[ ! -d ${tempdir} ]]; then
    errecho -r "[make_genotype_dataset_out_of_genotypes()]: Temporary directory '${tempdir}' not found."
    exit 1
  fi

  ## Check that the genotype files exist.
  for input_fn in ${input_fns[@]}; do
    if [[ ! -f ${input_fn} ]]; then
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Genotype file '${input_fn}' not found."
      exit 1
    fi

    normalized_input_fn=${input_fn%.gz}
    input_suffix=.${normalized_input_fn##*.}
    if [[ -z ${inferred_suffix} ]]; then
      inferred_suffix=${input_suffix}
    elif [[ ${input_suffix} != ${inferred_suffix} ]]; then
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Input genotype files have inconsistent suffixes. Expected '${inferred_suffix}' but found '${input_suffix}' for '${input_fn}'."
      exit 1
    fi
  done

  ## If outPop is '', then use 'Unknown' instead.
  if [[ -z $out_population ]]; then
    out_population='Unknown'
  fi

  case ${inferred_suffix} in
    .geno)
      format="EIGENSTRAT"
      ;;
    .bed)
      format="PLINK"
      ;;
    .vcf)
      format="VCF"
      ;;
    *)
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Could not infer genotype format from suffix '${inferred_suffix}'. Supported suffixes are '.geno[.gz]', '.bed[.gz]', and '.vcf[.gz]'."
      exit 1
      ;;
  esac

  ## Merge eigenstrat genotypes
  if [[ ${format} == "EIGENSTRAT" ]]; then
    ## Paste genos together. If only one is there, then it's simply a copy of it
    paste -d '\0' ${input_fns[@]} > ${tempdir}/${out_name}.geno

    ## Copy the snp file
    cp ${input_fns[0]%.geno}.snp ${tempdir}/${out_name}.snp

    ## And cat the ind files (this needs a bit of variable expansion to work)
    ind_fns=''
    for base_fn in ${input_fns[@]%.geno}; do
      ind_fns+="${base_fn}.ind "
    done
    ## Also add output_ind_suffix to individual IDs. Set input and output field sep to TAB.
    cat ${ind_fns} | awk -v suffix=${output_ind_suffix} -v outPop=${out_population} 'BEGIN {OFS=FS="\t"}; {$1=$1suffix; $3=outPop; print $0}' > ${tempdir}/${out_name}.ind

    ## Final sanity check, that the file dimensions are correct.
    if [[ $(wc -l ${tempdir}/${out_name}.geno | cut -f 1 -d ' ') != $(wc -l ${tempdir}/${out_name}.snp | cut -f 1 -d ' ') ]]; then
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Genotype file '${out_name}.geno' has a different number of lines than the snp file."
      exit 1
    fi

    ## Check that the genotype dataset has a consistent length across first and last snp.
    geno_top_length=$(bc <<< "$(head -n1 ${tempdir}/${out_name}.geno | wc -c | cut -f 1 -d ' ') - 1")
    geno_bot_length=$(bc <<< "$(tail -n1 ${tempdir}/${out_name}.geno | wc -c | cut -f 1 -d ' ') - 1")
    if [[ ${geno_top_length} != ${geno_bot_length} ]]; then
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Genotype file '${out_name}.geno' has inconsistent line lengths. Check the input datasets and try again."
      exit 1
    fi

    ## The number of characters (excluding the new line character) in the last row of the genotype file should match than the number of individuals.
    if [[ ${geno_bot_length} != $(wc -l ${tempdir}/${out_name}.ind | cut -f 1 -d ' ') ]]; then
      errecho -r "[make_genotype_dataset_out_of_genotypes()]: Genotype file '${out_name}.geno' has a different number of lines than the ind file."
      exit 1
    fi
    errecho -g "[make_genotype_dataset_out_of_genotypes()]: Successfully created genotype dataset '${out_name}.{geno,snp,ind}'.\n"

  ## Merge plink genotypes
  elif [[ ${format} == 'PLINK' ]]; then
    errecho -r "[make_genotype_dataset_out_of_genotypes()]: PLINK genotype merging not yet implemented."
    exit 1
  elif [[ ${format} == 'VCF' ]]; then
    errecho -r "[make_genotype_dataset_out_of_genotypes()]: VCF genotype merging not yet implemented."
    exit 1
  fi
}
