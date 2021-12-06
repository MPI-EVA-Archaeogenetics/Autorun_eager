# EVA_autorun
Automated eager processing of Autorun output bams. 

# Quickstart
 - Run `prepare_eager_tsv.R` for SG or TF data for a given sequencing batch:
```
./prepare_eager_tsv.R -s 210429_K00233_0191_AHKJHFBBXY_Jena0014 -a SG -o eager_inputs/ -d .eva_credentials
./prepare_eager_tsv.R -s 210802_K00233_0212_BHLH3FBBXY_SRdi_JR_BN -a TF -o eager_inputs/ -d .eva_credentials
```
 - Run eager:
```
run_Eager.sh
```

⚠️ For some library preparation protocols and external libraries, UDG treatment cannot be reliably inferred, and errors will be thrown.
In such cases, an eager input TSV will still be created, but UDG treatment for affected libraries will be set to 'Unknown' and needs to be manually edited.

## Autorun.config
Contains the `autorun`, `SG` and `TF` profiles.

#### autorun
Broader scope options and parameters for use across all processing with autorun.  
Turns off automatic cleanup of intermediate files on successful completion of a run to allow resuming of the run when additional data becomes available, without rerunning completed steps.

#### SG
The standardised parameters for processing shotgun data.

#### TF
The standardised parameters for processing 1240k capture data.

## prepare_eager_tsv.R
An R script that when given a sequencing batch ID, Autorun Analysis type and PANDORA credentials will create/update eaget input TSV files for further processing.
```
Usage: ./prepare_eager_tsv.R [options] .credentials


Options:
	-h, --help
		Show this help message and exit

	-s SEQUENCING_BATCH_ID, --sequencing_batch_id=SEQUENCING_BATCH_ID
		The Pandora sequencing batch ID to update eager input for. A TSV file will be prepared
			for each individual in this run, containing all relevant processed BAM files
			from the individual

	-a ANALYSIS_TYPE, --analysis_type=ANALYSIS_TYPE
		The analysis type to compile the data from. Should be one of: 'SG', 'TF'.

	-r, --rename
		Changes all dots (.) in the Library_ID field of the output to underscores (_).
			Some tools used in nf-core/eager will strip everything after the first dot (.)
			from the name of the input file, which can cause naming conflicts in rare cases.

	-o OUTDIR, --outDir=OUTDIR
		The desired output directory. Within this directory, one subdirectory will be 
			created per analysis type, within that one subdirectory per individual ID,
			and one TSV within each of these directory.

	-d, --debug_output
		When provided, the entire result table for the run will be saved as '<seq_batch_ID>.results.txt'.
			Helpful to check all the output data in one place.
```

The eager input TSVs will be created in the following directory structure, given `-o eager_inputs`:
```
eager_inputs
├── SG
│   ├── IND001
│   └── IND002
└── TF
    ├── IND001
    └── IND002
```

## run_Eager.sh
A wrapper shell script that goes through all TSVs in the `eager_inputs` directory, checks if a completed run exists for a given TSV, and submits/resumes an
eager run for that individual if necessary.

Currently uses eager version `2.4.1` and profiles `eva,archgen,medium_data,autorun` across all runs, with the `SG` or `TF` profiles used for their respective
data types.

The outputs are saved with the same directory structure as the inputs, but in a separate parent directory.
```
eager_outputs
├── SG
│   ├── IND001
│   └── IND002
└── TF
    ├── IND001
    └── IND002
```
