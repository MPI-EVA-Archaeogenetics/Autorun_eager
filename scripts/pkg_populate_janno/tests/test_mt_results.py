"""Tests for Human_MT Results.txt parsing/aggregation."""
import textwrap
import numpy as np
import pandas as pd
import pytest

from populate_janno.mt_results import HumanMTResultsReader


@pytest.fixture
def results_txt(tmp_path):
    """Write a minimal, realistic Human_MT Results.txt file."""
    content = textwrap.dedent("""\
        @FILE@\t/some/path/to/bam
        reads aligned to MT with MQ >= 25\t1000
        HaploGrep3 haplogroup assignment\tH2a1
        contamMix contamination estimate [%]\t2.5
        contamMix contamination lower boundary of 95% CI [%]\t1.0
        contamMix contamination upper boundary of 95% CI [%]\t4.0
        mean sequencing depth\t120.4
    """)
    path = tmp_path / "Results.txt"
    path.write_text(content)
    return str(path)


class TestReadResultsTxt:
    def test_parses_expected_fields(self, results_txt):
        df = HumanMTResultsReader._read_results_txt(results_txt)
        assert df.loc[0, "reads aligned to MT with MQ >= 25"] == 1000
        assert df.loc[0, "HaploGrep3 haplogroup assignment"] == "H2a1"

    def test_converts_percent_columns_to_proportions(self, results_txt):
        df = HumanMTResultsReader._read_results_txt(results_txt)
        assert df.loc[0, "contamMix contamination estimate [%]"] == pytest.approx(0.025)

    def test_records_source_path(self, results_txt):
        df = HumanMTResultsReader._read_results_txt(results_txt)
        assert df.loc[0, "mt_results_path"] == results_txt


class TestContammixError:
    def test_computes_max_absolute_deviation(self):
        result = HumanMTResultsReader._contammix_error(median=0.05, upper=0.09, lower=0.03)
        assert result == pytest.approx(0.04)  # max(|0.05-0.09|, |0.05-0.03|)

    def test_returns_nan_when_median_missing(self):
        result = HumanMTResultsReader._contammix_error(median=pd.NA, upper=0.09, lower=0.03)
        assert pd.isna(result)


class TestInferResultsPath:
    def test_returns_na_for_non_mt_capable_analysis(self, tmp_path):
        bam = tmp_path / "results" / "Human_TF" / "sample" / "out.bam"
        bam.parent.mkdir(parents=True)
        bam.touch()
        reader = HumanMTResultsReader(analysis_type="TF")
        assert pd.isna(reader._infer_results_path(str(bam)))

    def test_finds_sibling_mt_results_for_capable_analysis(self, tmp_path):
        rm_dir = tmp_path / "Human_RM" / "sample"
        rm_dir.mkdir(parents=True)
        bam = rm_dir / "out.bam"
        bam.touch()
        mt_dir = tmp_path / "Human_MT" / "sample"
        mt_dir.mkdir(parents=True)
        (mt_dir / "Results.txt").touch()

        reader = HumanMTResultsReader(analysis_type="RM")
        found = reader._infer_results_path(str(bam))
        assert found == str(mt_dir / "Results.txt")

    def test_returns_na_if_bam_path_itself_missing(self, tmp_path):
        reader = HumanMTResultsReader(analysis_type="RM")
        missing_bam = tmp_path / "does_not_exist.bam"
        
        with pytest.warns(UserWarning, match="Inferred results file not found"):
            ## Ignore expected warning
            result = reader._infer_results_path(str(missing_bam))
        assert pd.isna(result)

    def test_returns_na_if_sibling_mt_results_missing(self, tmp_path):
        rm_dir = tmp_path / "Human_RM" / "sample"
        rm_dir.mkdir(parents=True)
        bam = rm_dir / "out.bam"
        bam.touch()
        # Note: no Human_MT sibling directory created

        reader = HumanMTResultsReader(analysis_type="RM")
        assert pd.isna(reader._infer_results_path(str(bam)))


class TestBuildLibraryTable:
    def test_handles_all_missing_mt_results_without_raising(self, mocker):
        reader = HumanMTResultsReader(analysis_type="TF")
        tsv_table = pd.DataFrame({
            "Library_ID": ["LIB1.A0101", "LIB1.A0102"],
            "BAM": ["/some/path/one.bam", "/some/path/two.bam"],
        })
        mocker.patch.object(reader, "_infer_results_path", autospec=True, return_value=pd.NA)

        result = reader.build_library_table(tsv_table)

        assert set(result["Library_ID"]) == {"LIB1.A0101", "LIB1.A0102"}
        assert result["MT_Haplogroup"].isna().all()
        assert result["Contammix_Est"].isna().all()
        assert result["Contammix_Err"].isna().all()

    def test_handles_mixed_present_and_missing_mt_results(self, mocker, tmp_path):
        reader = HumanMTResultsReader(analysis_type="RM")
        tsv_table = pd.DataFrame({
            "Library_ID": ["LIB1.A0101", "LIB2.A0101"],
            "BAM": ["/path/lib1.bam", "/path/lib2.bam"],
        })
        results_file = tmp_path / "Results.txt"
        results_file.write_text(
            "reads aligned to MT with MQ >= 25\t500\n"
            "HaploGrep3 haplogroup assignment\tH2a1\n"
            "contamMix contamination estimate [%]\t2.0\n"
            "contamMix contamination lower boundary of 95% CI [%]\t1.0\n"
            "contamMix contamination upper boundary of 95% CI [%]\t3.0\n"
            "mean sequencing depth\t80.0\n"
        )
        mocker.patch.object(reader, "_infer_results_path", autospec=True, side_effect=[str(results_file), pd.NA])

        result = reader.build_library_table(tsv_table)
        result = result.set_index("Library_ID")

        assert result.loc["LIB1.A0101", "MT_Haplogroup"] == "H2a1"
        assert pd.isna(result.loc["LIB2.A0101", "MT_Haplogroup"])
