#!/usr/bin/env bash

## DEPENDENCY
pandora_helper="/mnt/archgen/tools/helper_scripts/py_helpers/pyPandoraHelper/pyPandoraHelper.py"

## Defaults
valid_analysis_types=("TF" "SG" "RP" "RM" "IM" "YC")
rush=''
array=''
temp_file=''

## Flood execution. Useful for testing/fast processing of small batches.
if [[ $1 == "-r" || $1 == "--rush" ]]; then
    rush="-bg"
elif [[ $1 == '-a' || $1 == "--array" ]]; then
    array='TRUE'
    temp_file="/mnt/archgen/Autorun_eager/$(date +'%y%m%d_%H%M')_Autorun_eager_queue.txt"
    ## Create new empty file with the correct naming, or flush contents of file if somehow it exists.
    echo -n '' > ${temp_file}
fi

nxf_path="/home/srv_autoeager/conda/envs/autoeager/bin/"
eager_version='2.5.0'
autorun_config='/mnt/archgen/Autorun_eager/conf/Autorun.config' ## Contains specific profiles with params for each analysis type.
root_input_dir='/mnt/archgen/Autorun_eager/eager_inputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each individual.
####        E.g. /mnt/archgen/Autorun_eager/eager_inputs/SG/GUB001/GUB001.tsv
root_output_dir='/mnt/archgen/Autorun_eager/eager_outputs'

## Testing
# root_input_dir='/mnt/archgen/Autorun_eager/dev/testing/eager_inputs' ## Directory should include subdirectories for each analysis type (TF/SG) and sub-subdirectories for each individual.
# root_output_dir='/mnt/archgen/Autorun_eager/dev/testing/eager_outputs'

## Set base profiles for EVA cluster.
nextflow_profiles="eva,archgen,medium_data,autorun,local_paths"

## Set colour and face for colour printing
Red='\033[1;31m'$(tput bold) ## Red bold face
Yellow=$(tput sgr0)'\033[1;33m' ## Yellow normal face

## Since I'm running through all data every time, the runtime of the script will increase marginally over time. 
## Maybe create a list of eager inputs that are newer than the MQC reports and use that to loop over?
for analysis_type in ${valid_analysis_types[@]}; do
    # echo ${analysis_type}
    analysis_profiles="${nextflow_profiles},${analysis_type}"
    # echo "${root_input_dir}/${analysis_type}"
    for eager_input in ${root_input_dir}/${analysis_type}/*/*/*.tsv; do
        ## Set output directory name from eager input name
        ind_id=$(basename ${eager_input} .tsv)
        site_id=`${pandora_helper} -g site_id ${ind_id}` ## Site inferred by pyPandoraHelper
        eager_output_dir="${root_output_dir}/${analysis_type}/${site_id}/${ind_id}"

        run_name="-resume" ## To be changed once/if a way to give informative run names becomes available

        ## If no multiqc_report exists (last step of eager), or TSV is newer than the report, start an eager run.
        #### Always running with resume will ensure runs are only ever resumed instead of restarting.
        if [[ ${eager_input} -nt ${eager_output_dir}/multiqc/multiqc_report.html ]]; then

            if [[ ${array} == 'TRUE' ]]; then
            ## For array submissions, the commands to be run will be added one by one to the temp_file
            ## Then once all jobs have been added, submit that to qsub with each line being its own job.
            ## Use `continue` to avoid running eager interactivetly for arrayed jobs.
                echo "cd $(dirname ${eager_input}) ; ${nxf_path}/nextflow run nf-core/eager \
                -r ${eager_version} \
                -profile ${analysis_profiles} \
                -c ${autorun_config} \
                --input ${eager_input} \
                --outdir ${eager_output_dir} \
                -w ${eager_output_dir}/work \
                -with-tower \
                -ansi-log false \
                ${run_name} ${rush}" | tr -s " " >> ${temp_file}
                continue ## Skip running eager interactively if arrays are requested.
            fi

            ## NON-ARRAY RUNS
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

## If array is requested submit the created array file to qsub below
if [[ ${array} == 'TRUE' ]]; then
    mkdir -p /mnt/archgen/Autorun_eager/array_Logs/$(basename ${temp_file}) ## Create new directory for the logs for more traversable structure
    jn=$(wc -l ${temp_file} | cut -f 1 -d " ") ## number of jobs equals number of lines
    export NXF_OPTS='-Xms6G -Xmx6G' ## Set 4GB limit to Nextflow VM
    export JAVA_OPTS='-Xms12G -Xmx12G -XX:ParallelGCThreads=1' ## Set 8GB limit to Java VM. Single GarbageCollecteor thread
    ## -V Pass environment to job (includes nxf/java opts)
    ## -S /bin/bash Use bash
    ## -l v_hmem=40G ## 40GB memory limit (8 for java + the rest for garbage collector)
    ## -pe smp 2 ## Use two cores. one for nextflow, one for garbage collector
    ## -n AE_spawner ## Name the job
    ## -cwd Run in currect run directory (ran commands include a cd anyway, but to find the files at least)
    ## -j y ## join stderr and stdout into one output log file
    ## -b y ## Provided command is a binary already (i.e. executable)
    ## -o /mnt/archgen/Autorun_eager/array_Logs/ ## Keep all log files in one directory.
    ## -tc 10 ## Number of concurrent spawner jobs (10)
    ## -t 1-${jn} ## The number of array jobs (from 1 to $jn)
    echo "qsub -V -S /bin/bash -l h_vmem=40G -pe smp 2 -N AE_spawner_$(basename ${temp_file}) -cwd -j y -b y -o /mnt/archgen/Autorun_eager/array_Logs/$(basename ${temp_file}) -tc 10 -t 1-${jn} /mnt/archgen/Autorun_eager/scripts/submit_as_array.sh ${temp_file}"
    qsub -V -S /bin/bash -l h_vmem=40G -pe smp 2 -N AE_spawner_$(basename ${temp_file}) -cwd -j y -b y -o /mnt/archgen/Autorun_eager/array_Logs/$(basename ${temp_file}) -tc 10 -t 1-${jn} /mnt/archgen/Autorun_eager/scripts/submit_as_array.sh ${temp_file}
fi
