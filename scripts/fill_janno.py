#!/usr/bin/env python
## This script is inspired by poseidon-eager's populate_janno.py. Functionality from there has been ported over.
## 2026-07-01 Thiseas Christos Lamnidis
import pyEager
import argparse
import sys
import os
import glob
import pandas as pd
import numpy as np
import sqlalchemy
import pymysql
import country_converter as coco
import pyPandoraHelper as pH
pd.options.mode.copy_on_write = True
VERSION="0.0.1"

def _get_args(cli_args:str = None):
    '''This function parses and return arguments passed in'''
    parser = argparse.ArgumentParser(
        prog="populate_janno",
        description="This script reads in different nf-core/eager result files and"
        "uses this information to populate the relevant fields in a"
        "poseidon janno file. The janno file and .ind/.fam file of the"
        "package are updated, unless the --safe option is provided, in"
        "which case the output files get the suffix '.new'.",
    )
    parser.add_argument(
        "-i",
        "--ind_id",
        required=True,
        help="The individual ID whose package janno should be updated."
    )
    parser.add_argument(
        "-j",
        "--janno",
        metavar="<JANNO>",
        required=True,
        help="The input janno file.",
    )
    parser.add_argument(
        "-a",
        "--analysis_type",
        required=True,
        help="The analysis type of the data to fill in.",
        choices=["SG","TF","TM","RP","RM"]
    )
    parser.add_argument(
        "-c",
        "--credentials",
        metavar="<CREDETIALS>",
        required=True,
        help="The PANDORA credentials file.",
    )
    parser.add_argument(
        "-s",
        "----contamination_snp_cutoff",
        metavar="<CONTAMINATION_SNP_CUTOFF>",
        required=False,
        default=100
        help="The snp cutoff for nuclear contamination results. Nuclear contamination results with fewer than this number of SNPs will be ignored when calculating the values for 'Contamination_*' columns. [100]"
    )
    parser.add_argument(
        "-p",
        "--genotype_ploidy",
        metavar="<PLOIDY>",
        required=False,
        default='haploid',
        help="The genotype ploidy of the genotypes produced by eager. This value will be used to fill in all missing entries in the 'Genotype_Ploidy' in the output janno file. ['haploid']",
    )
    parser.add_argument(
        "--safe",
        action="store_true",
        help="Activate safe mode. The package's janno and ind files will not be updated, but instead new files will be created with the '.new' suffix. Only useful for testing.",
    )
    parser.add_argument("-v", "--version", action="version", version=VERSION)
    return(parser.parse_args(cli_args))

def read_janno(path:str) -> pd.DataFrame:
    return (pd.read_table(path, dtype={
        "Poseidon_ID" : "str",
        "Genetic_Sex" : "str",
        "Group_Name" : "str",
        "Individual_ID" : "str",
        "Species" : "str",
        "Alternative_IDs" : "str",
        "Alternative_IDs_Context" : "str",
        "Relation_To" : "str",
        "Relation_Degree" : "str",
        "Relation_Type" : "str",
        "Collection_ID" : "str",
        "Custodian_Institution" : "str",
        "Cultural_Era" : "str",
        "Cultural_Era_URL" : "str",
        "Archaeological_Culture" : "str",
        "Archaeological_Culture_URL" : "str",
        "Country" : "str",
        "Country_ISO" : "str",
        "Location" : "str",
        "Site" : "str",
        "Latitude" : np.float32,
        "Longitude" : np.float32,
        "Date_Type" : "str",
        "Date_C14_Labnr" : "str",
        "Date_C14_Uncal_BP" : "Int64",
        "Date_C14_Uncal_BP_Err" : "Int64",
        "Date_BC_AD_Start" : "Int64",
        "Date_BC_AD_Median" : "Int64",
        "Date_BC_AD_Stop" : "Int64",
        "Chromosomal_Anomalies" : "str",
        "MT_Haplogroup" : "str",
        "Y_Haplogroup" : "str",
        "Source_Material" : "str",
        "Nr_Libraries" : "Int64",
        "Library_Names" : "str",
        "Capture_Type" : "str",
        "UDG" : "str",
        "Library_Built" : "str",
        "Genotype_Ploidy" : "str",
        "Data_Preparation_Pipeline_URL" : "str",
        "Endogenous" : np.float32,
        "Nr_SNPs" : "Int64",
        "Coverage_on_Target_SNPs" : np.float32,
        "Damage" : np.float32,
        "Contamination" : "str",
        "Contamination_Err" : "str",
        "Contamination_Meas" : "str",
        "Genetic_Source_Accession_IDs" : "str",
        "Primary_Contact" : "str",
        "Publication" : "str",
        "Note" : "str",
        "Keywords" : "str"
    }))

