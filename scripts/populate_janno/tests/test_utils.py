"""Tests for pure, stateless helpers in populate_janno.utils."""
import numpy as np
import pandas as pd
import pytest

from populate_janno.utils import weighted_mean, coalesce_dataframes, join_non_missing_strings, clean_placeholder_string, longest_non_null_string


class TestWeightedMean:
    def test_basic_weighted_average(self, sample_library_group):
        # Row 2 (val=2.0) is excluded because filter_col=50 < min_val=100
        result = weighted_mean(sample_library_group, min_val=100)
        expected = (10 * 1.0 + 30 * 3.0) / (10 + 30)
        assert result == pytest.approx(expected)

    def test_returns_nan_when_no_rows_pass_filter(self, sample_library_group):
        result = weighted_mean(sample_library_group, min_val=1000)
        assert np.isnan(result)

    def test_ignores_nan_values_even_if_filter_passes(self):
        df = pd.DataFrame({"wt": [1, 1], "val": [np.nan, 5.0], "filter_col": [200, 200]})
        result = weighted_mean(df, min_val=100)
        assert result == 5.0

    def test_min_val_is_inclusive(self):
        df = pd.DataFrame({"wt": [1], "val": [10.0], "filter_col": [100]})
        result = weighted_mean(df, min_val=100)
        assert result == 10.0


class TestCoalesceDataframes:
    def test_fills_missing_values_from_y(self):
        x = pd.DataFrame({"key": ["a", "b"], "val": [1, None]})
        y = pd.DataFrame({"key": ["a", "b"], "val": [99, 2]})
        result = coalesce_dataframes(x, y, "key")
        assert result.set_index("key")["val"].tolist() == [1, 2]  # x's value preserved where present

    def test_adds_columns_only_present_in_y(self):
        x = pd.DataFrame({"key": ["a"], "val": [1]})
        y = pd.DataFrame({"key": ["a"], "extra": ["hello"]})
        result = coalesce_dataframes(x, y, "key")
        assert result.loc[0, "extra"] == "hello"

    def test_raises_if_common_key_missing(self):
        x = pd.DataFrame({"key": ["a"]})
        y = pd.DataFrame({"other": ["a"]})
        with pytest.raises(ValueError):
            coalesce_dataframes(x, y, "key")

    def test_raises_if_either_df_is_none(self):
        with pytest.raises(ValueError):
            coalesce_dataframes(None, pd.DataFrame(), "key")


class TestJoinNonMissingStrings:
    def test_joins_both_present_with_default_separator(self):
        assert join_non_missing_strings("a", "b") == "a;b"

    def test_joins_both_present_with_custom_separator(self):
        assert join_non_missing_strings("a", "b", sep=", ") == "a, b"

    def test_returns_single_value_when_other_missing(self):
        assert join_non_missing_strings("a", pd.NA) == "a"
        assert join_non_missing_strings(pd.NA, "b") == "b"

    def test_returns_na_when_both_missing(self):
        assert pd.isna(join_non_missing_strings(pd.NA, pd.NA))

    def test_filter_values_suppress_join_when_one_is_na(self):
        result = join_non_missing_strings("a", "b", filter_val1=pd.NA, filter_val2="present")
        assert result == "b"

    def test_filter_values_both_na_returns_na(self):
        result = join_non_missing_strings("a", "b", filter_val1=pd.NA, filter_val2=pd.NA)
        assert pd.isna(result)

class TestCleanPlaceholderString:
    def test_returns_value_unchanged_when_not_a_placeholder(self):
        assert clean_placeholder_string("Saxony") == "Saxony"

    def test_returns_na_for_actual_na(self):
        assert pd.isna(clean_placeholder_string(pd.NA))

    @pytest.mark.parametrize("placeholder", ["na", "NA", "None", "none", " na ", "NONE"])
    def test_returns_na_for_placeholder_strings_case_insensitive(self, placeholder):
        assert pd.isna(clean_placeholder_string(placeholder))

class TestLongestNonNullString:
    def test_returns_longest_string(self):
        s = pd.Series(["H2a1", "H", pd.NA])
        assert longest_non_null_string(s) == "H2a1"

    def test_returns_na_when_all_missing(self):
        s = pd.Series([pd.NA, pd.NA])
        assert pd.isna(longest_non_null_string(s))

    def test_single_value(self):
        s = pd.Series(["H2a1"])
        assert longest_non_null_string(s) == "H2a1"

    def test_ties_return_one_of_the_longest(self):
        s = pd.Series(["AB", "CD"])
        assert longest_non_null_string(s) == "AB"