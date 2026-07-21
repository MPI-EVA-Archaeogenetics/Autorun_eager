#!/usr/bin/env bash

## Bash strict mode (no -e given, since I want to use check_fail to provide informative error info manually):
set -uo pipefail

VERSION="0.0.0"
source /mnt/archgen/Autorun_eager/scripts/helper_functions.sh

# ## Helptext function
# function Helptext() {
#   echo -ne "\t usage: $0 [options] <ind_id>\n\n"
#   echo -ne "This script pulls data and metadata from Autorun_eager and creates a poseidon package with the data for the specified individual.\n\n"
#   echo -ne "Options:\n"
#   echo -ne "-a, --analysis_type\t\tThe analysis type from which the genotypes should be pulled. Individuals in the package will also get a suffix that denotes the analysis type.\n"
#   echo -ne "-r, --root_output_directory\t\tOptional. The root directory to place the output packages in. Default: '/mnt/archgen/internal_poseidon_archives/'\n"
#   echo -ne "-f, --force\t\tOptional. Force package creation even if no new genotypes are found.\n"
#   echo -ne "-k, --keep_logs\t\tOptional. Keep the log files generated during package creation. By default these are deleted on successful completion.\n"
#   echo -ne "-h, --help\t\tPrint this text and exit.\n"
#   echo -ne "-v, --version \t\tPrint version and exit.\n"
# }

root_poseidon_dir="/mnt/archgen/internal_poseidon_archives"
date_stamp="$(date -I)"
trident_path="/r1/people/srv_autoeager/bin/trident-2.1.0.0"
output_fn="/mnt/archgen/Autorun_eager/.tmp/sites/joblists/${date_stamp}_site_package_update_list.txt"
echo '' > ${output_fn}

for a in ${root_poseidon_dir}/*; do
  analysis_type=$(basename $a)
  for s in ${root_poseidon_dir}/${analysis_type}/.individuals/*; do
    site=$(basename $s)
    output_site_yml="${root_poseidon_dir}/${analysis_type}/${site}/POSEIDON.yml"
    newest_geno=$(ls -Art -1 ${s}/*/*geno | tail -n 1) ## Reverse order and tail to avoid broken pipe errors
    
    if [[ ${newest_geno} -nt ${output_site_yml} ]]; then
      echo "/mnt/archgen/Autorun_eager/scripts/update_site_packages.sh -a ${analysis_type} ${site}" >> ${output_fn}
    else
      errecho -g "No newer genotypes found for site ${site} in analysis type ${analysis_type}. Skipping package update."
    fi
  done
done

echo "sbatch --mem=4GB -p short --cpus-per-task=1 --job-name=site_spawner_$(basename ${output_fn}) --output=/mnt/archgen/Autorun_eager/.tmp/sites/$(basename ${output_fn})/%x.po%A.%a --array 1-${jn} /mnt/archgen/Autorun_eager/scripts/submit_as_array.sh ${output_fn}"
sbatch --mem=4GB -p short --cpus-per-task=1 --job-name=site_spawner_$(basename ${output_fn}) --output=/mnt/archgen/Autorun_eager/.tmp/sites/$(basename ${output_fn})/%x.po%A.%a --array 1-${jn} /mnt/archgen/Autorun_eager/scripts/submit_as_array.sh ${output_fn}
