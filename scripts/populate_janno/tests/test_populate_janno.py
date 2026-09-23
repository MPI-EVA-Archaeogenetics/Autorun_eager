import pandas as pd
import pytest

from populate_janno.populate_janno import JannoPopulator, parse_args


@pytest.fixture
def fake_janno_path(tmp_path):
    df = pd.DataFrame({
        "Poseidon_ID": ["AAR001.RM"],
        "Genetic_Sex": ["F"],
        "Group_Name": ["MyGroup"],
        "Individual_ID": [pd.NA],
    })
    path = tmp_path / "AAR001.janno"
    df.to_csv(path, sep="\t", index=False)
    return str(path)


@pytest.fixture
def fake_credentials_path(tmp_path):
    path = tmp_path / "credentials.txt"
    path.write_text("host\nport\nlogin\npassword\n")
    return str(path)


@pytest.fixture
def args(fake_janno_path, fake_credentials_path):
    return parse_args(["-i", "AAR001", "-a", "RM", "-j", fake_janno_path, "-c", fake_credentials_path])


class TestFetchPublicationStatus:
    def test_merges_publication_status_by_eager_id(self, args, mocker):
        mocker.patch("populate_janno.eager_run.pH.get_site_id", return_value="AAR001")
        mocker.patch("populate_janno.populate_janno.EagerRun.__init__", return_value=None)
        mocker.patch("populate_janno.populate_janno.EagerRun.version", "1.0.0", create=True)

        populator = JannoPopulator(args)
        populator.eager_run.tsv_table = pd.DataFrame({
            "Sample_Name": ["AAR001"],
            "BAM": ["/a/AAR001.A0101.RM1.1.bam"],
        })

        mocker.patch.object(
            populator.pandora_client, "query_raw_data",
            return_value=pd.DataFrame({
                "raw_data.Full_Raw_Data_Id": ["AAR001.A0101.RM1.1.Data"],
                "raw_data.DOI": ["10.1/abc"],
            }),
        )

        result = populator._fetch_publication_status()

        assert result.loc[0, "Eager_ID"] == "AAR001"
        assert result.loc[0, "Publication_Status"] == "yes"

    def test_no_bams_skips_query_entirely(self, args, mocker):
        mocker.patch("populate_janno.eager_run.pH.get_site_id", return_value="AAR001")
        mocker.patch("populate_janno.populate_janno.EagerRun.__init__", return_value=None)
        mocker.patch("populate_janno.populate_janno.EagerRun.version", "1.0.0", create=True)

        populator = JannoPopulator(args)
        populator.eager_run.tsv_table = pd.DataFrame({
            "Sample_Name": ["AAR001"],
            "BAM": [pd.NA],
        })

        query_spy = mocker.patch.object(populator.pandora_client, "query_raw_data")

        result = populator._fetch_publication_status()

        query_spy.assert_not_called()
        assert result.loc[0, "Publication_Status"] == "no"

    def test_partial_status_when_some_libraries_lack_a_doi(self, args, mocker):
        """
        A sample with two libraries: one has a real DOI, the other's raw data
        entry exists in Pandora but with a missing/NA DOI. This should yield
        'partial', not 'yes' or 'no'.
        """
        mocker.patch("populate_janno.eager_run.pH.get_site_id", return_value="AAR001")
        mocker.patch("populate_janno.populate_janno.EagerRun.__init__", return_value=None)
        mocker.patch("populate_janno.populate_janno.EagerRun.version", "1.0.0", create=True)

        populator = JannoPopulator(args)
        populator.eager_run.tsv_table = pd.DataFrame({
            "Sample_Name": ["AAR001", "AAR001"],
            "BAM": [
                "/a/AAR001.A0101.RM1.1.bam",
                "/a/AAR001.A0102.RM1.1.bam",
            ],
        })

        mocker.patch.object(
            populator.pandora_client, "query_raw_data",
            return_value=pd.DataFrame({
                "raw_data.Full_Raw_Data_Id": [
                    "AAR001.A0101.RM1.1.Data",
                    "AAR001.A0102.RM1.1.Data",
                ],
                "raw_data.DOI": ["10.1/abc", pd.NA],
            }),
        )

        result = populator._fetch_publication_status()

        assert result.loc[0, "Eager_ID"] == "AAR001"
        assert result.loc[0, "Publication_Status"] == "partial"

    def test_multiple_samples_get_independent_statuses(self, args, mocker):
        """
        Confirms 'partial' status for one sample doesn't leak into another
        sample -- i.e. the DOI-presence classification is correctly scoped
        per Sample_Name, not computed globally across the whole tsv_table.
        """
        mocker.patch("populate_janno.eager_run.pH.get_site_id", return_value="AAR001")
        mocker.patch("populate_janno.populate_janno.EagerRun.__init__", return_value=None)
        mocker.patch("populate_janno.populate_janno.EagerRun.version", "1.0.0", create=True)

        populator = JannoPopulator(args)
        populator.eager_run.tsv_table = pd.DataFrame({
            "Sample_Name": ["AAR001", "AAR001", "AAR002"],
            "BAM": [
                "/a/AAR001.A0101.RM1.1.bam",   # AAR001, has DOI
                "/a/AAR001.A0102.RM1.1.bam",   # AAR001, missing DOI -> partial
                "/a/AAR002.A0101.RM1.1.bam",   # AAR002, has DOI -> yes
            ],
        })

        mocker.patch.object(
            populator.pandora_client, "query_raw_data",
            return_value=pd.DataFrame({
                "raw_data.Full_Raw_Data_Id": [
                    "AAR001.A0101.RM1.1.Data",
                    "AAR001.A0102.RM1.1.Data",
                    "AAR002.A0101.RM1.1.Data",
                ],
                "raw_data.DOI": ["10.1/abc", pd.NA, "10.1/def"],
            }),
        )

        result = populator._fetch_publication_status().set_index("Eager_ID")

        assert result.loc["AAR001", "Publication_Status"] == "partial"
        assert result.loc["AAR002", "Publication_Status"] == "yes"