def get_eager_version(eager_result_dir: str):
    software_versions_csv_fn = os.path.join(
        eager_result_dir, "pipeline_info", "software_versions.csv"
    )
    ## Check the file xists, and if so, read it in and return the version of nf-core/eager
    if os.path.exists(software_versions_csv_fn):
        with open(software_versions_csv_fn, "r") as f:
            for line in f:
                if line.strip().split()[0] == "nf-core/eager":
                    return line.strip().split()[1].lstrip("v")
    else:
        return None

## Function to calculate weighted mean of a group from the weight and value columns specified.
def weighted_mean(
    group, wt_col:str = "wt", val_col:str = "val", filter_col:str = "filter_col", min_val:int = 100
) -> float:
    '''
    Calculate the weighted mean of a group based on weight and value columns.
    
    This function computes a weighted average of values from a specified column,
    using weights from another specified column. Values are filtered based on a
    minimum threshold before calculation.
    
    Parameters
    ----------
    group : pandas.DataFrame
      The input DataFrame containing the weight, value, and filter columns.
    wt_col : str, optional
      The name of the column containing weights. Default is "wt".
    val_col : str, optional
      The name of the column containing values to average. Default is "val".
    filter_col : str, optional
      The name of the column used for filtering values. Default is "filter_col".
    min_val : int, optional
      The minimum threshold value for filtering. Values below this threshold
      are excluded from the calculation. Default is 100.
    
    Returns
    -------
    float or numpy.nan
      The weighted mean of the valid values, or NaN if no values meet the
      filtering criteria.
    
    Examples
    --------
    >>> import pandas as pd
    >>> import numpy as np
    >>> df = pd.DataFrame({
    ...     'wt': [1, 2, 3],
    ...     'val': [10, 20, 30],
    ...     'filter_col': [150, 120, 100]
    ... })
    >>> weighted_mean(df, min_val=100)
    23.333...
    '''
    non_nan_indices = ~group[val_col].isna()
    filter_indices = group[filter_col] >= min_val  ## Remove values below the cutoff
    valid_indices = non_nan_indices & filter_indices
    if valid_indices.any():
        weighted_values = (
            group.loc[valid_indices, wt_col] * group.loc[valid_indices, val_col]
        )
        total_weight = group.loc[
            valid_indices, wt_col
        ].sum()  # Calculate total weight without excluded weights
        weighted_mean = weighted_values.sum() / total_weight
    else:
        weighted_mean = np.nan  # Return NaN if no valid values left
    return weighted_mean

## Function to convert UDG_Treatment to poseidon UDG
def udg_treatment_to_udg(df: pd.DataFrame) -> pd.DataFrame:
    '''
    Convert UDG treatment values in a DataFrame column from eager-coded format to Poseidon equivalents.
    
    This function maps eager-specific UDG (Uracil-DNA Glycosylase) treatment codes to their 
    corresponding Poseidon standard representations:
    - "none" -> "minus"
    - "half" -> "half"
    - "full" -> "plus"
    - "mixed" -> "mixed"
    - any other value -> "n/a"
    
    Args:
      df (pd.DataFrame): DataFrame containing a 'UDG_Treatment' column with eager-coded values.
    
    Returns:
      pd.DataFrame: The input DataFrame with 'UDG_Treatment' column values converted to Poseidon equivalents.
    
    Note:
      This function modifies the input DataFrame in place and also returns it.
    '''
    if df["UDG_Treatment"] == "none":
        df["UDG_Treatment"] = "minus"
    elif df["UDG_Treatment"] == "half":
        df["UDG_Treatment"] = "half"
    elif df["UDG_Treatment"] == "full":
        df["UDG_Treatment"] = "plus"
    elif df["UDG_Treatment"] == "mixed":
        df["UDG_Treatment"] = "mixed"
    else:
        df["UDG_Treatment"] = "n/a"
    return df

