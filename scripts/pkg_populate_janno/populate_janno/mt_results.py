"""Parsing and aggregation of Human_MT pipeline `Results.txt` files."""
import os
import warnings
import numpy as np
import pandas as pd

from .config import MT_CAPABLE_ANALYSES
from .utils import weighted_mean, longest_non_null_string


class HumanMTResultsReader:
    RENAME_COLUMNS = {
        "reads aligned to MT with MQ >= 25": "n_mt_reads",
        "HaploGrep3 haplogroup assignment": "MT_Haplogroup",
        "contamMix contamination estimate [%]": "Contammix_Est",
        "contamMix contamination lower boundary of 95% CI [%]": "Contammix_Est_Lower",
        "contamMix contamination upper boundary of 95% CI [%]": "Contammix_Est_Upper",
        "mean sequencing depth": "MT_Mean_Coverage",
    }
    KEEP_COLUMNS = {
        "mt_results_path": str,
        "n_mt_reads": int,
        "MT_Haplogroup": str,
        "Contammix_Est": np.float32,
        "Contammix_Est_Lower": np.float64,
        "Contammix_Est_Upper": np.float64,
        "MT_Mean_Coverage": np.float64,
    }

    def __init__(self, analysis_type: str):
        self.analysis_type = analysis_type

    def _infer_results_path(self, bam_path: str):
        if not os.path.exists(bam_path):
            warnings.warn(f"Inferred results file not found: {bam_path}")
            return pd.NA
        if self.analysis_type in MT_CAPABLE_ANALYSES:
            mt_fn = os.path.dirname(bam_path).replace(f"Human_{self.analysis_type}", "Human_MT") + "/Results.txt"
            if os.path.exists(mt_fn):
                return mt_fn
        return pd.NA

    @staticmethod
    def _read_results_txt(fn: str) -> pd.DataFrame:
        data = {}
        with open(fn, "r") as f:
            for line in f:
                if line.startswith("@FILE@"):
                    continue
                key, value = line.split("\t")
                try:
                    data[key.strip()] = pd.to_numeric(value.strip())
                except Exception:
                    data[key.strip()] = value.strip()
        df = pd.DataFrame([data]).assign(mt_results_path=fn)
        for col in df.filter(regex=r'\[%\]$').columns:
            try:
                df[col] = df[col].div(100)
            except Exception:
                pass
        return df

    @staticmethod
    def _contammix_error(median, upper, lower) -> float:
        if pd.isna(median):
            return np.nan
        return max(abs(median - upper), abs(median - lower))

    def _fallback_result(self, fn) -> dict:
        """A dict with all KEEP_COLUMNS keys, using NA/NaN as appropriate per dtype,
        plus a Contammix_Err key to match the shape of a successfully parsed result."""
        result = {c: (np.nan if t is np.float32 else pd.NA) for c, t in self.KEEP_COLUMNS.items()}
        result["mt_results_path"] = fn
        result["Contammix_Err"] = np.nan
        return result

    def _read_one(self, fn) -> dict:
        """
        Return a dict of parsed MT-result fields (plus a computed Contammix_Err) for
        a single inferred results path.

        If `fn` is NA -- meaning no results file could be located, e.g. because the
        sample's analysis type doesn't support MT capture, or no sibling Human_MT
        directory was found -- this returns an all-NA fallback silently. This is an
        expected, common situation, not a parsing failure, so no warning is raised.

        If `fn` is a real path but parsing still fails, the same fallback shape is
        used, but a warning IS raised, since that indicates an unexpected problem
        with a file that should have been readable.
        """
        if pd.isna(fn):
            return self._fallback_result(fn)

        try:
            mt_results = self._read_results_txt(fn).rename(columns=self.RENAME_COLUMNS)
            mt_results = mt_results[self.KEEP_COLUMNS.keys()].astype(self.KEEP_COLUMNS)
            result = mt_results.iloc[0].to_dict()
        except Exception:
            warnings.warn(f"Incorporation of mt results failed from: '{fn}'  ({type(e).__name__}: {e})")
            return self._fallback_result(fn)

        result["Contammix_Err"] = self._contammix_error(
            result.get("Contammix_Est"),
            result.get("Contammix_Est_Upper"),
            result.get("Contammix_Est_Lower"),
        )
        return result

    def build_library_table(self, tsv_table: pd.DataFrame) -> pd.DataFrame:
        """Return one aggregated MT-results row per Library_ID."""
        df = tsv_table.copy()
        df["mt_results_path"] = df["BAM"].apply(self._infer_results_path)

        # Build one result-dict per row (via _read_one), then assemble a DataFrame
        # directly from that list of dicts -- aligned positionally by df.index.
        # This intentionally avoids pd.concat()/merge() on `mt_results_path`,
        # since that column can validly be NA (or repeated) across multiple rows
        # simultaneously, which is unsafe to join/concat on.
        results_list = df["mt_results_path"].apply(self._read_one).tolist()
        per_row_results = pd.DataFrame(results_list, index=df.index)

        df = pd.concat([df, per_row_results.drop(columns="mt_results_path")], axis=1)
        df = df.filter(["Library_ID", "n_mt_reads", "MT_Haplogroup", "MT_Mean_Coverage", "Contammix_Est", "Contammix_Err"])

        return (
            df.groupby("Library_ID")
            .apply(lambda g: pd.Series({
                "n_mt_reads": g["n_mt_reads"].sum(),
                "MT_Mean_Coverage": g["MT_Mean_Coverage"].sum(),
                "MT_Haplogroup": longest_non_null_string(g["MT_Haplogroup"]),
                "Contammix_Est": weighted_mean(g, wt_col="n_mt_reads", val_col="Contammix_Est", filter_col="n_mt_reads", min_val=0),
                "Contammix_Err": weighted_mean(g, wt_col="n_mt_reads", val_col="Contammix_Err", filter_col="n_mt_reads", min_val=0),
            }), include_groups=False)
            .reset_index()
        )