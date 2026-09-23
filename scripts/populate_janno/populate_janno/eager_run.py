"""Represents a single eager run's inputs/outputs on disk."""
import os
import glob
import re
import warnings
import pandas as pd
import pyEager
import pyPandoraHelper as pH

from .config import AUTORUN_EAGER_ROOT, BAM_SEARCH_DIRS


class EagerRun:
    def __init__(self, ind_id: str, analysis_type: str, root: str = AUTORUN_EAGER_ROOT):
        self.ind_id = ind_id
        self.analysis_type = analysis_type
        self.site_id = pH.get_site_id(ind_id)
        self.result_dir = os.path.join(root, "eager_outputs", analysis_type, self.site_id, ind_id) + "/"
        self.tsv_path = os.path.join(root, "eager_inputs", analysis_type, self.site_id, ind_id, f"{ind_id}.tsv")
        self.version = self._read_version()
        self.tsv_table = self._read_tsv_table()

    def _read_version(self) -> str:
        versions_fn = os.path.join(self.result_dir, "pipeline_info", "software_versions.csv")
        if not os.path.exists(versions_fn):
            return ""
        with open(versions_fn) as f:
            for line in f:
                parts = line.strip().split()
                if parts and parts[0] == "nf-core/eager":
                    return parts[1].lstrip("v")
        return ""

    def _read_tsv_table(self) -> pd.DataFrame:
        table = pyEager.parsers.parse_eager_tsv(self.tsv_path)
        return pyEager.parsers.infer_merged_bam_names(table, run_trim_bam=True, skip_deduplication=False)

    def damage_json_paths(self):
        paths = glob.glob(os.path.join(self.result_dir, "mapdamage", "*"))
        if not paths:
            paths = glob.glob(os.path.join(self.result_dir, "damageprofiler", "*", "*.json"))
        return paths

    def endorspy_json_paths(self):
        # Endogenous DNA is always computed on SG data, regardless of analysis type.
        return glob.glob(
            os.path.join(self.result_dir, "endorspy", "*.json").replace(f"/{self.analysis_type}/", "/SG/")
        )

    def snp_coverage_json_paths(self):
        return glob.glob(os.path.join(self.result_dir, "genotyping", "*.json"))

    def sexdet_json_path(self):
        return os.path.join(self.result_dir, "sex_determination", "sexdeterrmine.json")

    def nuclear_contamination_json_path(self):
        return os.path.join(self.result_dir, "nuclear_contamination", "nuclear_contamination_mqc.json")

    def infer_absolute_bam_path(self, fn: str, dirs_to_check=BAM_SEARCH_DIRS):
        for d in dirs_to_check:
            candidate = os.path.join(self.result_dir, d, fn)
            ## Older results lack the _udg* in the file name. check for those too
            candidate2 = os.path.join(self.result_dir, d, re.sub('_udg[a-z]*\.', '.', fn))
            if os.path.exists(candidate):
                return candidate
            elif os.path.exists(candidate2):
                return candidate2
        warnings.warn(f"File {fn} not found anywhere within {self.result_dir}")
        return pd.NA