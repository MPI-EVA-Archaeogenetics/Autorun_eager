"""Assembles the full sample-level result table (sex det, SNP coverage, library
naming/UDG, and library-level metric aggregation)."""
import pandas as pd
import pyEager

from .eager_run import EagerRun
from .library_results import LibraryResultsAggregator


class SampleResultsBuilder:
    def __init__(self, eager_run: EagerRun, contamination_snp_cutoff: int = 100):
        self.eager_run = eager_run
        self.library_aggregator = LibraryResultsAggregator(eager_run, contamination_snp_cutoff)

    @staticmethod
    def _convert_to_poseidon_udg(row, udg_treatment_col="UDG_Treatment") -> str:
        udg_list = list(dict.fromkeys(row[udg_treatment_col].strip().split(";")))
        if len(udg_list) > 1:
            return "mixed"
        return {"none": "minus", "half": "half", "full": "plus"}.get(udg_list[0], "n/a")

    def _udg_table(self) -> pd.DataFrame:
        df = (
            self.eager_run.tsv_table[["Sample_Name", "Library_ID", "UDG_Treatment"]]
            .drop_duplicates()
            .groupby("Sample_Name")[["UDG_Treatment"]]
            .agg(lambda x: ";".join(x))
        )
        df["UDG"] = df.apply(self._convert_to_poseidon_udg, axis=1)
        return df

    def _library_built_table(self) -> pd.DataFrame:
        tsv = self.eager_run.tsv_table
        table = tsv[["Sample_Name", "Library_ID", "additional_bam_name"]].copy()
        table["Library_ID"] = table["Library_ID"].str.replace(r"_ss", "")
        table["Genotyping_BAM"] = table.apply(
            lambda row: self.eager_run.infer_absolute_bam_path(row.additional_bam_name), axis=1
        )
        table = (
            table.drop_duplicates()
            .groupby(["Sample_Name", "Genotyping_BAM"])[["Library_ID"]]
            .agg(lambda x: ";".join(x))
            .rename(columns={"Library_ID": "Library_Names"})
            .reset_index()
        )
        table["Nr_Libraries"] = table["Library_Names"].str.count(";") + 1
        table["Library_Built"] = table["Sample_Name"].apply(lambda s: "ss" if str(s).endswith("_ss") else "ds")
        table = self._udg_table().filter(["Sample_Name", "UDG"]).merge(table, on="Sample_Name", validate="one_to_one")
        return (
            tsv[["Sample_Name", "BAM"]]
            .assign(BAM=lambda d: d["BAM"].str.rsplit("/", n=1).str[-1].str.removesuffix(".bam"))
            .groupby("Sample_Name")[["BAM"]].agg(lambda x: ";".join(x))
            .rename(columns={"BAM": "Included_Seq_IDs"}).reset_index()
            .merge(table, on="Sample_Name", validate="one_to_one")
        )

    def _snp_coverage_table(self) -> pd.DataFrame:
        return (
            pyEager.wrappers.compile_snp_coverage_table(self.eager_run.snp_coverage_json_paths())
            .drop("Total_Snps", axis=1)
            .rename(columns={"id": "Sample_Name", "Covered_Snps": "Nr_SNPs"})
        )

    def _sex_determination_table(self) -> pd.DataFrame:
        table = pyEager.parsers.parse_sexdeterrmine_json(self.eager_run.sexdet_json_path())
        rate_cols = ["RateX", "RateY", "RateErrX", "RateErrY"]
        table[rate_cols] = table[rate_cols].apply(lambda x: round(pd.to_numeric(x, errors="coerce"), 5))
        table = table.rename(columns={"id": "sexdet_bam_name"}).merge(
            self.eager_run.tsv_table.filter(["Sample_Name", "sexdet_bam_name"]).drop_duplicates(),
            on="sexdet_bam_name", validate="one_to_one",
        )
        return table[["Sample_Name", "RateX", "RateY", "RateErrX", "RateErrY"]]

    def build(self) -> pd.DataFrame:
        return (
            self._sex_determination_table()
            .merge(self._snp_coverage_table(), on="Sample_Name", validate="one_to_one")
            .merge(self._library_built_table(), on="Sample_Name", validate="one_to_one")
            .merge(self.library_aggregator.build(), on="Sample_Name", validate="one_to_one")
            .rename(columns={"Sample_Name": "Eager_ID"})
        )