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

## Helper function to pull minotaur versions from Config Profile Description and add them to a file.
## usage add_versions_file <eager_result_dir> <version_fn> <package_name> <packaged_version> <fill_janno_path> <trident_path>
## Will create a file with the following information:
##   nf-core/eager version
##   fill_in_janno.R version
##   trident version
  function add_versions_file() {
  local eager_result_dir
  local version_fn
  local pipeline_report_fn
  local eager_version
  local fill_in_janno_version
  local trident_version
  local fill_janno_path
  local trident_path

  ## Read in function params
  eager_result_dir=${1}
  version_fn=${2}
  package_name=${3}
  packager_version=${4}
  fill_janno_path=${5}
  trident_path=${6}
  
  pipeline_report_fn=${eager_result_dir}/pipeline_info/pipeline_report.txt ## The pipeline report file from nf-core/eager
  eager_version=$(grep "Pipeline Release:" ${pipeline_report_fn} | awk -F ":" '{print $NF}')
  fill_in_janno_version=$(/mnt/archgen/Autorun_eager/scripts/run_Rscript_containerised.sh ${fill_janno_path} -v)
  trident_version=$(${trident_path} --version 2>/dev/null)

  echo eager_result_dir $eager_result_dir
  echo version_fn $version_fn
  echo pipeline_report_fn $pipeline_report_fn
  echo eager_version $eager_version
  echo fill_in_janno_version $fill_in_janno_version
  echo trident_version $trident_version
  echo fill_janno_path $fill_janno_path
  echo trident_path $trident_path

  errecho -y "[${package_name}]: Writing version info to '${version_fn}'."
  ## Create the versions file. Flush any old file contents if the file exists.
  echo "# ${package_name}"                                        > ${version_fn}
  echo "This package was created on $(date -I) and was processed using the following versions:" >> ${version_fn}
  echo " - nf-core/eager version: ${eager_version}"               >> ${version_fn}
  echo " - Poseidon-packager version: ${packager_version}"        >> ${version_fn}
  echo " - fill_in_janno.R version: ${fill_in_janno_version}"     >> ${version_fn}
  echo " - trident creation version: ${trident_version}"          >> ${version_fn}
}

