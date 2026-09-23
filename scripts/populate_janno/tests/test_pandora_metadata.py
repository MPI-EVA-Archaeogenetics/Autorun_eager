"""Tests for functions and column derivation logic in pandora_metadata.py."""
import pandas as pd
import pytest

from populate_janno.pandora_metadata import PandoraIndividualMetadata

from populate_janno.pandora_metadata import (
    _bam_path_to_raw_data_id, derive_raw_data_ids, PandoraRawDataMetadata,
)

def _row(**overrides):
    """Build a row with all expected keys defaulting to pd.NA, overridden as needed."""
    base = {
        "individual.C14_Uncalibrated": pd.NA,
        "individual.C14_Uncalibrated_Variation": pd.NA,
        "individual.C14_Calibrated_From": pd.NA,
        "individual.C14_Calibrated_To": pd.NA,
        "individual.C14_Calibrated_Mean": pd.NA,
        "individual.C14_Calibration_Reservoir_Offset": pd.NA,
        "individual.C14_Info": pd.NA,
        "individual.C14_Id": pd.NA,
        "individual.C14_Id_Lab": pd.NA,
        "individual.Archaeological_Date_From": pd.NA,
        "individual.Archaeological_Date_To": pd.NA,
        "site.Date_From": pd.NA,
        "site.Date_To": pd.NA,
    }
    base.update(overrides)
    return pd.Series(base)


class TestDetermineDateType:
    def test_c14_when_uncalibrated_present_and_nonzero(self):
        row = _row(**{"individual.C14_Uncalibrated": 4500})
        assert PandoraIndividualMetadata._determine_date_type(row) == "C14"

    def test_c14_uncalibrated_zero_is_treated_as_missing(self):
        row = _row(**{
            "individual.C14_Uncalibrated": 0,
            "individual.Archaeological_Date_From": -2000,
        })
        assert PandoraIndividualMetadata._determine_date_type(row) == "contextual"

    def test_contextual_when_archaeological_date_present(self):
        row = _row(**{"individual.Archaeological_Date_From": -1000})
        assert PandoraIndividualMetadata._determine_date_type(row) == "contextual"

    def test_contextual_when_only_site_date_present(self):
        row = _row(**{"site.Date_From": -500})
        assert PandoraIndividualMetadata._determine_date_type(row) == "contextual"

    def test_na_when_nothing_present(self):
        assert pd.isna(PandoraIndividualMetadata._determine_date_type(_row()))


class TestDetermineC14Labnr:
    def test_combines_lab_and_id_when_both_present(self):
        row = _row(**{
            "individual.C14_Uncalibrated": 4500,
            "individual.C14_Id_Lab": "OxA",
            "individual.C14_Id": "12345",
        })
        assert PandoraIndividualMetadata._determine_c14_labnr(row) == "OxA-12345"

    def test_returns_id_only_when_lab_missing(self):
        row = _row(**{
            "individual.C14_Uncalibrated": 4500,
            "individual.C14_Id": "OxA-12345",
        })
        assert PandoraIndividualMetadata._determine_c14_labnr(row) == "OxA-12345"

    def test_na_when_no_uncalibrated_date(self):
        row = _row(**{"individual.C14_Id": "OxA-12345"})
        assert pd.isna(PandoraIndividualMetadata._determine_c14_labnr(row))


class TestDetermineBcAdDates:
    def test_uses_calibrated_range_when_available(self):
        row = _row(**{
            "individual.C14_Uncalibrated": 4500,
            "individual.C14_Calibrated_From": -3300,
            "individual.C14_Calibrated_To": -3000,
            "individual.C14_Calibrated_Mean": -3150,
        })
        start, median, stop = PandoraIndividualMetadata._determine_bc_ad_dates(row)
        assert (start, median, stop) == (-3300, -3150, -3000)

    def test_excludes_one_sigma_calibrated_dates(self):
        row = _row(**{
            "individual.C14_Uncalibrated": 4500,
            "individual.C14_Calibrated_From": -3300,
            "individual.C14_Calibrated_To": -3000,
            "individual.C14_Info": "reported at 1 sigma",
        })
        start, median, stop = PandoraIndividualMetadata._determine_bc_ad_dates(row)
        assert pd.isna(start) and pd.isna(median) and pd.isna(stop)

    def test_falls_back_to_archaeological_dates(self):
        row = _row(**{
            "individual.Archaeological_Date_From": -2000,
            "individual.Archaeological_Date_To": -1000,
        })
        start, median, stop = PandoraIndividualMetadata._determine_bc_ad_dates(row)
        assert (start, median, stop) == (-2000, -1500, -1000)

    def test_falls_back_to_site_dates_last(self):
        row = _row(**{"site.Date_From": -500, "site.Date_To": -100})
        start, median, stop = PandoraIndividualMetadata._determine_bc_ad_dates(row)
        assert (start, median, stop) == (-500, -300, -100)

    def test_all_na_when_nothing_available(self):
        start, median, stop = PandoraIndividualMetadata._determine_bc_ad_dates(_row())
        assert pd.isna(start) and pd.isna(median) and pd.isna(stop)


