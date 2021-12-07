#!/usr/bin/env bash

eager_version='2.4.1'
autorun_config='/mnt/archgen/users/lamnidis/popgen_autoprocess/Autorun.config' ## Contains specific profiles with params for each analysis type.
root_input_dir='/mnt/archgen/users/lamnidis/popgen_autoprocess/eager_inputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each individual.
####        E.g. /mnt/archgen/users/lamnidis/popgen_autoprocess/eager_inputs/SG/GUB001/GUB001.tsv
root_output_dir='/mnt/archgen/users/lamnidis/popgen_autoprocess/eager_outputs'

## Set base profiles for EVA cluster.
nextflow_profiles="eva,archgen,medium_data,autorun"

## Set colour and face for colour printing
Red='\033[1;31m'$(tput bold) ## Red bold face
Yellow=$(tput sgr0)'\033[1;33m' ## Yellow normal face

## Since I'm running through all data every time, the runtime of the script will increase marginally over time. 
## Maybe create a list of eager inputs that are newer than the MQC reports and use that to loop over?
for analysis_type in "SG" "TF"; do
    # echo ${analysis_type}
    analysis_profiles="${nextflow_profiles},${analysis_type}"
    # echo "${root_input_dir}/${analysis_type}"
    for eager_input in ${root_input_dir}/${analysis_type}/*/*.tsv; do
        ## Set output directory name from eager input name
        eager_output_dir="${root_output_dir}/${analysis_type}/$(basename ${eager_input} .tsv)"
        # ## Run name is individual ID followed by analysis_type
        # run_name="$(basename ${eager_input} .tsv)_${analysis_type}"
        # echo $run_name
        ## If no multiqc_report exists (last step of eager), or TSV is newer than the report, start an eager run.
        #### Always running with resume will ensure runs are only ever resumed instead of restarting.
        if [[ ${eager_input} -nt ${eager_output_dir}/multiqc/multiqc_report.html ]]; then
            ## Debugging info.
            echo "Running eager on ${eager_input}:"
            echo "nextflow run nf-core/eager \
                -r ${eager_version} \
                -profile ${analysis_profiles} \
                -c ${autorun_config} \
                --input ${eager_input} \
                --email ${USER}@eva.mpg.de \
                --outdir ${eager_output_dir} \
                -w ${eager_output_dir}/work \
                -with-tower -ansi-log false \
                -resume"
            
            ## Actually run eager now.
            nextflow run nf-core/eager \
                -r ${eager_version} \
                -profile ${analysis_profiles} \
                -c ${autorun_config} \
                --input ${eager_input} \
                --email ${USER}@eva.mpg.de \
                --outdir ${eager_output_dir} \
                -w ${eager_output_dir}/work \
                -with-tower -ansi-log false \
                -resume # ${run_name}
        fi
    done
done
