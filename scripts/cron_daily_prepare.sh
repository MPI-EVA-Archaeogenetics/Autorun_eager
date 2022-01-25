#!/bin/bash

# determine which new Results have accumulated within a day, 
# prepare for processing with EAGER

cd /mnt/archgen/Autorun_eager

# 1240k
# Note: this find only checks runs starting from 2020
find /mnt/archgen/Autorun/Results/Human_1240k/2* -name "Results.txt" -mtime -1 | cut -f 7 -d "/"| sort -u| while read RUN ; do
    prepare_eager_tsv.R -s $RUN -a TF -o eager_inputs/ -d .eva_credentials
done 

# Shotgun
# Note: this find only checks runs starting from 2020
find /mnt/archgen/Autorun/Results/Human_Shotgun/2* -name "Results.txt" -mtime -1 | cut -f 7 -d "/"| sort -u| while read RUN ; do
    prepare_eager_tsv.R -s $RUN -a SG -o eager_inputs/ -d .eva_credentials
done 