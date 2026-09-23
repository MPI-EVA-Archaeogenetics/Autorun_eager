"""Transforms a raw Pandora query result into poseidon-ready individual-level metadata."""
import numpy as np
import pandas as pd
import country_converter as coco

from .utils import cast_to_int64
from .utils import clean_placeholder_string
from .utils import join_non_missing_strings

PANDORA_COLUMNS = [
    'individual.Full_Individual_Id',
    'individual.Provenience',
    'individual.Archaeological_ID', 
    'individual.Archaeological_Date_From',
    'individual.Archaeological_Date_To',
    'individual.Archaeological_Date_Info',
    'individual.C14_Uncalibrated',
    'individual.C14_Uncalibrated_Variation',
    'individual.C14_Calibrated_From',
    'individual.C14_Calibrated_To',
    'individual.C14_Calibrated_Mean',
    'individual.C14_Calibration_Software',
    'individual.C14_Calibration_Curve',
    'individual.C14_Calibration_Reservoir_Offset',
    'individual.C14_Info',
    'individual.C14_Id_Lab',
    'individual.C14_Id',
    'site.Name',
    'site.Locality',
    'site.Province',
    'site.Country',
    'site.Latitude',
    'site.Longitude',
    'site.Date_From',
    'site.Date_To',
    'site.Date_Info',
]
POSEIDON_COLUMNS = [
    'Individual_ID',
    'Collection_ID',
    'Site',
    'Latitude',
    'Longitude',
    'Date_Type',
    'Date_C14_Labnr',
    'Date_C14_Uncal_BP',
    'Date_C14_Uncal_BP_Err',
    'Date_C14_Reservoir_Offset',
    'Date_BC_AD_Start',
    'Date_BC_AD_Median',
    'Date_BC_AD_Stop',
    'Date_Note',
    'Location',
    'Country',
    'Country_ISO',
    'Source_Material',
    'Pandora_Tags',
    'Pandora_Projects',
]

def _bam_path_to_raw_data_id(bam_path: str) -> str:
    """
    Convert an absolute BAM path to the exact Full_Raw_Data_Id Pandora is
    expected to have for it, e.g.:
        /mnt/archgen/.../AAR001.A0101.RM1.1.bam -> AAR001.A0101.RM1.1.Raw_Data
    """
    basename = bam_path.rsplit("/", 1)[-1].removesuffix(".bam")
    return f"{basename}.Data"


def derive_raw_data_ids(tsv_table: pd.DataFrame, bam_col: str = "BAM") -> list:
    """Derive unique, expected Full_Raw_Data_Id values from an eager TSV table's BAM column."""
    return (
        tsv_table[bam_col]
        .dropna()
        .apply(_bam_path_to_raw_data_id)
        .unique()
        .tolist()
    )


