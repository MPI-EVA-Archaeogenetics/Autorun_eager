## This script builds a Singularity image using Docker.
## It is designed to be used on OSX systems which lack a native Singularity option.
## This is necessary because building singularity images requires sudo privileges, which are not available on the servers.
## It requires Docker to be installed and running.
docker pull tclamnidis/singularity-in-docker:3.8.1
docker run --rm --privileged -v $(pwd):/work tclamnidis/singularity-in-docker:3.8.1 build --force singularity/sidora_AE_singularity.sif singularity/sidora_AE_singularity.def
