#!/usr/bin/env bash

## This script is used to run the AE Singularity container with the provided arguments.
## It binds the necessary directories and executes the command inside the container.
if [[ -z $1 ]]; then
    echo "Usage: $0 <command> [args...]"
    exit 1
fi

singularity exec --bind /mnt/archgen/Autorun_eager/:/mnt/archgen/Autorun_eager/ /mnt/archgen/Autorun_eager/singularity/AE_R_deps_singularity.sif $*