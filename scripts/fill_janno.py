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
        "-r",
        "--eager_result_dir",
        metavar="<DIR>",
        required=True,
        help="The nf-core/eager result directory for the minotaur package.",
    )
    parser.add_argument(
        "-j",
        "--janno",
        metavar="<JANNO>",
        required=True,
        help="The input janno file.",
    )
    parser.add_argument(
        "-t",
        "--eager_tsv_path",
        metavar="<TSV>",
        required=True,
        help="The path to the eager input TSV used to generate the nf-core/eager results.",
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
    tables = [ "TAB_Sample", "TAB_Individual","TAB_Site" ]
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

def main(cli_args:str = None):
    
    args=_get_args(cli_args)
    
    ## Collect JSONs for steps wthat can produce multiple.
    damage_estimation_paths = glob.glob(
        os.path.join(args.eager_result_dir, "damageprofiler", "*", "*.json")
    ) + glob.glob(os.path.join(args.eager_result_dir, "mapdamage", "*"))
    ## Endogenous in Poseidon should be calculated on the SG data.
    endorspy_json_paths = glob.glob(
        os.path.join(args.eager_result_dir, "endorspy", "*.json")
            .replace(f"/{args.analysis_type}/", "/SG/")
    )
    snp_coverage_json_paths = glob.glob(
        os.path.join(args.eager_result_dir, "genotyping", "*.json")
    )

    ## Collect paths for analyses with single json.
    sexdeterrmine_json_path = os.path.join(
        args.eager_result_dir, "sex_determination", "sexdeterrmine.json"
    )
    nuclear_contamination_json_path = os.path.join(
        args.eager_result_dir, "nuclear_contamination", "nuclear_contamination_mqc.json"
    )

    ## Read in nf-core/eager TSV info
    tsv_table = pyEager.parsers.parse_eager_tsv(args.eager_tsv_path)
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
            min_val=100,
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
            min_val=100,
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
            lambda x: "Nr Snps (per library): {}. Estimate and error are weighted means of values per library. Libraries with fewer than 100 SNPs used in contamination estimation were excluded.".format(
                ";".join(x)
            )
        )
        .rename(columns={"Contamination_Nr_SNPs": "Contamination_Note"})
        .reset_index()
        .merge(collected_lib_results, on="Sample_Name", validate="one_to_one")
    )

    
    ## Create list of Pandora Library IDs that were used, to create Library_Names and Nr_Libraries.
    ## Janno Columns: Library_Names, Library_Built, Nr_Libraries, UDG
    library_built_table=tsv_table[["Sample_Name", "Library_ID"]]
    # library_built_table.loc[-1] = ["AAR001_ss", "AAR001_ss.A0102"]
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
    
    out_janno=coalesce_dataframes(janno_table, collected_sample_results, "Eager_ID")
    
    return(out_janno)

if __name__ == "__main__":
    main()