def coalesce_dataframes(
    x: pd.DataFrame = None,
    y: pd.DataFrame = None,
    common_key: str = None,
) -> pd.DataFrame:
    '''
    Coalesce two dataframes on a shared key.

    Existing values in x are preserved. Missing values in x are filled from y
    for shared columns. Columns that exist only in y are added to x.
    '''
    if x is None or y is None:
        raise ValueError("Both dataframes must be provided.")
    if common_key is None:
        raise ValueError("A common_key must be provided.")
    if common_key not in x.columns or common_key not in y.columns:
        raise ValueError(f"Both dataframes must contain a '{common_key}' column.")
    
    # Set the common key as the index for both dataframes
    result = x.set_index(common_key).copy()
    other = y.set_index(common_key).copy()
    
    # Fill missing values in result with values from other
    result = result.fillna(other)
    
    # Add columns that exist only in other
    for column in other.columns:
        if column not in result.columns:
            result[column] = other[column]
    
    # Reset the index to bring the common_key back as a column
    return result.reset_index()

def _format_table_name(x:str) -> str:
    return x.removeprefix("TAB_").lower()

def build_sql_query(
    values: list                 = None,
    column: str                  = None,
    metadata:sqlalchemy.MetaData = None,
    # tables:list = [ "TAB_Sample", "TAB_Individual","TAB_Site" ]
) -> str:
    """
    Build the SQL query for Pandora

    Args:
        values (list, optional): The values to filter Pandora info for.
        column (str, optional): The column to apply the filter to.
        metadata: SQLAlchemy metadata object containing table definitions.

    Returns:
        str: Full SQL query string.
    """
        # tables: a list of Pandora table names that are to be pulled. Currently hardcoded. As working out the correct join keys is beyond the scope of this script.
    tables = [ "TAB_Sample", "TAB_Individual","TAB_Site", "TAB_Type" ]
    filter_query = ""
    if not column:
        print("No column provided. No query filtering will be performed.")
    else:
        if isinstance(values, str):
            filter_query = f"    AND {column} = '{values}'"
        elif isinstance(values, list):
            q = []
            sep = "\n         OR "
            for v in values:
                q.append(f"`{column}` = '{v}'")
            filter_query = "AND (\n            " + f"{sep.join(q)}" + "\n        )"
    # Dynamically generate the SELECT clause with prefixed columns
    if not metadata:
        select_clause = 'SELECT *'
    else:
        select_clause = "SELECT\n"
        columns = []
        for old_name in tables:
            new_name=_format_table_name(old_name)
            table = metadata.tables[old_name]
            for column in table.columns:
                columns.append(f"{new_name}.`{column.name}` AS `{new_name}.{column.name}`")
        
        select_clause += ",\n".join(columns)
    query = f"""
    {select_clause}
    FROM
         TAB_Sample     AS sample
    JOIN TAB_Individual AS individual ON sample.individual = individual.id
    JOIN TAB_Site       AS site       ON individual.site   = site.id
    JOIN TAB_Type       AS type       ON sample.type       = type.id
    WHERE
        -- Remove any deleted entries.
        sample.Deleted            =  'false'
        AND individual.Deleted    =  'false'
        AND site.Deleted          =  'false'
        {filter_query}
    ORDER BY individual.Full_Individual_Id;
    """
    return query

def read_credfile(cred_file: str) -> dict:
    """Read credentials to access SQL server from file

    Args:
        cred_file (str): TXT formatted files with credentials for accessing Pandora.
            Four lines, first line is host, second line is login, third line is password, fourth line is port.
    Returns:
        dict: {host: 'server_address', login: 'login', password: 'pwd', port: 'port'}
    """
    with open(cred_file, "r") as c:
        lines = c.readlines()
        cred = {
            "host"     : lines[0].strip(),
            "port"     : lines[1].strip(),
            "login"    : lines[2].strip(),
            "password" : lines[3].strip()
        }
    return cred

def query_pandora(
    host:str           = None,
    port:str           = None,
    login:str          = None,
    password:str       = None,
    filter_column:str  = "individual.Full_Individual_Id",
    filter_values:list = None
) -> pd.DataFrame:
    """Retrieve information from Pandora, applying specific filters.

    Args:
        host (str): Address of SQL server.
        port (str): Port of SQL server.
        login (str): Login of SQL server.
        password (str): Password of SQL server.
        filter_column (str): The column to filter on, if any filter_values are provided.
        filter_values (list): The values that should be filtered for. Only matching values in the filter_column are kept.
    Returns:
        (pandas dataframe): Table of retrieved metadata (Site-Sample tabs).
    """
    sql_connection = f"mysql+pymysql://{login}:{password}@{host}:{port}/pandora"
    engine = sqlalchemy.create_engine(sql_connection)
    metadata = sqlalchemy.MetaData()
    metadata.reflect(bind=engine)  # Reflect the table structures from the database
    try:
        pd.read_sql_query("SELECT 1", engine)
        print("[query_pandora]: Successfully Connected to Pandora Database")
    except Exception as e:
        print(e)
        print("[query_pandora]: Error connecting to Pandora Database")
        sys.exit(1)
    print("[query_pandora]: Making request to Pandora SQL server")
    query_string = build_sql_query(column=filter_column, values=filter_values, metadata=metadata)
    request = pd.read_sql_query(query_string, engine)
    
    print("[query_pandora]: All samples and metadata successfully retrieved")
    return request

