#!/usr/bin/env python
"""CLI entry point tying eager + Pandora results into an updated janno file."""
import argparse
import sys
import pandas as pd

from .config import VERSION, CONTAMINATION_SNP_CUTOFF_DEFAULT, GENOTYPE_PLOIDY_DEFAULT
from .janno import JannoFile
from .eager_run import EagerRun
from .pandora_client import PandoraClient
from .pandora_metadata import PandoraIndividualMetadata, PandoraRawDataMetadata, derive_raw_data_ids
from .sample_results import SampleResultsBuilder


def parse_args(cli_args=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="populate_janno", description="...")
    parser.add_argument("-i", "--ind_id", required=True)
    parser.add_argument("-a", "--analysis_type", required=True, choices=["SG", "TF", "TM", "RP", "RM"])
    parser.add_argument("-j", "--janno", required=True)
    parser.add_argument("-c", "--credentials", required=True)
    parser.add_argument("-s", "--contamination_snp_cutoff", type=int, default=CONTAMINATION_SNP_CUTOFF_DEFAULT)
    parser.add_argument("-p", "--genotype_ploidy", default=GENOTYPE_PLOIDY_DEFAULT)
    parser.add_argument("--safe", action="store_true")
    parser.add_argument("-v", "--version", action="version", version=VERSION)
    return parser.parse_args(cli_args)


class JannoPopulator:
    """Orchestrates: read janno -> gather eager metrics -> gather Pandora metadata -> merge -> write."""

    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.eager_run = EagerRun(args.ind_id, args.analysis_type)
        self.janno = JannoFile(args.janno)
        self.pandora_client = PandoraClient(args.credentials)

    def _fetch_pandora_individual_metadata(self) -> pd.DataFrame:
        individual_id = self.janno.df["Individual_ID"].iloc[0]
        raw = self.pandora_client.query(filter_values=individual_id).replace("", pd.NA)
        raw = raw[~raw["sample.Ethically_culturally_sensitive"].str.startswith("Yes", na=False)]
        return PandoraIndividualMetadata(raw).build()

    def _fetch_publication_status(self) -> pd.DataFrame:
        """
        Returns one row per Sample_Name (renamed to Eager_ID to match the
        janno's merge key), with a Publication_Status column derived from
        Pandora's TAB_Raw_Data DOI entries.
        """
        tsv_table = self.eager_run.tsv_table
        raw_data_ids = derive_raw_data_ids(tsv_table)
        if raw_data_ids:
            raw = self.pandora_client.query_raw_data(raw_data_ids)
        else:
            raw = pd.DataFrame(columns=["raw_data.Full_Raw_Data_Id", "raw_data.DOI"])
        result = PandoraRawDataMetadata(raw, tsv_table).build()
        return result.rename(columns={"Sample_Name": "Eager_ID"})

    def run(self) -> pd.DataFrame:
        print(f"[populate_janno]: Starting v{VERSION} for {self.args.ind_id} "
            f"({self.args.analysis_type})", file=sys.stderr)

        self.janno.add_derived_id_columns(self.args.analysis_type)

        sample_results = SampleResultsBuilder(self.eager_run, self.args.contamination_snp_cutoff).build()
        publication_status = self._fetch_publication_status()
        sample_results = sample_results.merge(publication_status, on="Eager_ID", validate="one_to_one")

        individual_results = self._fetch_pandora_individual_metadata()

        self.janno.coalesce(sample_results, "Eager_ID")
        self.janno.coalesce(individual_results, "Individual_ID")
        self.janno.finalize(self.args.analysis_type, self.args.genotype_ploidy, self.eager_run.version)

        return self.janno.as_dataframe()

    @property
    def output_path(self) -> str:
        return self.args.janno + ".new" if self.args.safe else self.args.janno


def main(cli_args=None):
    args = parse_args(cli_args)
    populator = JannoPopulator(args)
    populator.run()
    populator.janno.write(populator.output_path)


if __name__ == "__main__":
    main()