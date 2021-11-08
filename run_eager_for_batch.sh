#!/usr/bin/env bash
VERSION="0.1.0"

## Parse CLI args.
TEMP=`getopt -q -o hvS: --long help,version,Sequencing_Id: -n 'run_eager_for_batch.sh' -- "$@"`
eval set -- "$TEMP"

## Debugging
# echo $TEMP

## Helptext function
function Helptext {
    echo -ne "\t usage: $0 [options]\n\n"
    echo -ne "This script will take a sequencing run ID, find the data for all demultiplexed individuals, and create/update the eager input TSV for those individuals.\n\n"
    echo -ne "options:\n"
    echo -ne "-h, --help\t\tPrint this text and exit.\n"
    echo -ne "-S, --Sequencing_Id\t\tThe pandora sequencing ID of the run.\n"
    # echo -ne "-v, --version \t\tPrint version and exit.\n"
}

if [ $? -ne 0 ]
then
    Helptext
fi

## Read in CLI arguments
while true ; do
    case "$1" in
        -S|--Sequencing_Id) sid=("$2"); shift 2;;
        -h|--help) Helptext; exit 0 ;;
        # -v|--version) echo "${VERSION}"; exit 0;;
        --) break;;
        *) echo "Invalid option specified."; Helptext; exit 1;; 
    esac
done
