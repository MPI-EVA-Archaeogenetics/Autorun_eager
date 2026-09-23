"""Shared fixtures for the populate_janno test suite."""
import pandas as pd
import pytest


@pytest.fixture
def sample_library_group() -> pd.DataFrame:
    """A small library-level group, as would be passed to weighted_mean()."""
    return pd.DataFrame({
        "wt": [10, 20, 30],
        "val": [1.0, 2.0, 3.0],
        "filter_col": [150, 50, 120],  # second row should get excluded at min_val=100
    })