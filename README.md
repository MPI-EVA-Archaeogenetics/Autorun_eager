# Autorun_eager

Automated nf-core/eager processing of Autorun output bams.

## Quickstart

> [!NOTE]
> A Singularity wrapper is provided for R scripts: `scripts/run_Rscript_containerised.sh`.
> It is recommended that you use the provided Singularity image wrapper to run Rscripts in this repository.
> This ensures that the required R packages are available and that the scripts run in a consistent environment.

- Run `prepare_eager_tsv.R` for human SG, TF, TM, RP, RM, IM, or YC data for a given sequencing batch:

    ```bash
    prepare_eager_tsv.R -s <batch_Id> -a SG -o eager_inputs/ -d .eva_credentials
    prepare_eager_tsv.R -s <batch_Id> -a TF -o eager_inputs/ -d .eva_credentials
    prepare_eager_tsv.R -s <batch_Id> -a TM -o eager_inputs/ -d .eva_credentials
    prepare_eager_tsv.R -s <batch_Id> -a RP -o eager_inputs/ -d .eva_credentials
    prepare_eager_tsv.R -s <batch_Id> -a RM -o eager_inputs/ -d .eva_credentials
    prepare_eager_tsv.R -s <batch_Id> -a IM -o eager_inputs/ -d .eva_credentials
    prepare_eager_tsv.R -s <batch_Id> -a YC -o eager_inputs/ -d .eva_credentials
    ```

- Run eager with the following script, which then runs on the generated TSV files:

    ```bash
    run_Eager.sh -a
    ```

⚠️ For some library preparation protocols and external libraries, UDG treatment cannot be reliably inferred, and errors will be thrown.
In such cases, an eager input TSV will still be created, but UDG treatment for affected libraries will be set to 'Unknown' and needs to be manually edited.

## Autorun.config

Contains the `autorun`, `local_paths`, `SG`, `TF`, `TM`, `RP`, `RM`, `IM`, and `YC`  profiles.

### autorun

Broader scope options and parameters for use across all processing with autorun.

Turns off automatic cleanup of intermediate files on successful completion of a run to allow resuming of the run when additional data becomes available, without rerunning completed steps.

### local_paths

This is profile contains all paramters provided to BOTH SG and TF runs that are paths to files on the local MPI-EVA filesystem. 
They are provided in a separate profile to make it clearer to provided added transparency as well as make it easier for third parties to reproduce the processing done with Autorun_eager (e.g. by loading the `SG` or `TF` remote profiles) without getting errors about paths that do not exist on their filesystem.

### SG

The standardised parameters for processing human shotgun data.

### TF

The standardised parameters for processing human 1240k capture data.

### TM

The standardised parameters for processing human 1240k+MT capture data.

### RP

The standardised parameters for processing human Twist capture data.

### RM

The standardised parameters for processing human Twist+MT capture data.

### IM

The standardised parameters for processing human Immuno-capture data.

### YC

The standardised parameters for processing human Y+MT (YMCA) capture data.

## prepare_eager_tsv.R

> [!NOTE]
> A Singularity wrapper is provided for R scripts: `scripts/run_Rscript_containerised.sh`.
> It is recommended that you use the provided Singularity image wrapper to run Rscripts in this repository.
> This ensures that the required R packages are available and that the scripts run in a consistent environment.


An R script that when given a sequencing batch ID, Autorun Analysis type and PANDORA credentials will create/update eager input TSV files for further processing.

```bash
Usage: ./scripts/prepare_eager_tsv.R [options] .credentials


Options:
	-h, --help
		Show this help message and exit

	-s SEQUENCING_BATCH_ID, --sequencing_batch_id=SEQUENCING_BATCH_ID
		The Pandora sequencing batch ID to update eager input for. A TSV file will be prepared
			for each individual in this run, containing all relevant processed BAM files
			from the individual

	-a ANALYSIS_TYPE, --analysis_type=ANALYSIS_TYPE
		The analysis type to compile the data from. Should be one of: 'SG', 'TF', 'RP', 'RM', 'YC', 'IM'.

	-r, --rename
		Changes all dots (.) in the Library_ID field of the output to underscores (_).
			Some tools used in nf-core/eager will strip everything after the first dot (.)
			from the name of the input file, which can cause naming conflicts in rare cases.

	-w WHITELIST, --whitelist=WHITELIST
		An optional file that includes the IDs of whitelisted individuals,
			one per line. Only the TSVs for these individuals will be updated.

	-o OUTDIR, --outDir=OUTDIR
		The desired output directory. Within this directory, one subdirectory will be 
			created per analysis type, within that one subdirectory per individual ID,
			and one TSV within each of these directory.

	-d, --debug_output
		When provided, the entire result table for the run will be saved as '<seq_batch_ID>.results.txt'.
			Helpful to check all the output data in one place.
Note: a valid sidora .credentials file is required. Contact the Pandora/Sidora team for details.
```

The eager input TSVs will be created in the following directory structure, given `-o eager_inputs`:

