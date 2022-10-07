# Autorun_eager: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
