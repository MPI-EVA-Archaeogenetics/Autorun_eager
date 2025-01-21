# Autorun_eager: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.6.0] - XX/XX/XXXX

### `Added`

- Processing of YC data. (Y + mtDNA capture (YMCA))
- `conf/Autorun.config`: Use hard links when publishing results, instead of copying files.
- `scripts/create_poseidon_release.sh`: New script to create large releases of the entire TF processed data in Poseidon format.
- Now compatible with Pandora Site IDs longer than 3 letters.
  - The following scripts can now infer Site_ID of varied lengths from the Ind_ID (pyPandoraHelper):
    - `scripts/clear_results.sh`
    - `scripts/clear_work_dirs.sh`
    - `scripts/ethical_sample_scrub.sh`
    - `scripts/run_Eager.sh`
    - `scripts/update_poseidon_packages.sh`
  - The following scripts can now infer Site_ID of varied lengths from the Ind_ID (rPandoraHelper):
    - `scripts/prepare_eager_tsv.R`
    - `scripts/fill_in_janno.R`

### `Fixed`

### `Dependencies`

- pyPandoraHelper=0.2.1
- rPandoraHelper=0.2.0

### `Deprecated`

## [1.5.0] - 30/09/2024

### `Added`

- Processing of RM data. (Twist capture + mtDNA)
  - `conf/Autorun.config`: Add RP profile for processing twist capture results. Identical to TF for now.
  - `scripts/prepare_eager_tsv.R`: Add RP analysis type for twist capture results
  - `scripts/run_Eager.sh`: Run for RP TSVs.
  - `scripts/cron_daily_prepare.sh`: Create RP analysis TSVs daily.
  - `scripts/ethical_sample_scrub.sh`: Add RP analysis type for ethical sample scrubbing.
  - `scripts/clear_work_dirs.sh`: Add RP analysis type for work directory clearing.
  - `scripts/clear_results.sh`: Add RP analysis type for results directory clearing.
- `scripts/update_poseidon_packages.sh`: Bump version for new release.
- `README.md`: Updated to list new state of the pipeline.

### `Fixed`

### `Dependencies`

### `Deprecated`

## [1.4.0] - 12/07/2023

### `Added`

- Processing of RP data. (Twist capture)
  - `conf/Autorun.config`: Add RP profile for processing twist capture results. Identical to TF for now.
  - `conf/Autorun.config`: Use mapdamage for damage calculation. Limit to 100000 reads, to lower runtime.
  - `scripts/prepare_eager_tsv.R`: Add RP analysis type for twist capture results
  - `scripts/run_Eager.sh`: Run for RP TSVs.
  - `scripts/cron_daily_prepare.sh`: Create RP analysis TSVs daily.
  - `scripts/ethical_sample_scrub.sh`: Add RP analysis type for ethical sample scrubbing.
  - `scripts/clear_work_dirs.sh`: Add RP analysis type for work directory clearing.
  - `scripts/clear_results.sh`: Add RP analysis type for results directory clearing.

### `Fixed`

### `Dependencies`

- nf-core/eager=2.5.0

### `Deprecated`

## [1.3.0] - 12/07/2023

### `Added`

- `scripts/ethical_sample_scrub.sh`: A script to remove eager input/outputs for samples that were marked as ethically sensitive after the pipelines picked them up.
- `scripts/cron_ethical_scrub.sh`: A cron-able script to run `ethical_sample_scrub.sh` daily.
- `scripts/clear_work_dirs.sh`: A bash script to `rm -r` the work directories of an individual ID for both `SG` and `TF` processing.
- `scripts/clear_results.sh`: A bash script that deletes the results for an individual while maintaining the nextflow process cache for them.

### `Fixed`

- `scripts/cron_daily_prepare.sh`: Silenced permission errors due to ethical sample scrubbing.

### `Dependencies`

### `Deprecated`

## [1.2.0] - 21/03/2023

### `Added`

- `prepare_eager_tsv.R`: Added `-w/--whitelist` option. A whitelist of Pandora Individual IDs can be provided. Only the TSVs of individuals in the whitelist will be updated.

### `Fixed`

- `update_poseidon_packages.sh`: `Library_Names` field now includes only unique library names.
- `prepare_eager_tsv.R`: Camel_Case versions of Pandora Analysis IDs are no longer filtered out.

### `Dependencies`

### `Deprecated`

## [1.1.3] - 17/03/2023

### `Added`

### `Fixed`

- Column naming in `fill_in_janno.R`. `Nr_Libs` -> `Nr_Libraries`.
- `prepare_eager_tsv.R` no longer joins with non-unique iids. Optimised performance and less likely to kill the TSV maker.
- Increased memory given to eager spawner array jobs.

### `Dependencies`

### `Deprecated`

## [1.1.2] - 02/01/2023

### `Added`

- Add `-a` option to `run_Eager.sh` to create a text file with the run commands for launching Autorun_eager, for submission as a qsub array.
- Add array submission script.
- Add script to create and update poseidon packages from eager output.
  - Includes script to collate eager results and overwrite the janno of a poseidon pacakge.
  - Includes script to update poseidon indFile from janno files.
  - Each poseidon package contains a file named `AE_version.txt` with the version used for the last package creation/update.
- Added conda environment yaml file `autoeager_env.yml`

### `Fixed`

- Fixed pull request template.
- Fixed a bug where sequencing runs were considered updated if the `Results.txt` was updated without changing the data. Now only changes to the output bams constitute an update trigger.
- Fixed a bug where TSV creation would try to match the sequencing ID to the sequencing batch ID, instead of the run ID.

### `Dependencies`

### `Deprecated`

## [1.1.1] - 11/10/2022

### `Added`

### `Fixed`

- An error was thrown when trying to create the version file in non existing directories. now fixed.

### `Dependencies`

### `Deprecated`

## [1.1.0] - 07/10/2022

### `Added`

- Added bed file for on-target coverage calculation for TF data. In SG this parameter gets overwritten and hence ignored.
- `prepare_eager_tsv.R` now also creates a version file within the directory of the TSV.
- Added github PR template.

### `Fixed`

- Parameters that require local paths have been moved to their own profile to aid in reproducibility outside of the EVA cluster.

### `Dependencies`

### `Deprecated`

## [1.0.0] - 19/09/2022

### `Added`

- Directory structure now includes a subdirectory with the site ID.
- Jobs are now submitted to `all.q`

### `Fixed`

- Fixed a bug where the bams of additional Autorun pipelines would be pulled for processing than intended.
- The sample names for single stranded libraries now include the suffix `_ss` in the Sample Name field. Avoids file name collisions and makes merging of genotypes easier and allows end users to pick between dsDNA and ssDNA genotypes for individuals where both are available.
- Library names of single stranded libraries also include the suffix `_ss` in the Library Name field. This ensures that rows in the MultiQC report are sorted correctly.

### `Dependencies`

- nf-core/eager=2.4.5

### `Deprecated`

## [0.1.0] - 03/02/2022

Initial release of Autorun_eager.

### `Added`

- Configuration file with Autorun_eager parameter defaults in dedicated profiles for each analysis type.
- Script to prepare input TSV from pandora info, using Autorun outputted bams as input.
- Script to crawl through eager_inputs directory and run eager on each newly generated/updated input.
- cron script with the basic commands needed to run daily for full automation.

### `Fixed`

### `Dependencies`

- [sidora.core](https://github.com/sidora-tools/sidora.core)
- [pandora2eager](https://github.com/sidora-tools/pandora2eager)
- [nf-core/eager](https://github.com/nf-core/eager) `2.4.2`

### `Deprecated`
