# populate_janno

Populates a poseidon `.janno` file with metadata pulled from nf-core/eager result directories and the Pandora database, for a single individual and analysis type.

## What it does

Given an individual ID and an analysis type (`SG`, `TF`, `TM`, `RP`, `RM`), this script:

1. Locates the corresponding nf-core/eager input TSV and output directory on `/mnt/archgen/Autorun_eager`.
2. Parses eager result files (damage, endogenous DNA, nuclear contamination, sex determination, SNP coverage, and — where applicable — Human_MT contamination/haplogroup results) and aggregates them to sample level.
3. Queries the Pandora database for site, dating, and provenance metadata for the individual.
4. Merges both sources into the existing `.janno` file, filling in any missing fields without overwriting existing values.
5. Writes the result back out (in-place, or to a `.new` file with `--safe`).

## Installation

From the `populate_janno/` project root (the directory containing `pyproject.toml`):

```bash
pip install -e ".[test]"
```

This installs the package in editable mode plus the test dependencies (`pytest`, `pytest-mock`, `pytest-cov`). Runtime dependencies (`pandas`, `numpy`, `SQLAlchemy`, `PyMySQL`, `country_converter`, plus the internal `pyEager`/`pyPandoraHelper` packages) are installed automatically, aside from the two internal packages, which must be installed separately if not already available in your environment — see their own repos for install instructions.

## Usage

Once installed, the `populate-janno` command is available directly on your `PATH`:

```bash
populate-janno \
    -i AAR001 \
    -a RM \
    -j /path/to/AAR001_package/AAR001.janno \
    -c /mnt/archgen/Autorun_eager/.eva_credentials
```

Alternatively, without installing, run it as a module from the parent of the `populate_janno/` package directory:

```bash
python -m populate_janno -i AAR001 -a RM -j /path/to/AAR001.janno -c /path/to/credentials
```

### Arguments

| Flag | Description |
|---|---|
| `-i`, `--ind_id` | Individual ID whose janno should be updated. **Required.** |
| `-a`, `--analysis_type` | One of `SG`, `TF`, `TM`, `RP`, `RM`. **Required.** |
| `-j`, `--janno` | Path to the input `.janno` file. **Required.** |
| `-c`, `--credentials` | Path to the Pandora credentials file (host/port/login/password, one per line). **Required.** |
| `-s`, `--contamination_snp_cutoff` | Minimum SNPs required for a library's contamination estimate to be included in the sample-level weighted mean. Default: `100`. |
| `-p`, `--genotype_ploidy` | Value written to `Genotype_Ploidy` for all rows. Default: `haploid`. |
| `--safe` | Don't overwrite the input files — write to `<janno>.new` instead. Useful for testing changes without touching production packages. |
| `-v`, `--version` | Print the package version and exit. |

## Package structure

Each file has a single, narrow responsibility — this is deliberate, so that any one piece (e.g. how Human_MT results are parsed, or how Pandora dates are derived) can be understood, tested, and changed in isolation.

```
populate_janno/
├── __main__.py           # `python -m populate_janno` entry point
├── config.py              # Constants: paths, dtype maps, output column order
├── utils.py                # Small, stateless, reusable helpers
├── janno.py                 # Reading/writing/updating the .janno file itself
├── eager_run.py               # Locates & reads a single eager run's inputs/outputs on disk
├── pandora_client.py            # Pandora DB connection + SQL query construction
├── pandora_metadata.py            # Shapes raw Pandora query results into janno-ready columns
├── mt_results.py                    # Parses & aggregates Human_MT `Results.txt` files
├── library_results.py                 # Library-level metrics -> sample-level aggregation
├── sample_results.py                    # Assembles the full sample-level result table
└── populate_janno.py                      # CLI parsing + orchestration (JannoPopulator, main())
```

### File-by-file details

**`config.py`**
Static constants shared across the package: version string, the root Autorun_eager path, default CLI values, the `.janno` column dtype map, and the final output column order. Change this file when adding a new janno column, adjusting a default, or updating a filesystem path convention.

