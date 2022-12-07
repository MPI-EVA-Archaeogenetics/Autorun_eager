#!/usr/bin/env bash

if [[ ${1} = '' ]]; then
    echo "No input file provided."
    exit 0
else
    job_list_fn="${1}"
fi

command=$(sed -n ${SGE_TASK_ID}p ${job_list_fn})

# echo "$command"
bash -c "${command}"