def add_date_columns(data):
    df = data.copy()
    ## Edits the underlying dataframe
    ## Initialize new columns with NaN
    df['Date_Type']                 = pd.NA
    df['Date_C14_Labnr']            = pd.NA
    df['Date_C14_Uncal_BP']         = np.nan
    df['Date_C14_Uncal_BP_Err']     = np.nan
    df['Date_C14_Reservoir_Offset'] = np.nan
    df['Date_BC_AD_Start']          = np.nan
    df['Date_BC_AD_Median']         = np.nan
    df['Date_BC_AD_Stop']           = np.nan
    df['Date_Note']                 = pd.NA
    
    ## Define a function to determine Date_Type
    def determine_date_type(row):
        if pd.notna(row['individual.C14_Uncalibrated']) and not row['individual.C14_Uncalibrated'] == 0:
            return 'C14'
        elif pd.notna(row['individual.Archaeological_Date_From']) or pd.notna(row['site.Date_From']):
            return 'contextual'
        else:
            return pd.NA
    
    ## Define a function to determine Date_C14_Labnr
    def detrmine_c14_labnr(row):
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
    
    ## Define a function to determine Date_C14_Uncal_BP adn Date_C14_Uncal_BP_Err, Date_C14_Reservoir_Offset (if any)
    def determine_uncal_dates_and_reservoir(row):
        ## I am assuming only one value is in these fields, even when multiple dates are present.
        ## I think pandora only allows a single integer in the field anyway.
        if pd.notna(row['individual.C14_Uncalibrated']) and not row['individual.C14_Uncalibrated'] == 0:
            if pd.notna(row['individual.C14_Calibration_Reservoir_Offset']):
                reservoir_offset=row['individual.C14_Calibration_Reservoir_Offset']
            else:
                reservoir_offset=pd.NA
            return (row['individual.C14_Uncalibrated'], row['individual.C14_Uncalibrated_Variation'], reservoir_offset)
        else:
            return (pd.NA, pd.NA, pd.NA)
    
    ## Define a function to determine Date_BC_AD_* columns
    def determine_bc_ad_dates(row):
        if pd.notna(row['individual.C14_Uncalibrated']) and not row['individual.C14_Uncalibrated'] == 0:
            ## If there are uncalibrated and calibrated dates, fill in from Pandora. 
            if pd.notna(row['individual.C14_Calibrated_From']) and pd.notna(row['individual.C14_Calibrated_To']):
                ## Rare cases where the Pandora values correspond to 1 sigma. These should be excluded as they do not conform to Poseidon schema.
                if any(x in row['individual.C14_Info'].lower() for x in ["1 sigma", "1-sigma", "sigma1", "sigma 1", "sigma-1"]):
                    return ( pd.NA, pd.NA, pd.NA )
                else:
                    ## If mean is missing in Pandora, leave blank. (Median can't be calculated without the distribution.)
                    if pd.notna(row['individual.C14_Calibrated_Mean']):
                        calibrated_mean=row['individual.C14_Calibrated_Mean']
                    else:
                        calibrated_mean=pd.NA
                    return (
                        row['individual.C14_Calibrated_From'],
                        calibrated_mean,
                        row['individual.C14_Calibrated_To']
                    )
            else:
                ## If there are uncalibrated dates, but no calibrated ones, leave empty (should get quickcalibrated).
                return ( pd.NA, pd.NA, pd.NA )
        elif pd.notna(row['individual.Archaeological_Date_From']) and pd.notna(row['individual.Archaeological_Date_To']):
            ## If the individual has Archaeological dates, use those.
            individual_mean = np.mean([row['individual.Archaeological_Date_From'], row['individual.Archaeological_Date_To']])
            return(
                row['individual.Archaeological_Date_From'],
                individual_mean,
                row['individual.Archaeological_Date_To']
            )
        elif pd.notna(row['site.Date_From']) and pd.notna(row['site.Date_To']):
            ## If the site has a date range, use that.
            site_mean = np.mean([row['site.Date_From'], row['site.Date_To']])
            return(
                row['site.Date_From'],
                site_mean,
                row['site.Date_To']
            )
        else:
            ## If all the above are missing, leave empty.
            return( pd.NA, pd.NA, pd.NA )
    
    def add_date_note(row):
        if pd.notna(row['individual.C14_Calibration_Curve']) and pd.notna(row['individual.C14_Calibration_Software']):
            return f"{row['individual.C14_Calibration_Curve']}, calibrated with {row['individual.C14_Calibration_Software']}"
        elif pd.notna(row['individual.C14_Calibration_Curve']):
            return f"{row['individual.C14_Calibration_Curve']}"
        else:
            return pd.NA
            
    # Apply the function to determine Date_Type
    df['Date_Type'] = df.apply(determine_date_type, axis=1)
    
    # Apply the function to extract lab number from Pandora entries
    df['Date_C14_Labnr'] = df.apply(detrmine_c14_labnr, axis=1)
    
    # Apply the function to determine uncalibrated dates and reservoir offset.
    df[['Date_C14_Uncal_BP','Date_C14_Uncal_BP_Err', 'Date_C14_Reservoir_Offset']] = df.apply(determine_uncal_dates_and_reservoir, axis=1, result_type='expand')
    
    # Apply the function to determine BC_AD range columns
    df[['Date_BC_AD_Start', 'Date_BC_AD_Median', 'Date_BC_AD_Stop']] = df.apply(determine_bc_ad_dates, axis=1, result_type='expand')
    
    ## Apply function to add calibrartion note
    df['Date_Note'] = df.apply(add_date_note, axis=1)
    
    return df

