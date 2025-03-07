#!/usr/bin/env bash

date=$(date +'%y%m%d_%H%M')

cd /mnt/archgen/Autorun_eager/

if [[ ! -d stats/${date} ]]; then
	mkdir stats/${date}/
fi

find /mnt/archgen/Autorun_eager/eager_outputs -maxdepth 4 -mindepth 4 -path '*/*/*/multiqc' -type d | rev | cut -d "/" -f 2 | rev > stats/${date}/all_processed_inds_${date}.tsv

sort -u stats/${date}/all_processed_inds_${date}.tsv > stats/${date}/all_processed_inds_${date}_unique.txt

(for a in `ls eager_outputs/`; do echo -n "${a} individuals processed: "; find /mnt/archgen/Autorun_eager/eager_outputs/${a} -maxdepth 4 -mindepth 4 -path '*/*/*/multiqc/multiqc_report.html' -type f  | wc -l ; done ; echo "Date: ${date}") > stats/${date}/n_processed_inds_${date}.txt
