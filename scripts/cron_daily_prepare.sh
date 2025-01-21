#!/bin/bash

# determine which new Results have accumulated within a day, 
# prepare for processing with nf-core/eager
## Use creation time of bams to avoid picking up changes in statistics without change in data.

cd /mnt/archgen/Autorun_eager

# 1240k
# Note: this find only checks runs starting from 2020. Silence stderr to avoid 'permission denied'.
find /mnt/archgen/Autorun/Results/Human_1240k/2* -name '*.bam' -mtime -1 2>/dev/null | cut -f 7 -d "/" | sort -u | while read RUN ; do
    echo "Processing TF data from run: ${RUN}"
    scripts/prepare_eager_tsv.R -s $RUN -a TF -o eager_inputs/ -d .eva_credentials
done

# Shotgun
# Note: this find only checks runs starting from 2020.  Silence stderr to avoid 'permission denied'.
find /mnt/archgen/Autorun/Results/Human_Shotgun/2* -name '*.bam' -mtime -1 2>/dev/null | cut -f 7 -d "/" | sort -u | while read RUN ; do
    echo "Processing SG data from run: ${RUN}"
    scripts/prepare_eager_tsv.R -s $RUN -a SG -o eager_inputs/ -d .eva_credentials
done

# Twist
# Note: this find only checks runs starting from 2020.  Silence stderr to avoid 'permission denied'.
find /mnt/archgen/Autorun/Results/Human_RP/2* -name '*.bam' -mtime -1 2>/dev/null | cut -f 7 -d "/" | sort -u | while read RUN ; do
    echo "Processing RP data from run: ${RUN}"
    scripts/prepare_eager_tsv.R -s $RUN -a RP -o eager_inputs/ -d .eva_credentials
done

# Twist + mtDNA
# Note: this find only checks runs starting from 2020.  Silence stderr to avoid 'permission denied'.
find /mnt/archgen/Autorun/Results/Human_RM/2* -name '*.bam' -mtime -1 2>/dev/null | cut -f 7 -d "/" | sort -u | while read RUN ; do
    echo "Processing RM data from run: ${RUN}"
    scripts/prepare_eager_tsv.R -s $RUN -a RM -o eager_inputs/ -d .eva_credentials
done

# Y + mtDNA capture (YMCA)
# Note: this find only checks runs starting from 2020.  Silence stderr to avoid 'permission denied'.
find /mnt/archgen/Autorun/Results/Human_Y/2* -name '*.bam' -mtime -1 2>/dev/null | cut -f 7 -d "/" | sort -u | while read RUN ; do
    echo "Processing YC data from run: ${RUN}"
    scripts/prepare_eager_tsv.R -s $RUN -a YC -o eager_inputs/ -d .eva_credentials
done
