#!/usr/bin/env bash

if [[ ${1} = '' ]]; then
    echo "No input file provided."
    exit 0
else
    job_list_fn="${1}"
fi

## Pick the correct task ID in both the SGE and the SLURM cluster.
if ! hostname | grep -q -e login -e hpc -e dlcenode ; then 
    task_id=${SGE_TASK_ID}
else
    task_id=${SLURM_ARRAY_TASK_ID}
fi

command=$(sed -n ${task_id}p ${job_list_fn})

# echo "$command"
bash -c "${command}"