def determine_location(row):
    if pd.notna(row['site.Locality']) and pd.notna(row['site.Province']) and row['site.Province'].lower() not in ["na", "none"]:
        return f"{row['site.Locality']}, {row['site.Province']}"
    elif pd.notna(row['site.Locality']) and not pd.notna(row['site.Province']):
        return row['site.Locality']
    elif not pd.notna(row['site.Locality']) and pd.notna(row['site.Province']) and row['site.Province'].lower() not in ["na", "none"]:
        return row['site.Province']
    else:
        return pd.NA

def add_country_iso(data: pd.DataFrame, country_column: str = "Country") -> pd.DataFrame:
    """
    Adds a new column 'Country_ISO' to the DataFrame with ISO alpha-2 country codes.

    Parameters:
    df (pd.DataFrame): The input DataFrame.
    country_column (str): The name of the column containing country names.

    Returns:
    pd.DataFrame: The DataFrame with the new 'Country_ISO' column.
    """
    df = data.copy()
    # Initialize the CountryConverter
    cc = coco.CountryConverter()
    
    ## First, strip whitespace
    df[country_column] = df[country_column].apply(str.strip)
    
    ## Convert all names to ISO2 codes.
    iso_codes=cc.pandas_convert(df[country_column], to="iso2")
    
    # Add the new column to the DataFrame
    df['Country_ISO'] = iso_codes
    
    return df

