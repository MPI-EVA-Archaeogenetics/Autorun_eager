"""Reading, updating and writing a poseidon .janno file."""
import pandas as pd
from .config import JANNO_DTYPES, JANNO_OUTPUT_COLUMNS
from .utils import coalesce_dataframes


class JannoFile:
    def __init__(self, path: str):
        self.path = path
        self.df = pd.read_table(path, dtype=JANNO_DTYPES)

    def add_derived_id_columns(self, analysis_type: str) -> None:
        self.df["Eager_ID"] = self.df["Poseidon_ID"].str.replace(f".{analysis_type}", "")
        self.df["Individual_ID"] = self.df["Eager_ID"].str.replace(r"_ss", "")

    def coalesce(self, other: pd.DataFrame, key: str) -> None:
        self.df = coalesce_dataframes(self.df, other, key)

    def finalize(self, analysis_type: str, genotype_ploidy: str, eager_version: str) -> None:
        self.df["Group_Name"] = self.df["Group_Name"] + ";" + self.df["Group_Name"] + f".{analysis_type}"
        self.df["Genotype_Ploidy"] = genotype_ploidy
        suffix = f"/{eager_version}" if eager_version else ""
        self.df["Data_Preparation_Pipeline_URL"] = f"https://nf-co.re/eager{suffix}"

    def as_dataframe(self) -> pd.DataFrame:
        return self.df[JANNO_OUTPUT_COLUMNS]

    def write(self, output_path: str) -> None:
        self.as_dataframe().to_csv(output_path, sep="\t", na_rep="", mode="w", index=False)