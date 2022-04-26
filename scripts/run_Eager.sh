#!/usr/bin/env bash

## Flood execution. Useful for testing/fast processing of small batches.
if [[ $1 == "-r" || $1 == "--rush" ]]; then
    rush="-bg"
else
    rush=''
fi

nxf_path="/mnt/archgen/tools/nextflow/21.04.3.5560"
eager_version='2.4.4'
autorun_config='/mnt/archgen/Autorun_eager/conf/Autorun.config' ## Contains specific profiles with params for each analysis type.
root_input_dir='/mnt/archgen/Autorun_eager/eager_inputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each individual.
####        E.g. /mnt/archgen/Autorun_eager/eager_inputs/SG/GUB001/GUB001.tsv
root_output_dir='/mnt/archgen/Autorun_eager/eager_outputs'

## Testing
# root_input_dir='/mnt/archgen/Autorun_eager/dev/testing/eager_inputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each individual.
# root_output_dir='/mnt/archgen/Autorun_eager/dev/testing/eager_outputs'

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
    for eager_input in ${root_input_dir}/${analysis_type}/*/*/*.tsv; do
        ## Set output directory name from eager input name
        ind_id=$(basename ${eager_input} .tsv)
        site_id="${ind_id:0:3}"
        eager_output_dir="${root_output_dir}/${analysis_type}/${site_id}/${ind_id}"

        run_name="-resume" ## To be changed once/if a way to give informative run names becomes available
        
        ## TODO Give informative run names for easier trackingin tower.nf
        ##  If the output directory exists, assume you need to resume a run, else just name it
        # if [[ -d "${eager_output_dir}" ]]; then
        #     command_string="-resume"
        # else
        #     command_string="-name"
        # fi
        # ## Run name is individual ID followed by analysis_type. -resume or -name added as appropriate
        # run_name="${command_string} $(basename ${eager_input} .tsv)_${analysis_type}"

        ## If no multiqc_report exists (last step of eager), or TSV is newer than the report, start an eager run.
        #### Always running with resume will ensure runs are only ever resumed instead of restarting.
        if [[ ${eager_input} -nt ${eager_output_dir}/multiqc/multiqc_report.html ]]; then

            ## Change to input directory to run from, to keep one cwd per run.
            cd $(dirname ${eager_input})
            ## Debugging info.
            echo "Running eager on ${eager_input}:"
            echo "${nxf_path}/nextflow run nf-core/eager \
                -r ${eager_version} \
                -profile ${analysis_profiles} \
                -c ${autorun_config} \
                --input ${eager_input} \
                --outdir ${eager_output_dir} \
                -w ${eager_output_dir}/work \
                -with-tower \
                -ansi-log false \
                ${run_name} ${rush}"
            
            ## Actually run eager now.
                ## Monitor run in nf tower. Only works if TOWER_ACCESS_TOKEN is set.
                ## Runs show in the Autorun_Eager workspace on tower.nf
            ${nxf_path}/nextflow run nf-core/eager \
                -r ${eager_version} \
                -profile ${analysis_profiles} \
                -c ${autorun_config} \
                --input ${eager_input} \
                --outdir ${eager_output_dir} \
                -w ${eager_output_dir}/work \
                -with-tower \
                -ansi-log false \
                ${run_name} ${rush}
            
            cd ${root_input_dir} ## Then back to root dir
        fi
    done
done
