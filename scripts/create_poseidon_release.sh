#!/usr/bin/env bash

VERSION="1.0.0"

## Colours for printing to terminal
Yellow=$(tput sgr0)'\033[1;33m' ## Yellow normal face
Red=$(tput sgr0)'\033[1;31m' ## Red normal face
Normal=$(tput sgr0)

## Helptext function
function Helptext() {
  echo -ne "\t usage: $0 [options] <release_name>\n\n"
  echo -ne "This creates a dated release of all poseidon packages.\n\n"
  echo -ne "Options:\n"
  echo -ne "-h, --help\t\tPrint this text and exit.\n"
  echo -ne "-v, --version \t\tPrint version and exit.\n"
}

## Print messages to stderr
function errecho() { echo -e $* 1>&2 ;}


## Parse CLI args.
TEMP=`getopt -q -o hv --long help,version -n 'create_poseidon_release.sh' -- "$@"`  
eval set -- "$TEMP"

## parameter defaults
trident_path="/r1/people/srv_autoeager/bin/trident-1.5.7.0"
## In the future, maybe multiple releases, for each data type?
poseidon_pacakges="/mnt/archgen/Autorun_eager/poseidon_packages/TF/Sites/"
release_dir="/mnt/archgen/Autorun_eager/poseidon_packages/releases/"

## Read in CLI arguments
while true ; do
  case "$1" in
    -h|--help) Helptext; exit 0 ;;
    -v|--version) echo ${VERSION}; exit 0;;
    --) release_name="${2}"; break ;;
    *) echo -e "invalid option provided: $1.\n"; Helptext; exit 1;;
  esac
done

## All poseidon packages have the population name "Unknown". This can be used to make a mega release easily.
##   Once the large dataset is created, the population name can be changed to the site name.
## TODO: a) Submit to scheduler, b) First forge each site, then forge across sites. That limits open file handles and speeds things up considerably.
CMD="${trident_path} forge \
  -d ${poseidon_pacakges} \
  --forgeString Unknown \
  --outFormat EIGENSTRAT \
  --outPackagePath ${release_dir}/${release_name} \
  --outPackageName ${release_name} \
  --logMode SimpleLog"

errecho "${CMD}" | tr -s ' '
${CMD} 2>&1 > ${release_dir}/${release_name}.creation_log

if [[ $? -ne 0 ]]; then
  errecho "${Red}Error${Normal}: Trident failed to create the release. Check the log file for more information."
  exit 1
fi

## Update Group_Name column in ind file
awk -F "\t" -v OFS="\t" '{if ($1 ~ /_ss$/) {$3 = substr($1, 1,length($1)-6)} else {$3 = substr($1, 1,length($1)-3)}; print $0}' ${release_dir}/${release_name}.ind > ${release_dir}/${release_name}.ind.tmp
mv ${release_dir}/${release_name}.ind ${release_dir}/.${release_name}.ind.original
mv ${release_dir}/${release_name}.ind.tmp ${release_dir}/${release_name}.ind

## Update Group_Name column in janno file
##    janno has  aheader line, so add NR==1; NR > 1 to only apply the transformation after the first line.
awk -F "\t" -v OFS="\t" 'NR==1; NR > 1{if ($1 ~ /_ss$/) {$3 = substr($1, 1,length($1)-6)} else {$3 = substr($1, 1,length($1)-3)}; print $0}' ${release_dir}/${release_name}.janno > ${release_dir}/${release_name}.janno.tmp
mv ${release_dir}/${release_name}.janno ${release_dir}/.${release_name}.janno.original
mv ${release_dir}/${release_name}.janno.tmp ${release_dir}/${release_name}.janno

## Rectify the package to add checksums
CMD="${trident_path} rectify \
  -d ${release_dir}/${release_name} \
  --packageVersion Minor \
  --logText 'Added checksums to package' \
  --checksumAll"

errecho "${CMD}" | tr -s ' '
${CMD}