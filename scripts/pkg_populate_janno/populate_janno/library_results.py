"""Builds per-library metric tables and aggregates them to the sample level."""
import numpy as np
import pandas as pd
import pyEager

from .eager_run import EagerRun
from .mt_results import HumanMTResultsReader
from .utils import weighted_mean, join_non_missing_strings, longest_non_null_string


class LibraryResultsAggregator:
    def __init__(self, eager_run: EagerRun, contamination_snp_cutoff: int = 100):
        self.eager_run = eager_run
        self.contamination_snp_cutoff = contamination_snp_cutoff
        self.mt_reader = HumanMTResultsReader(eager_run.analysis_type)

    def _damage_table(self) -> pd.DataFrame:
        table = pyEager.wrappers.compile_damage_table(self.eager_run.damage_json_paths())
        table["Library_ID"] = table["id"].str.replace(r"_rmdup", "").str.replace(r".bam", "")
        return table[["Library_ID", "n_reads", "dmg_5p_1bp"]].rename(columns={"dmg_5p_1bp": "damage"})

    def _endogenous_table(self) -> pd.DataFrame:
        table = pyEager.wrappers.compile_endogenous_table(self.eager_run.endorspy_json_paths())
        if table.empty:
            print(f"[LibraryResultsAggregator]: No endogenous table found for {self.eager_run.ind_id}.")
            table = pd.DataFrame(columns=["id", "endogenous_dna"])
        return table[["id", "endogenous_dna"]].rename(columns={"id": "Library_ID", "endogenous_dna": "endogenous"})

    def _contamination_table(self) -> pd.DataFrame:
        table = pyEager.parsers.parse_nuclear_contamination_json(self.eager_run.nuclear_contamination_json_path())
        table = table[["id", "Num_SNPs", "Method1_ML_estimate", "Method1_ML_SE"]].rename(columns={
            "id": "Library_ID", "Num_SNPs": "Contamination_Nr_SNPs",
            "Method1_ML_estimate": "Contamination_Est", "Method1_ML_SE": "Contamination_SE",
        })
        table["Contamination_Est"] = pd.to_numeric(table["Contamination_Est"], errors="coerce")
        table["Contamination_SE"] = pd.to_numeric(table["Contamination_SE"], errors="coerce")
        return table

    def library_level_table(self) -> pd.DataFrame:
        mt_table = self.mt_reader.build_library_table(self.eager_run.tsv_table)
        table = (
            self._damage_table()
            .merge(self._endogenous_table(), on="Library_ID", validate="one_to_one")
            .merge(self._contamination_table(), on="Library_ID", validate="one_to_one")
            .merge(mt_table, on="Library_ID", validate="many_to_one")
        )
        table["Sample_Name"] = table["Library_ID"].str.replace(r".[A-Z][0-9]{4}$", "", regex=True)
        table["NUC_Contamination_Meas"] = np.where(table["Contamination_Nr_SNPs"] >= 100, "ANGSD", pd.NA)
        table["MT_Contamination_Meas"] = np.where(pd.notna(table["Contammix_Est"]), "ContamMix", pd.NA)
        return table

    def aggregate_to_sample_level(self, lib_results: pd.DataFrame) -> pd.DataFrame:
        samples = pd.DataFrame({"Sample_Name": lib_results["Sample_Name"].unique()})
        merge_in = lambda new: new.merge(samples, on="Sample_Name", validate="one_to_one")

        samples = merge_in(
            lib_results
            .groupby("Sample_Name")["endogenous"]
            .apply(np.maximum.reduce)
            .apply(lambda x: round(x / 100, 3))
            .reset_index()
            .rename(columns={"endogenous": "Endogenous"})
        )
        samples = merge_in(
            lib_results
            .groupby("Sample_Name")[["damage", "n_reads"]]
            .apply(weighted_mean, wt_col="n_reads", val_col="damage", filter_col="n_reads", min_val=0)
            .apply(lambda x: round(x, 3))
            .reset_index()
            .rename(columns={0: "Damage"})
        )
        samples = merge_in(
            lib_results
            .groupby("Sample_Name")[["Contamination_Nr_SNPs", "Contamination_Est", "n_reads"]]
            .apply(weighted_mean, wt_col="n_reads", val_col="Contamination_Est",
                   filter_col="Contamination_Nr_SNPs", min_val=self.contamination_snp_cutoff)
            .apply(lambda x: round(x, 3)).reset_index().rename(columns={0: "NUC_Contamination"})
        )
        samples = merge_in(
            lib_results
            .groupby("Sample_Name")[["Contamination_Nr_SNPs", "Contamination_SE", "n_reads"]]
            .apply(weighted_mean, wt_col="n_reads", val_col="Contamination_SE",
                   filter_col="Contamination_Nr_SNPs", min_val=self.contamination_snp_cutoff)
            .apply(lambda x: round(x, 5))
            .reset_index()
            .rename(columns={0: "NUC_Contamination_Err"})
        )
        samples = merge_in(
            lib_results
            .groupby("Sample_Name")[["Contammix_Est", "n_mt_reads"]]
            .apply(weighted_mean, wt_col="n_mt_reads", val_col="Contammix_Est", filter_col="n_mt_reads", min_val=0)
            .apply(lambda x: round(x, 3))
            .reset_index()
            .rename(columns={0: "MT_Contamination"})
        )
        samples = merge_in(
            lib_results
            .groupby("Sample_Name")[["Contammix_Err", "n_mt_reads"]]
            .apply(weighted_mean, wt_col="n_mt_reads", val_col="Contammix_Err", filter_col="n_mt_reads", min_val=0)
            .apply(lambda x: round(x, 5))
            .reset_index()
            .rename(columns={0: "MT_Contamination_Err"})
        )
        samples = merge_in(
            lib_results.astype("string")
            .groupby("Sample_Name")[["Contamination_Nr_SNPs"]]
            .agg(lambda x: (
                f"Nr Snps (per library): {';'.join(x)}. Estimate and error are weighted means of values per "
                f"library. Libraries with fewer than {self.contamination_snp_cutoff} SNPs used in contamination "
                "estimation were excluded."
            )).rename(columns={"Contamination_Nr_SNPs": "NUC_Contamination_Note"})
            .reset_index()
        )
        samples = merge_in(
            lib_results
            .groupby("Sample_Name")[["NUC_Contamination_Meas"]]
            .agg(lambda x: pd.NA if x.isna().all() else "ANGSD")
            .reset_index()
        )
        samples = merge_in(
            lib_results
            .groupby("Sample_Name")[["MT_Contamination_Meas"]]
            .agg(lambda x: pd.NA if x.isna().all() else "ContamMix")
            .reset_index()
        )
        samples = merge_in(
            lib_results
            .groupby("Sample_Name")[["MT_Contamination_Meas"]]
            .agg(lambda x: "mtDNA contamination is based on Human_MT pipeline results. Estimate and error are "
                           "weighted means of values per runlet.")
            .rename(columns={"MT_Contamination_Meas": "MT_Contamination_Note"})
            .reset_index()
        )
        samples = merge_in(
            lib_results
            .groupby("Sample_Name")["MT_Haplogroup"]
            .apply(longest_non_null_string)
            .reset_index(name="MT_Haplogroup")
        )
        samples = merge_in(
                    lib_results
                    .groupby("Sample_Name")["MT_Mean_Coverage"]
                    .apply(sum)
                    .reset_index(name="MT_Mean_Coverage")
        )
        return self._merge_nuc_and_mt_columns(samples)

    @staticmethod
    def _merge_nuc_and_mt_columns(samples: pd.DataFrame) -> pd.DataFrame:
        for col in samples.filter(like="NUC_").columns:
            new_col = col.removeprefix("NUC_")
            samples[new_col] = samples.apply(
                lambda row: join_non_missing_strings(
                    val1=row[col], val2=row[f"MT_{new_col}"],
                    filter_val1=row["NUC_Contamination_Meas"], filter_val2=row["MT_Contamination"],
                ), axis=1,
            )
        return samples.drop(columns=[
            "NUC_Contamination_Meas", "NUC_Contamination_Note", "NUC_Contamination_Err", "NUC_Contamination",
            "MT_Contamination_Meas", "MT_Contamination_Note", "MT_Contamination_Err", "MT_Contamination",
        ])

    def build(self) -> pd.DataFrame:
        return self.aggregate_to_sample_level(self.library_level_table())