**`utils.py`**
Generic, dependency-free helper functions with no knowledge of janno/eager/Pandora specifics:
- `weighted_mean` — weighted average of a group, with a minimum-value filter.
- `coalesce_dataframes` — fill missing values in one DataFrame from another, on a shared key.
- `join_non_missing_strings` — join two optionally-missing values with a separator, or fall back to whichever is present.
- `longest_non_null_string` — pick the longest non-null string in a group (used for haplogroup aggregation; safely handles all-NA groups).

If you find yourself writing the same "handle missing values" logic twice elsewhere in the package, it likely belongs here instead.

**`janno.py`**
`JannoFile` — wraps reading a `.janno` with the correct dtypes, adding derived ID columns, coalescing in new data, finalizing computed columns (`Group_Name`, `Genotype_Ploidy`, `Data_Preparation_Pipeline_URL`), and writing the result back out.

**`eager_run.py`**
`EagerRun` — represents a single (individual, analysis_type) eager run. Resolves the site ID, eager result/input directory paths, reads the eager TSV, parses the pipeline version, and locates result file paths (damage JSONs, endogenous DNA JSONs, SNP coverage JSONs, sex determination JSON, contamination JSON). Also infers absolute BAM paths for `Genotyping_BAM`.

**`pandora_client.py`**
`PandoraClient` — owns the database connection and SQL query construction for Pandora. `_build_query` is intentionally separated from the actual connection logic so it can be tested without a live database (see `tests/test_pandora_client.py` for an example using an in-memory SQLite schema purely to exercise column reflection).

**`pandora_metadata.py`**
`PandoraIndividualMetadata` — transforms a raw Pandora query result into the individual-level janno columns: date type/C14/BC-AD derivation logic, `Location` (from Locality/Province), `Country_ISO` (via `country_converter`), `Source_Material` (from sample type), and Pandora tags/projects.

**`mt_results.py`**
`HumanMT_ResultsReader` — parses Human_MT pipeline `Results.txt` files and aggregates them to the library level (haplogroup, contamMix estimate/error, MT read counts/coverage). Handles the case where no MT results exist for a library (non-MT-capable analysis type, or missing sibling `Human_MT` directory) without raising or warning — that's an expected, common outcome, not a parsing failure.

**`library_results.py`**
`LibraryResultsAggregator` — builds the full library-level metrics table (damage, endogenous DNA, nuclear contamination, MT results) and aggregates it up to the sample level, including the NUC/MT contamination column-joining logic.

**`sample_results.py`**
`SampleResultsBuilder` — the top-level assembler for everything eager-derived: sex determination, SNP coverage, library naming/UDG/Genotyping_BAM, plus the library-level aggregates from `library_results.py`. Its `.build()` output is one row per sample, ready to be coalesced into the janno.

**`populate_janno.py`**
CLI argument parsing (`parse_args`) and `JannoPopulator`, the orchestrator that ties everything together: reads the janno, builds eager-derived sample results, queries and shapes Pandora metadata, coalesces both into the janno, finalizes computed columns, and returns the result for writing. `main()` is the actual CLI entry point.

**`__main__.py`**
Thin wrapper so `python -m populate_janno` works without needing to know the internal module name.

## Running the tests

```bash
pytest
```

The test suite mirrors the package structure (`tests/test_utils.py`, `tests/test_pandora_client.py`, `tests/test_mt_results.py`, etc.), and favors testing small, isolated methods/functions directly over spinning up full integration scenarios — most of the package's classes were specifically designed with this in mind, so most logic can be tested without a live database connection or real eager output directories on disk.

Useful flags during development:

```bash
pytest -v                          # verbose, one line per test
pytest -x                          # stop at first failure
pytest -k "weighted_mean"          # run tests matching a keyword
pytest --lf                        # re-run only last-failed tests
pytest --cov=populate_janno        # coverage report (requires pytest-cov)
```

## Known limitations / TODOs

- Human_MT results are only currently integrated for `RM`/`TM` analysis types (`config.MT_CAPABLE_ANALYSES`).
- A `Results.txt` missing some fields (e.g. contamMix not run) currently causes the *entire* row to fall back to all-NA rather than partially populating available fields — see inline comments in `mt_results.py::_read_one` if this needs relaxing.