class PandoraIndividualMetadata:
    """Builds Date_*, Location, Country_ISO, Source_Material, Pandora_Tags/Projects columns."""

    def __init__(self, raw_pandora_results: pd.DataFrame):
        self.raw = raw_pandora_results

    @staticmethod
    def _determine_date_type(row):
        if pd.notna(row['individual.C14_Uncalibrated']) and not row['individual.C14_Uncalibrated'] == 0:
            return 'C14'
        elif pd.notna(row['individual.Archaeological_Date_From']) or pd.notna(row['site.Date_From']):
            return 'contextual'
        else:
            return pd.NA

    @staticmethod
    def _determine_c14_labnr(row):
        ## Only keep C14 IDs that are input in the Uncal date column.
        if pd.notna(row['individual.C14_Uncalibrated']) and not row['individual.C14_Uncalibrated'] == 0:
            if pd.notna(row['individual.C14_Id']) and pd.notna(row['individual.C14_Id_Lab']):
                return row['individual.C14_Id_Lab'] + "-" + row['individual.C14_Id']
            ## Sometimes the enire code is set in the ID column. in such cases, return only the lab ID
            elif pd.notna(row['individual.C14_Id']):
                return row['individual.C14_Id']
            else:
                return pd.NA
        else:
            return pd.NA

    @staticmethod
    def _determine_uncal_dates_and_reservoir(row):
        ## I am assuming only one value is in these fields, even when multiple dates are present.
        ## I think pandora only allows a single integer in the field anyway.
        if pd.notna(row['individual.C14_Uncalibrated']) and not row['individual.C14_Uncalibrated'] == 0:
            if pd.notna(row['individual.C14_Calibration_Reservoir_Offset']):
                reservoir_offset=row['individual.C14_Calibration_Reservoir_Offset']
            else:
                reservoir_offset=pd.NA
            return (
                cast_to_int64(row['individual.C14_Uncalibrated']),
                cast_to_int64(row['individual.C14_Uncalibrated_Variation']),
                cast_to_int64(reservoir_offset)
            )
        else:
            return (pd.NA, pd.NA, pd.NA)

    @staticmethod
    def _determine_bc_ad_dates(row):
        if pd.notna(row['individual.C14_Uncalibrated']) and not row['individual.C14_Uncalibrated'] == 0:
            ## If there are uncalibrated and calibrated dates, fill in from Pandora. 
            if pd.notna(row['individual.C14_Calibrated_From']) and pd.notna(row['individual.C14_Calibrated_To']):
                ## Rare cases where the Pandora values correspond to 1 sigma. These should be excluded as they do not conform to Poseidon schema.
                if pd.notna(row['individual.C14_Info']) and any(x in row['individual.C14_Info'].lower() for x in ["1 sigma", "1-sigma", "sigma1", "sigma 1", "sigma-1"]):
                    return ( cast_to_int64(pd.NA), cast_to_int64(pd.NA), cast_to_int64(pd.NA) )
                else:
                    ## If mean is missing in Pandora, leave blank. (Median can't be calculated without the distribution.)
                    if pd.notna(row['individual.C14_Calibrated_Mean']):
                        calibrated_mean=row['individual.C14_Calibrated_Mean']
                    else:
                        calibrated_mean=pd.NA
                    return (
                        cast_to_int64(row['individual.C14_Calibrated_From']),
                        cast_to_int64(calibrated_mean),
                        cast_to_int64(row['individual.C14_Calibrated_To'])
                    )
            else:
                ## If there are uncalibrated dates, but no calibrated ones, leave empty (should get quickcalibrated).
                return ( cast_to_int64(pd.NA), cast_to_int64(pd.NA), cast_to_int64(pd.NA) )
        elif pd.notna(row['individual.Archaeological_Date_From']) and pd.notna(row['individual.Archaeological_Date_To']):
            ## If the individual has Archaeological dates, use those.
            individual_mean = np.mean([row['individual.Archaeological_Date_From'], row['individual.Archaeological_Date_To']])
            return(
                cast_to_int64(row['individual.Archaeological_Date_From']),
                cast_to_int64(individual_mean),
                cast_to_int64(row['individual.Archaeological_Date_To'])
            )
        elif pd.notna(row['site.Date_From']) and pd.notna(row['site.Date_To']):
            ## If the site has a date range, use that.
            site_mean = np.mean([row['site.Date_From'], row['site.Date_To']])
            return(
                cast_to_int64(row['site.Date_From']),
                cast_to_int64(site_mean),
                cast_to_int64(row['site.Date_To'])
            )
        else:
            ## If all the above are missing, leave empty.
            return( cast_to_int64(pd.NA), cast_to_int64(pd.NA), cast_to_int64(pd.NA) )

    @staticmethod
    def _add_date_note(row):
        if pd.notna(row['individual.C14_Calibration_Curve']) and pd.notna(row['individual.C14_Calibration_Software']):
            return f"{row['individual.C14_Calibration_Curve']}, calibrated with {row['individual.C14_Calibration_Software']}"
        elif pd.notna(row['individual.C14_Calibration_Curve']):
            return f"{row['individual.C14_Calibration_Curve']}"
        else:
            return pd.NA

    def _add_date_columns(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()
        df["Date_Type"] = df.apply(self._determine_date_type, axis=1)
        df["Date_C14_Labnr"] = df.apply(self._determine_c14_labnr, axis=1)
        df[["Date_C14_Uncal_BP", "Date_C14_Uncal_BP_Err", "Date_C14_Reservoir_Offset"]] = df.apply(
            self._determine_uncal_dates_and_reservoir, axis=1, result_type="expand"
        )
        df[["Date_BC_AD_Start", "Date_BC_AD_Median", "Date_BC_AD_Stop"]] = df.apply(
            self._determine_bc_ad_dates, axis=1, result_type="expand"
        )
        df["Date_Note"] = df.apply(self._add_date_note, axis=1)
        return df

    @staticmethod
    def _determine_location(row):
        locality = clean_placeholder_string(row["site.Locality"])
        province = clean_placeholder_string(row["site.Province"])
        return join_non_missing_strings(locality, province, sep=", ")

    @staticmethod
    def _add_country_iso(df: pd.DataFrame, country_column: str = "site.Country") -> pd.DataFrame:
        df = df.copy()
        cc = coco.CountryConverter()
        df[country_column] = df[country_column].apply(str.strip)
        iso_codes = cc.pandas_convert(df[country_column], to="iso2")
        df["Country_ISO"] = iso_codes.replace("not found", pd.NA)
        return df

    # -- source material: body unchanged from the original -------------------------
    @staticmethod
    def _determine_source_material(row, type_col="type.Name", type_group_col="type.Type_Group"):
        match row[type_group_col]:
            case 'Tooth':
                return 'tooth'
            case 'Calculus':
                return 'other'
            case 'Bone':
                if row[type_col] in ['Petrous', 'Pars petrosa']:
                    return 'petrous'
                else:
                    return 'bone'
            case 'Other':
                match row[type_col]:
                    case 'Hair':
                        return 'hair'
                    case 'Soft tissue':
                        return 'soft'
                    case 'Soil':
                        return 'sediment'
                    case _:
                        return 'other'
            case _:
                return pd.NA

    def _sample_level_results(self) -> pd.DataFrame:
        sample_results = self.raw.filter(
            ["individual.Full_Individual_Id", "sample.Full_Sample_Id", "type.Type_Group", "type.Name"]
        ).copy()
        sample_results["Source_Material"] = sample_results.apply(self._determine_source_material, axis=1)
        sample_results = (
            sample_results.drop(["sample.Full_Sample_Id", "type.Type_Group", "type.Name"], axis=1)
            .groupby("individual.Full_Individual_Id").agg(lambda x: ";".join(x)).reset_index()
        )
        tags = (
            self.raw.filter(["individual.Full_Individual_Id", "individual.Tags", "individual.Projects"])
            .drop_duplicates()
            .assign(
                Pandora_Tags=lambda x: x["individual.Tags"].str.replace(",", ";", regex=False),
                Pandora_Projects=lambda x: x["individual.Projects"].str.replace(",", ";", regex=False),
            )
            .filter(["individual.Full_Individual_Id", "Pandora_Tags", "Pandora_Projects"])
        )
        return tags.merge(sample_results, on="individual.Full_Individual_Id", validate="one_to_one")

    def build(self) -> pd.DataFrame:
        individual_results = self.raw.filter(PANDORA_COLUMNS).drop_duplicates()
        individual_results = self._add_date_columns(individual_results)
        individual_results["Location"] = individual_results.apply(self._determine_location, axis=1)
        individual_results = self._add_country_iso(individual_results, "site.Country")
        return (
            individual_results
            .merge(self._sample_level_results(), on="individual.Full_Individual_Id", validate="one_to_one")
            .rename(columns={
                "individual.Full_Individual_Id": "Individual_ID",
                "individual.Archaeological_ID": "Collection_ID",
                "site.Name": "Site", "site.Latitude": "Latitude",
                "site.Longitude": "Longitude", "site.Country": "Country",
            })
            .filter(POSEIDON_COLUMNS, axis=1)
        )

class PandoraRawDataMetadata:
    """
    Shapes a raw Pandora TAB_Raw_Data query result (Full_Raw_Data_Id, DOI
    columns) into a per-Sample_Name Publication_Status column.

    Publication_Status logic, per Sample_Name:
      - "no"      if every associated DOI is missing/empty (including the case
                   where a sample's raw data entries weren't found in Pandora
                   at all)
      - "partial" if some associated DOIs are present and some are missing/empty
      - "yes"     if every associated DOI is present and non-empty
    """

    def __init__(self, raw_pandora_results: pd.DataFrame, tsv_table: pd.DataFrame, bam_col: str = "BAM"):
        self.raw = raw_pandora_results
        self.tsv_table = tsv_table
        self.bam_col = bam_col

    def _raw_data_id_to_sample_map(self) -> pd.DataFrame:
        """One row per unique (raw_data_id, Sample_Name) pair, derived from tsv_table."""
        df = self.tsv_table[[self.bam_col, "Sample_Name"]].dropna(subset=[self.bam_col]).copy()
        df["raw_data_id"] = df[self.bam_col].apply(_bam_path_to_raw_data_id)
        return df[["raw_data_id", "Sample_Name"]].drop_duplicates()

    def _attach_sample_name(self) -> pd.DataFrame:
        """Exact-match join of tsv-derived raw_data_ids against Pandora's Full_Raw_Data_Id."""
        id_map = self._raw_data_id_to_sample_map()
        return id_map.merge(
            self.raw, left_on="raw_data_id", right_on="raw_data.Full_Raw_Data_Id", how="left"
        )

    @staticmethod
    def _classify_publication_status(dois: pd.Series) -> str:
        present = dois.notna() & (dois.astype(str).str.strip() != "")
        if present.all():
            return "yes"
        if not present.any():
            return "no"
        return "partial"

    def build(self) -> pd.DataFrame:
        """
        Returns one row per Sample_Name, with a Publication_Status column.
        Samples with no matching raw data entries in Pandora are still
        represented, with Publication_Status = 'no'.
        """
        attached = self._attach_sample_name()
        all_samples = self.tsv_table["Sample_Name"].dropna().unique()

        status_by_sample = (
            attached.groupby("Sample_Name")["raw_data.DOI"]
            .apply(self._classify_publication_status)
            .reindex(all_samples, fill_value="no")
        )
        return status_by_sample.reset_index().rename(
            columns={"index": "Sample_Name", "raw_data.DOI": "Publication_Status"}
        )
