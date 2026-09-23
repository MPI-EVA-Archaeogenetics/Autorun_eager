"""Small, reusable, stateless helpers with no knowledge of janno/eager/pandora."""
import pandas as pd
import numpy as np


def weighted_mean(group, wt_col="wt", val_col="val", filter_col="filter_col", min_val=100):
    """Calculate the weighted mean of a given set of grouped values using the weights defined. Values can be excluded from the calculation if the value in filter_col is below min_val."""
    non_nan = ~group[val_col].isna()
    passes_filter = group[filter_col] >= min_val
    valid = non_nan & passes_filter
    if not valid.any():
        return np.nan
    weighted_values = group.loc[valid, wt_col] * group.loc[valid, val_col]
    total_weight = group.loc[valid, wt_col].sum()
    return weighted_values.sum() / total_weight


def cast_to_int64(val):
    if pd.isna(val):
        return pd.NA
    if isinstance(val, float):
        return pd.Int64Dtype().type(round(val))
    if isinstance(val, int):
        return pd.Int64Dtype().type(val)
    return pd.NA


def coalesce_dataframes(x: pd.DataFrame, y: pd.DataFrame, common_key: str) -> pd.DataFrame:
    """Fill missing values in x from y, add y-only columns."""
    if x is None or y is None:
        raise ValueError("Both dataframes must be provided.")
    if common_key not in x.columns or common_key not in y.columns:
        raise ValueError(f"Both dataframes must contain a '{common_key}' column.")

    result = x.set_index(common_key).copy()
    other = y.set_index(common_key).copy()
    result = result.fillna(other)
    for column in other.columns:
        if column not in result.columns:
            result[column] = other[column]
    return result.reset_index()


def join_non_missing_strings(val1, val2, filter_val1=None, filter_val2=None, sep=';'):
    """Join values val1 and val2, iff filter_val1 and filter_val2 are non-NA. If only one filter_val is missing, then the corresponding val is output."""
    if filter_val1 is not None and filter_val2 is not None:
        if pd.isna(filter_val1) or pd.isna(filter_val2):
            if pd.isna(filter_val1) and pd.isna(filter_val2):
                return pd.NA
            if pd.isna(filter_val1):
                return val2 if pd.notna(val2) else pd.NA
            return val1 if pd.notna(val1) else pd.NA

    if pd.isna(val1) and pd.isna(val2):
        return pd.NA
    if pd.notna(val1) and pd.isna(val2):
        return val1
    if pd.isna(val1) and pd.notna(val2):
        return val2
    return f"{val1}{sep}{val2}"

def clean_placeholder_string(value, placeholders=("na", "none")):
    """Return pd.NA if value is missing or matches a placeholder string (case-insensitive), else return value."""
    if pd.isna(value):
        return pd.NA
    if str(value).strip().lower() in placeholders:
        return pd.NA
    return value

def longest_non_null_string(series: pd.Series):
    """
    Return the longest non-null string in `series`, or pd.NA if every value is null.

    This replaces a previous idxmax()-based approach, which raised a KeyError
    (plus a pandas FutureWarning about deprecated all-NA idxmax behavior) when
    every value in a group was NA -- e.g. because no MT results were available
    for any library belonging to a given sample.
    """
    lengths = series.str.len()
    if lengths.isna().all():
        return pd.NA
    return series.loc[lengths.idxmax()]
