# Autorun_eager: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 25/04/2022

### `Added`

- Directory structure now includes a subdirectory with the site ID.

### `Fixed`

- Fixed a bug where the bams of additional Autorun pipelines would be pulled for processing than intended.
- The sample names for single stranded libraries now include the suffix `_ss` in the Sample Name field. Avoids file name collisions and makes merging of genotypes easier and allows end users to pick between dsDNA and ssDNA genotypes for individuals where both are available.

### `Dependencies`

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