class TestDetermineLocation:
    def test_combines_locality_and_province_with_comma_separator(self):
        row = pd.Series({"site.Locality": "Somewhere", "site.Province": "Somewhereshire"})
        assert PandoraIndividualMetadata._determine_location(row) == "Somewhere, Somewhereshire"

    def test_returns_locality_only_when_province_is_placeholder(self):
        row = pd.Series({"site.Locality": "Somewhere", "site.Province": "NA"})
        assert PandoraIndividualMetadata._determine_location(row) == "Somewhere"

    def test_returns_province_only_when_locality_is_placeholder(self):
        row = pd.Series({"site.Locality": "None", "site.Province": "Bavaria"})
        assert PandoraIndividualMetadata._determine_location(row) == "Bavaria"

    def test_na_when_both_missing_or_placeholders(self):
        row = pd.Series({"site.Locality": "na", "site.Province": pd.NA})
        assert pd.isna(PandoraIndividualMetadata._determine_location(row))



class TestBamPathToRawDataId:
    def test_converts_bam_path_to_expected_raw_data_id(self):
        result = _bam_path_to_raw_data_id("/mnt/archgen/.../AAR001.A0101.RM1.1.bam")
        assert result == "AAR001.A0101.RM1.1.Data"

    def test_handles_bare_filename(self):
        assert _bam_path_to_raw_data_id("AAR001.A0101.RM1.1.bam") == "AAR001.A0101.RM1.1.Data"


class TestDeriveRawDataIds:
    def test_deduplicates_and_converts(self):
        tsv_table = pd.DataFrame({
            "BAM": [
                "/a/AAR001.A0101.RM1.1.bam",
                "/a/AAR001.A0101.RM1.1.bam",
                "/a/AAR001.A0102.RM1.1.bam",
            ]
        })
        assert sorted(derive_raw_data_ids(tsv_table)) == [
            "AAR001.A0101.RM1.1.Data", "AAR001.A0102.RM1.1.Data",
        ]

    def test_returns_empty_list_when_all_missing(self):
        tsv_table = pd.DataFrame({"BAM": [pd.NA, pd.NA]})
        assert derive_raw_data_ids(tsv_table) == []


class TestClassifyPublicationStatus:
    def test_all_present_is_yes(self):
        assert PandoraRawDataMetadata._classify_publication_status(pd.Series(["10.1/a", "10.1/b"])) == "yes"

    def test_all_missing_is_no(self):
        assert PandoraRawDataMetadata._classify_publication_status(pd.Series([pd.NA, ""])) == "no"

    def test_mixed_is_partial(self):
        assert PandoraRawDataMetadata._classify_publication_status(pd.Series(["10.1/a", pd.NA])) == "partial"


class TestPandoraRawDataMetadataBuild:
    def test_full_pipeline_produces_expected_statuses(self):
        tsv_table = pd.DataFrame({
            "Sample_Name": ["SAMPLE1", "SAMPLE1", "SAMPLE2", "SAMPLE3"],
            "BAM": [
                "/a/SAMPLE1.A0101.RM1.1.bam", "/a/SAMPLE1.A0102.RM1.1.bam",  # SAMPLE1: two libraries
                "/a/SAMPLE2.A0101.RM1.1.bam",                                 # SAMPLE2: one library
                "/a/SAMPLE3.A0101.RM1.1.bam",                                 # SAMPLE3: no match in Pandora
            ],
        })
        raw = pd.DataFrame({
            "raw_data.Full_Raw_Data_Id": [
                "SAMPLE1.A0101.RM1.1.Data",
                "SAMPLE1.A0102.RM1.1.Data",
                "SAMPLE2.A0101.RM1.1.Data",
            ],
            "raw_data.DOI": ["10.1/a", pd.NA, "10.1/c"],
        })

        result = PandoraRawDataMetadata(raw, tsv_table).build().set_index("Sample_Name")

        assert result.loc["SAMPLE1", "Publication_Status"] == "partial"
        assert result.loc["SAMPLE2", "Publication_Status"] == "yes"
        assert result.loc["SAMPLE3", "Publication_Status"] == "no"