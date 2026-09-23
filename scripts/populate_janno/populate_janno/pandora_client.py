"""Everything related to connecting to and querying the Pandora MySQL database."""
import sys
import pandas as pd
import sqlalchemy


class PandoraClient:
    """Owns credentials + connection + query construction for Pandora."""

    TABLES = ["TAB_Sample", "TAB_Individual", "TAB_Site", "TAB_Type"]

    def __init__(self, credentials_file: str):
        self.credentials = self._read_credentials(credentials_file)
        self._engine = None
        self._metadata = None

    @staticmethod
    def _read_credentials(cred_file: str) -> dict:
        with open(cred_file, "r") as c:
            lines = c.readlines()
        return {
            "host": lines[0].strip(),
            "port": lines[1].strip(),
            "login": lines[2].strip(),
            "password": lines[3].strip(),
        }

    def connect(self) -> None:
        conn_str = (
            f"mysql+pymysql://{self.credentials['login']}:{self.credentials['password']}"
            f"@{self.credentials['host']}:{self.credentials['port']}/pandora"
        )
        self._engine = sqlalchemy.create_engine(conn_str)
        self._metadata = sqlalchemy.MetaData()
        self._metadata.reflect(bind=self._engine)
        try:
            pd.read_sql_query("SELECT 1", self._engine)
            print("[PandoraClient]: Successfully connected to Pandora database")
        except Exception as e:
            print(e)
            print("[PandoraClient]: Error connecting to Pandora database")
            sys.exit(1)

    @staticmethod
    def _format_table_name(name: str) -> str:
        return name.removeprefix("TAB_").lower()

    def _build_individual_query(self, column: str = None, values=None) -> str:
        filter_query = ""
        if not column:
            print("[PandoraClient]: No column provided, no filtering applied.")
        elif isinstance(values, str):
            filter_query = f"    AND {column} = '{values}'"
        elif isinstance(values, list):
            sep = "\n         OR "
            clauses = [f"`{column}` = '{v}'" for v in values]
            filter_query = "AND (\n            " + sep.join(clauses) + "\n        )"

        if self._metadata is None:
            select_clause = "SELECT *"
        else:
            cols = []
            for table_name in self.TABLES:
                alias = self._format_table_name(table_name)
                table = self._metadata.tables[table_name]
                cols += [f"{alias}.`{c.name}` AS `{alias}.{c.name}`" for c in table.columns]
            select_clause = "SELECT\n" + ",\n".join(cols)

        return f"""
        {select_clause}
        FROM
             TAB_Sample     AS sample
        JOIN TAB_Individual AS individual ON sample.individual = individual.id
        JOIN TAB_Site       AS site       ON individual.site   = site.id
        JOIN TAB_Type       AS type       ON sample.type       = type.id
        WHERE
            sample.Deleted            =  'false'
            AND individual.Deleted    =  'false'
            AND site.Deleted          =  'false'
            {filter_query}
        ORDER BY individual.Full_Individual_Id;
        """

    def query(self, filter_column: str = "individual.Full_Individual_Id", filter_values=None) -> pd.DataFrame:
        if self._engine is None:
            self.connect()
        print("[PandoraClient]: Making request to Pandora SQL server")
        result = pd.read_sql_query(self._build_individual_query(column=filter_column, values=filter_values), self._engine)
        print("[PandoraClient]: All samples and metadata successfully retrieved")
        return result

    def _build_raw_data_query(self, raw_data_ids: list) -> str:
        """
        Build a SQL query to retrieve Full_Raw_Data_Id and DOI from Pandora's
        TAB_Raw_Data table, for entries whose Full_Raw_Data_Id exactly matches one
        of the given raw_data_ids.
        """
        if not raw_data_ids:
            raise ValueError("raw_data_ids must be a non-empty list.")

        sep = "\n         OR "
        clauses = [f"raw_data.`Full_Raw_Data_Id` = '{rid}'" for rid in raw_data_ids]
        filter_query = "AND (\n            " + sep.join(clauses) + "\n        )"

        return f"""
        SELECT
            raw_data.`Full_Raw_Data_Id` AS `raw_data.Full_Raw_Data_Id`,
            raw_data.`DOI`              AS `raw_data.DOI`
        FROM
            TAB_Raw_Data AS raw_data
        WHERE
            raw_data.Deleted = 'false'
            {filter_query}
        ORDER BY raw_data.Full_Raw_Data_Id;
        """

    def query_raw_data(self, raw_data_ids: list) -> pd.DataFrame:
        """
        Retrieve Full_Raw_Data_Id and DOI from Pandora's TAB_Raw_Data table, for
        entries whose Full_Raw_Data_Id exactly matches one of the given raw_data_ids.
        """
        if self._engine is None:
            self.connect()
        print("[PandoraClient]: Making request to Pandora SQL server for raw data")
        query_string = self._build_raw_data_query(raw_data_ids)
        result = pd.read_sql_query(query_string, self._engine)
        print("[PandoraClient]: Raw data successfully retrieved")
        return result
