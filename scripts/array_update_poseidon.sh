#!/usr/bin/env bash
analysis_type=$1
ind_list_fn=$2

## Bash strict mode (no -e given, since I want to use check_fail to provide informative error info manually):
set -uo pipefail


if [[ ${analysis_type} = '' ]]; then
    echo "No analysis type provided."
    echo "Usage: ${0##*/} <analysis_type> <ind_list_fn>"
    exit 0
fi

if [[ ${ind_list_fn} = '' ]]; then
    echo "No individual list file provided."
    echo "Usage: ${0##*/} <analysis_type> <ind_list_fn>"
    exit 0
fi
output_fn="${ind_list_fn##*/}.${analysis_type}.joblist"
echo '' > ${output_fn}

while read r; do
    echo "/mnt/archgen/Autorun_eager/scripts/update_poseidon_package_v2.sh -a ${analysis_type} ${r}" >> ${output_fn}
done < ${ind_list_fn}

jn=$(wc -l ${output_fn} | cut -f 1 -d " ") ## number of jobs equals number of lines
echo "sbatch --mem=4GB -p short --cpus-per-task=1 --job-name=poseidon_spawner_${output_fn} --output=/mnt/archgen/Autorun_eager/.tmp/$(basename ${output_fn})/%x.po%A.%a --array 1-${jn} /mnt/archgen/Autorun_eager/scripts/submit_as_array.sh ${output_fn}"
sbatch --mem=4GB -p short --cpus-per-task=1 --job-name=poseidon_spawner_${output_fn} --output=/mnt/archgen/Autorun_eager/.tmp/$(basename ${output_fn})/%x.po%A.%a --array 1-${jn} /mnt/archgen/Autorun_eager/scripts/submit_as_array.sh ${output_fn}