def main(cli_args:str = None):
    
    args=_get_args(cli_args)
    
    site_id=pH.get_site_id(args.ind_id)
    eager_result_dir = f"/mnt/archgen/Autorun_eager/eager_outputs/{analysis_type}/{site_id}/{ind_id}/"
    
    ## Collect JSONs for steps wthat can produce multiple.
    damage_estimation_paths = glob.glob(
        os.path.join(eager_result_dir, "damageprofiler", "*", "*.json")
    ) + glob.glob(os.path.join(eager_result_dir, "mapdamage", "*"))
    ## Endogenous in Poseidon should be calculated on the SG data.
    endorspy_json_paths = glob.glob(
        os.path.join(eager_result_dir, "endorspy", "*.json")
            .replace(f"/{args.analysis_type}/", "/SG/")
    )
    snp_coverage_json_paths = glob.glob(
        os.path.join(eager_result_dir, "genotyping", "*.json")
    )
    
    ## Collect paths for analyses with single json.
    sexdeterrmine_json_path = os.path.join(
        eager_result_dir, "sex_determination", "sexdeterrmine.json"
    )
    nuclear_contamination_json_path = os.path.join(
        eager_result_dir, "nuclear_contamination", "nuclear_contamination_mqc.json"
    )
    
    ## Read in nf-core/eager TSV info
    eager_tsv_path = f"/mnt/archgen/Autorun_eager/eager_inputs/{analysis_type}/{site_id}/{ind_id}/{ind_id}.tsv"
    tsv_table = pyEager.parsers.parse_eager_tsv(eager_tsv_path)
    tsv_table = pyEager.parsers.infer_merged_bam_names(
        tsv_table, run_trim_bam=True, skip_deduplication=False
    )
    
    ## Read in janno and create needed additonal columns.
    janno_table = read_janno(args.janno)
    ## Add Individual_ID to janno table. That is the Poseidon_ID after removing added analysis type and _ss suffixes.
    janno_table["Eager_ID"] = janno_table["Poseidon_ID"].str.replace(f".{args.analysis_type}", "")
    janno_table["Individual_ID"] = janno_table["Eager_ID"].str.replace(r"_ss", "")
    
    ## Prepare damage table for joining. Infer eager Library_ID from id column, by removing '_rmdup.bam' suffix
    ## Janno Columns: Damage
    ## The "_rmdup" is removed separately to also apply to mapdamage results (which lack the .bam suffix)
    damage_table = pyEager.wrappers.compile_damage_table(damage_estimation_paths)
    damage_table["Library_ID"] = (
        damage_table["id"].str.replace(r"_rmdup", "").str.replace(r".bam", "")
    )
    damage_table = damage_table[["Library_ID", "n_reads", "dmg_5p_1bp"]].rename(
        columns={"dmg_5p_1bp": "damage"}
    )
    
    ## Prepare SG endogenous table for joining. Should be max value in cases where multiple libraries are merged.
    ## Janno Columns: Endogenous
    endogenous_table = pyEager.wrappers.compile_endogenous_table(endorspy_json_paths)
    endogenous_table = endogenous_table[["id", "endogenous_dna"]].rename(
        columns={"id": "Library_ID", "endogenous_dna": "endogenous"}
    )
    
    ## Prepare contamination table for joining. Always at library level. Only need to fix column names here.
    ## Janno columns: Contamination_Est, Conamination_SE, Contamination_Nr_SNPs, Conamination_Note
    contamination_table = pyEager.parsers.parse_nuclear_contamination_json(
        nuclear_contamination_json_path
    )
    contamination_table = contamination_table[
        ["id", "Num_SNPs", "Method1_ML_estimate", "Method1_ML_SE"]
    ].rename(
        columns={
            "id": "Library_ID",
            "Num_SNPs": "Contamination_Nr_SNPs",
            "Method1_ML_estimate": "Contamination_Est",
            "Method1_ML_SE": "Contamination_SE",
        }
    )
    contamination_table["Contamination_Est"] = pd.to_numeric(
        contamination_table["Contamination_Est"], errors="coerce"
    )
    contamination_table["Contamination_SE"] = pd.to_numeric(
        contamination_table["Contamination_SE"], errors="coerce"
    )
    
    ## LIBRARY LEVEL RESULTS THAT NEED AGGRGATION. Need to be put together since weighted mean relies on n_reads from damage_table.
    lib_results = (
        damage_table
        .merge(endogenous_table, on="Library_ID", validate="one_to_one")
        .merge(contamination_table, on="Library_ID", validate="one_to_one")
    )
    lib_results["Sample_Name"] = lib_results["Library_ID"].str.replace(r".[A-Z][0-9]{4}$", "", regex=True)
    lib_results['Contamination_Meas'] = np.where(lib_results['Contamination_Nr_SNPs'] > 100, 'ANGSD', pd.NA)
    
    ## Aggregate lib_results to sample level
    collected_lib_results = pd.DataFrame()
    collected_lib_results["Sample_Name"] = lib_results["Sample_Name"].unique()
    
    ## Endogenous: maximum value across libraries
    collected_lib_results = (
        lib_results.groupby("Sample_Name")["endogenous"]
        .apply(np.maximum.reduce)
        .apply(lambda x: round (x/100, 3) )
        .reset_index()
        .rename(columns={"endogenous": "Endogenous"})
        .merge(collected_lib_results, on="Sample_Name", validate="one_to_one")
    )
    
    ## Damage: weighted mean across libraries
    collected_lib_results = (
        lib_results.groupby("Sample_Name")[
            ["damage", "n_reads"]
        ]
        .apply(
            weighted_mean,
            wt_col="n_reads",
            val_col="damage",
            filter_col="n_reads",
            min_val=0,
        )
        .apply(lambda x: round (x, 3) )
        .reset_index()
        .rename(columns={0: "Damage"})
        .merge(collected_lib_results, on="Sample_Name", validate="one_to_one")
    )
    
    ## Contamination_Est: weighted mean across libraries
    collected_lib_results = (
        lib_results.groupby("Sample_Name")[
            ["Contamination_Nr_SNPs", "Contamination_Est", "n_reads"]
        ]
        .apply(
            weighted_mean,
            wt_col="n_reads",
            val_col="Contamination_Est",
            filter_col="Contamination_Nr_SNPs",
            min_val=args.contamination_snp_cutoff,
        )
        .apply(lambda x: round (x, 3) )
        .reset_index()
        .rename(columns={0: "Contamination"})
        .merge(collected_lib_results, on="Sample_Name", validate="one_to_one")
    )
    
    ## Contamination_SE: weighted mean across libraries
    collected_lib_results = (
        lib_results.groupby("Sample_Name")[
            ["Contamination_Nr_SNPs", "Contamination_SE", "n_reads"]
        ]
        .apply(
            weighted_mean,
            wt_col="n_reads",
            val_col="Contamination_SE",
            filter_col="Contamination_Nr_SNPs",
            min_val=args.contamination_snp_cutoff,
        )
        .apply(lambda x: round (x, 5) )
        .reset_index()
        .rename(columns={0: "Contamination_Err"})
        .merge(collected_lib_results, on="Sample_Name", validate="one_to_one")
    )
    
    ## Contamination_Note: message about contamination estimation
    collected_lib_results = (
        lib_results.astype("string")
        .groupby("Sample_Name")[["Contamination_Nr_SNPs"]]
        .agg(
            lambda x: "Nr Snps (per library): {}. Estimate and error are weighted means of values per library. Libraries with fewer than {args.contamination_snp_cutoff} SNPs used in contamination estimation were excluded.".format(
                ";".join(x)
            )
        )
        .rename(columns={"Contamination_Nr_SNPs": "Contamination_Note"})
        .reset_index()
        .merge(collected_lib_results, on="Sample_Name", validate="one_to_one")
    )
    
    ## Conamination_Meas: onlt ANGSD if some libraries have enough SNPs
    collected_lib_results = (
        lib_results.groupby("Sample_Name")[["Contamination_Meas"]]
        .agg(
            lambda x: np.nan if x.isna().all() else 'ANGSD'
        )
        .reset_index()
        .merge(collected_lib_results, on="Sample_Name", validate="one_to_one")
        )
    
    ## Create list of Pandora Library IDs that were used, to create Library_Names and Nr_Libraries.
    ## Janno Columns: Library_Names, Library_Built, Nr_Libraries, UDG
    library_built_table=tsv_table[["Sample_Name", "Library_ID"]]
    library_built_table["Library_ID"]=library_built_table["Library_ID"].str.replace(r"_ss", "")
    library_built_table=(
            library_built_table[["Sample_Name", "Library_ID"]]
        .drop_duplicates()
        .groupby("Sample_Name")[["Library_ID"]]
        .agg(lambda x: ";".join(x))
        .rename(columns={"Library_ID": "Library_Names"})
        .reset_index()
    )
    library_built_table["Nr_Libraries"] = library_built_table["Library_Names"].str.count(";") + 1
    library_built_table["Library_Built"] = library_built_table.apply(
        lambda row: ";".join(
            ["ss"] * int(row["Nr_Libraries"])
            if str(row.Sample_Name).endswith("_ss")
            else ["ds"] * int(row["Nr_Libraries"])
        ),
        axis=1,
    )
    library_built_table=(
            tsv_table[["Sample_Name", "Library_ID", "UDG_Treatment"]]
        .drop_duplicates()
        .groupby("Sample_Name")[["UDG_Treatment"]]
        .agg(lambda x: ";".join(x))
        .rename(columns={"UDG_Treatment": "UDG"})
        .reset_index()
        .merge(library_built_table, on="Sample_Name", validate="one_to_one")
    )
    
    ## Prepare SNP coverage table for joining. Should always be on the sample level, so only need to fix column names.
    ## Janno columns: Nr_SNPs
    snp_coverage_table = pyEager.wrappers.compile_snp_coverage_table(
        snp_coverage_json_paths
    )
    snp_coverage_table = snp_coverage_table.drop("Total_Snps", axis=1).rename(
        columns={"id": "Sample_Name", "Covered_Snps": "Nr_SNPs"}
    )
    
    sex_determination_table = pyEager.parsers.parse_sexdeterrmine_json(
        sexdeterrmine_json_path
    )
    sex_determination_table["Sample_Name"] = sex_determination_table["id"].str.replace(r"\..*$", "", regex=True)
    sex_determination_table[["RateX", "RateY", "RateErrX", "RateErrY"]] = (
        sex_determination_table[["RateX", "RateY", "RateErrX", "RateErrY"]]
        .apply(lambda x: round(pd.to_numeric(x, errors='coerce'), 5))
    )
    sex_determination_table = sex_determination_table[["Sample_Name", "RateX", "RateY", "RateErrX", "RateErrY"]]
    
    collected_sample_results = (
        sex_determination_table
        .merge(snp_coverage_table, on="Sample_Name", validate="one_to_one")
        .merge(library_built_table, on="Sample_Name", validate="one_to_one")
        .merge(collected_lib_results, on="Sample_Name", validate="one_to_one")
        .rename(columns={"Sample_Name":"Eager_ID"})
    )
    
    creds=read_credfile(args.credentials)
    ## Pull info from padora. Uses the first Individual_ID in the janno. This is because at this stage, all poseidon IDs will have the same Invidual_ID.
    pandora_results = query_pandora(**creds, filter_values=janno_table['Individual_ID'][0]).replace('', pd.NA)
    pandora_results = pandora_results[~pandora_results['sample.Ethically_culturally_sensitive'].str.startswith('Yes', na=False)]
    
    ## Get Source_Material column info.
    sample_results = (
        pandora_results
        .filter(['individual.Full_Individual_Id', 'sample.Full_Sample_Id', 'type.Type_Group', 'type.Name'])
    )
    sample_results['Source_Material'] = (
        (sample_results['type.Type_Group'] + '_' + sample_results['type.Name'])
        .str.lower()
        .str.replace(' ', '_')
    )
    sample_results = (
        sample_results
        .drop(['sample.Full_Sample_Id', 'type.Type_Group', 'type.Name'], axis=1)
        .groupby("individual.Full_Individual_Id")
        .agg(lambda x: ";".join(x))
        .reset_index()
    )
    
    pandora_cols_to_keep = [
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
        'site.Date_Info'
    ]
    
    poseidon_cols = [
        'Individual_ID',
        'Alternative_IDs',
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
        'Country_ISO',
        'Source_Material'
    ]
    
    individual_results = (
        pandora_results
        .filter(pandora_cols_to_keep)
        .drop_duplicates()
    )
    individual_results = add_date_columns(individual_results)
    individual_results['Location'] = individual_results.apply(determine_location, axis=1)
    individual_results = add_country_iso(individual_results, "site.Country")
    
    ## Finalise individual results table from pandora
    individual_results = (
        individual_results
        .merge(sample_results, on="individual.Full_Individual_Id", validate="one_to_one")
        .rename(columns={
            'individual.Full_Individual_Id' : 'Individual_ID', ## Foreign Key
            'individual.Archaeological_ID' : 'Alternative_IDs',
            'site.Name' : 'Site',
            'site.Latitude' : 'Latitude',
            'site.Longitude' : 'Longitude',
        })
        .filter(poseidon_cols, axis=1)
    )
    
    ## Put together all the information from the compiled tables into the janno.
    out_janno=coalesce_dataframes(janno_table, collected_sample_results, "Eager_ID")
    out_janno=coalesce_dataframes(out_janno  , individual_results      , "Individual_ID")
    ## Finally, update the Group_Name to include the poseidon ID, as well as the site ID with the analysis type suffix.
    out_janno['Group_Name'] = out_janno['Group_Name'] + ';' + out_janno['Group_Name'] + f'.{args.analysis_type}'
    out_janno['Genotype_Ploidy'] = args.genotype_ploidy
    return(out_janno)

if __name__ == "__main__":
    filled_janno = main()
    if args.safe:
        output = args.input+".new"
    else:
        output = args.input
    
    ## Save output to file.
    filled_janno.to_csv(
            args.janno+'.new', 
            filled_janno, 
            sep="\t", 
            na_rep="",
            mode="w",
        )