```text
eager_inputs
├── SG
│   └──ABC
│       ├── ABC001
│       └── ABC002
├── TF
│   └──ABC
│       ├── ABC001
│       └── ABC002
├── TM
│   └──ABC
│       ├── ABC001
│       └── ABC002
├── RP
│   └──ABC
│       ├── ABC001
│       └── ABC002
├── RM
│   └──ABC
│       ├── ABC001
│       └── ABC002
├── YC
│   └──ABC
│       ├── ABC001
│       └── ABC002
└── IM
    └──ABC
         ├── ABC001
         └── ABC002
```

Alongside each created TSV is a file named `autorun_eager_version.txt`, which states the version of Autorun_eager used.

## run_Eager.sh

A wrapper shell script that goes through all TSVs in the `eager_inputs` directory, checks if a completed run exists for a given TSV, and submits/resumes an eager run for that individual if necessary.

Currently uses eager version `2.5.0` and profiles `eva,archgen,medium_data,autorun,local_paths` across all runs, with the appropriate profile.

The outputs are saved with the same directory structure as the inputs, but in a separate parent directory.

```text
eager_outputs
├── SG
│   └──ABC
│       ├── ABC001
│       └── ABC002
├── TF
│   └──ABC
│       ├── ABC001
│       └── ABC002
├── RP
│   └──ABC
│       ├── ABC001
│       └── ABC002
└── RM
    └──ABC
         ├── ABC001
         └── ABC002
```

This script recognises the `-a/--array` option. When this is provided, instead of running eager jobs in sequence, a temporary file is created named `$(date +'%y%m%d_%H%M')_Autorun_eager_queue.txt` that includes the command line of all eager jobs to-be-ran, one per line. An "Autorun_eager spawner" (`AE_spawner`) array job is then submitted using `qsub`, which uses a secondary script named `scripts/submit_as_array.sh` to submit the command in each line of the temporary file as a separate task. In this manner, 10 eager runs can be ran in parallel. Logs for these jobs will then be added to a directory named `array_Logs/<temp_file_name>/`.

## update_poseidon_package.sh

A shell script that will check the available TF genotype datasets for a given individual and create/update a poseidon package with the data of that individual.

```
	 usage: ./scripts/update_poseidon_package.sh [options] <ind_id>

This script pulls data and metadata from Autorun_eager for the TF version of the specified individual and creates a poseidon package.

Options:
-h, --help		Print this text and exit.
-v, --version 		Print version and exit.
```

Comparing the timestamp of the Autorun_eager genotypes and those in the poseidon package for the individual (if one exists already) this script will create/update a poseidon package where necessary by doing the following:
1. Check if a package creation/update is needed. If not, exit happily.
2. Create a bare poseidon package from the available Autorun_eager genotypes **in a temporary directory**.
    - Paste together dsDNA and ssDNA genotypes before creating bare package, if necessary.
3. Pull information from Pandora and Autorun_eager to populate the package janno files, using `scripts/fill_in_janno.R`. This also updates the Genetic_Sex field.
4. Update the genetic sex in the package ind file, so it matches the updated janno, using `scripts/update_dataset_from_janno.R`.
5. Use `trident update` to bump the package version (`1.0.0` if the package is newly created), and create a Changelog.
6. Validate the resulting package.
7. If validation passes, publish the (updated) version of the package to the central repository in `poseidon_packages/` and remove any temporary files created.

## ethical_sample_scrub.sh

A shell script that scrubs the Autorun_eager input and output directories of all individuals in a specified list of sensitive sequencing IDs. This is used daily with the most up-to-date list of sensitive sequencing IDs to ensure that no results are available even if marking samples as sensitive was done late.

```
     usage: ethical_sample_scrub.sh [options] <sensitive_seqIds_list>

This script pulls the Pandora individual IDs from the list of sensitive sequencing IDs, and
    removes all Autorun_eager input and outputs from those individuals (if any).
    This ensures that no results are available even if marking samples as sensitive was done late.

Options:
-h, --help		Print this text and exit.
```

## clear_work_dirs.sh

A shell script that will clear the work directories of individuals in a specified individual ID list from both the SG and TF results directories.

```
     usage: clear_work_dirs.sh [options] <ind_id_list>

This script clears the work directories of individuals in a specified individual ID list from both the SG and TF results directories.

Options:
-h, --help		Print this text and exit.
```

## clear_results.sh

A shell script that clears the results directories of all individuals in a specified list While maintaining nextflow's caching of already-ran processes. This is useful for refreshing the results directories of individuals when changes to the input might have changes merging of libraries, thus making the directory structure inconsistent.

```
     usage: clear_results.sh [options] <ind_id_list>

This script removes all output directory contents for the provided individuals, without clearing out caching, allowing for the results to be re-published.
    This enables refreshing of result directories when changes to the input might have changes merging of libraries, thus making the directory structure inconsistent.

Options:
-h, --help		Print this text and exit.
-a, --analysis_type		Set the analysis type. Options: TF, SG.
```

## create_processed_ind_list.sh

A shell script that creates a list of processed individuals for each analysis type, as well as across all analysis types, from the results directories of the eager outputs.
These lists are then used to provide counts of the number of processed individuals in a dedicated file.

```
		 usage: create_processed_ind_list.sh
```

