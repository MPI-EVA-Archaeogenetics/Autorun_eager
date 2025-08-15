## This script builds a Singularity image using Docker.
## It is designed to be used on OSX systems which lack a native Singularity option.
## This is necessary because building singularity images requires sudo privileges, which are not available on the servers.
## It requires Docker to be installed and running.
docker pull tclamnidis/singularity-in-docker:3.8.1
docker run --rm --privileged -v $(pwd):/work tclamnidis/singularity-in-docker:3.8.1 build --force singularity/AE_R_deps_singularity.sif singularity/AE_R_deps_singularity.def

## The resulting image should then be moved to the appropriate directory on the server-side installation of Autorun_eager.
## scp singularity/AE_R_deps_singularity.sif autoeager:/mnt/archgen/Autorun_eager/singularity/