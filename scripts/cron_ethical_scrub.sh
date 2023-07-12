#!/bin/bash

## Use ethically_culturally_sensitive list to scrub any sensitive sample results

cd /mnt/archgen/Autorun_eager

list_fn="/mnt/archgen/Autorun/Pandora_Tables/Ethically_Sensitive.txt"

scripts/ethical_sample_scrub.sh ${list_fn}
