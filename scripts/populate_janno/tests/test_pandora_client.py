"""Tests for SQL construction in PandoraClient (no live DB connection needed)."""
import sqlalchemy
import pytest

from populate_janno.pandora_client import PandoraClient


@pytest.fixture
def fake_metadata():
    """Build an in-memory SQLite schema mirroring the Pandora tables we care about,
    just enough to exercise column reflection in _build_individual_query()."""
    engine = sqlalchemy.create_engine("sqlite:///:memory:")
    metadata = sqlalchemy.MetaData()
    sqlalchemy.Table(
        "TAB_Sample", metadata,
        sqlalchemy.Column("id", sqlalchemy.Integer, primary_key=True),
        sqlalchemy.Column("individual", sqlalchemy.Integer),
        sqlalchemy.Column("Deleted", sqlalchemy.String),
    )
    sqlalchemy.Table(
        "TAB_Individual", metadata,
        sqlalchemy.Column("id", sqlalchemy.Integer, primary_key=True),
        sqlalchemy.Column("site", sqlalchemy.Integer),
        sqlalchemy.Column("Full_Individual_Id", sqlalchemy.String),
        sqlalchemy.Column("Deleted", sqlalchemy.String),
    )
    sqlalchemy.Table(
        "TAB_Site", metadata,
        sqlalchemy.Column("id", sqlalchemy.Integer, primary_key=True),
        sqlalchemy.Column("Deleted", sqlalchemy.String),
    )
    sqlalchemy.Table(
        "TAB_Type", metadata,
        sqlalchemy.Column("id", sqlalchemy.Integer, primary_key=True),
    )
    metadata.create_all(engine)
    return metadata


@pytest.fixture
def client_with_metadata(fake_metadata):
    """A PandoraClient instance with metadata pre-populated, bypassing connect()."""
    client = PandoraClient.__new__(PandoraClient)  # skip __init__, no credentials file needed
    client._metadata = fake_metadata
    client._engine = None
    return client


class TestBuildQuery:
    def test_query_contains_expected_joins(self, client_with_metadata):
        query = client_with_metadata._build_individual_query()
        assert "JOIN TAB_Individual" in query
        assert "JOIN TAB_Site" in query
        assert "JOIN TAB_Type" in query

    def test_query_filters_deleted_rows(self, client_with_metadata):
        query = client_with_metadata._build_individual_query()
        assert "sample.Deleted            =  'false'" in query

    def test_single_string_filter_value(self, client_with_metadata):
        query = client_with_metadata._build_individual_query(column="individual.Full_Individual_Id", values="AAR001")
        assert "AND individual.Full_Individual_Id = 'AAR001'" in query

    def test_list_filter_values_uses_or(self, client_with_metadata):
        query = client_with_metadata._build_individual_query(
            column="individual.Full_Individual_Id", values=["AAR001", "AAR002"]
        )
        assert "`individual.Full_Individual_Id` = 'AAR001'" in query
        assert "`individual.Full_Individual_Id` = 'AAR002'" in query
        assert " OR " in query

    def test_select_clause_prefixes_columns_with_table_alias(self, client_with_metadata):
        query = client_with_metadata._build_individual_query()
        assert "sample.`id` AS `sample.id`" in query
        assert "individual.`Full_Individual_Id` AS `individual.Full_Individual_Id`" in query

    def test_no_metadata_falls_back_to_select_star(self, client_with_metadata):
        client_with_metadata._metadata = None
        query = client_with_metadata._build_individual_query()
        assert "SELECT *" in query


class TestFormatTableName:
    @pytest.mark.parametrize("input_name,expected", [
        ("TAB_Sample", "sample"),
        ("TAB_Individual", "individual"),
        ("NoPrefix", "noprefix"),
    ])
    def test_strips_prefix_and_lowercases(self, input_name, expected):
        assert PandoraClient._format_table_name(input_name) == expected


class TestBuildRawDataQuery:
    def test_uses_exact_equality_not_like(self, client_with_metadata):
        query = client_with_metadata._build_raw_data_query(["AAR001.A0101.RM1.1.Raw_Data"])
        assert "raw_data.`Full_Raw_Data_Id` = 'AAR001.A0101.RM1.1.Raw_Data'" in query
        assert "LIKE" not in query

    def test_multiple_ids_are_or_joined(self, client_with_metadata):
        query = client_with_metadata._build_raw_data_query(["ID1.Raw_Data", "ID2.Raw_Data"])
        assert "= 'ID1.Raw_Data'" in query
        assert "= 'ID2.Raw_Data'" in query
        assert " OR " in query

    def test_raises_on_empty_list(self, client_with_metadata):
        with pytest.raises(ValueError):
            client_with_metadata._build_raw_data_query([])
