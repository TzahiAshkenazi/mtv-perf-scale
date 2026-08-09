import io
import os
import sys
import unittest
from contextlib import redirect_stdout
from unittest.mock import MagicMock, call, patch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import report_parser  # noqa: E402


class ComputeS3KeyPrefixTests(unittest.TestCase):
    def test_matches_example_from_scale_lab_host(self):
        log_directory = (
            "/home/kni/MTV/results/5-0-0-8/1vm-1disk-1tb-820usage-cold-tc2-4/"
            "logs/1vm-1disk-1tb-820usage-cold-tc2-4_20260808-142034"
        )
        expected = (
            "results/5-0-0-8/1vm-1disk-1tb-820usage-cold-tc2-4/"
            "logs/1vm-1disk-1tb-820usage-cold-tc2-4_20260808-142034"
        )
        self.assertEqual(report_parser.compute_s3_key_prefix(log_directory), expected)

    def test_strips_trailing_slash(self):
        log_directory = "/home/kni/MTV/results/5-0-0-8/dsl-4-small/logs/dsl-4-small_20250531-233720/"
        expected = "results/5-0-0-8/dsl-4-small/logs/dsl-4-small_20250531-233720"
        self.assertEqual(report_parser.compute_s3_key_prefix(log_directory), expected)

    def test_falls_back_to_basename_when_no_results_segment(self):
        log_directory = "/tmp/some-other-dir/dsl-4-small_20250531-233720"
        self.assertEqual(
            report_parser.compute_s3_key_prefix(log_directory),
            "dsl-4-small_20250531-233720",
        )


class UploadLogsToS3Tests(unittest.TestCase):
    def _write(self, root, relative_path, contents=b"data"):
        full_path = os.path.join(root, relative_path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        with open(full_path, "wb") as f:
            f.write(contents)
        return full_path

    def test_mirrors_nested_directory_structure_as_s3_keys(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmp_dir:
            self._write(tmp_dir, "1vm-1disk-1tb-820usage-cold-tc2-4_STDOUT.log")
            self._write(tmp_dir, "MigrationBreakdown_1vm-1disk-1tb-820usage-cold-tc2-4_20260808-142034.txt")
            self._write(tmp_dir, os.path.join("METRICS", "esx1-NetworkTransmitRate.csv"))

            key_prefix = (
                "results/5-0-0-8/1vm-1disk-1tb-820usage-cold-tc2-4/"
                "logs/1vm-1disk-1tb-820usage-cold-tc2-4_20260808-142034"
            )

            mock_s3_client = MagicMock()
            with patch.object(report_parser.boto3, "client", return_value=mock_s3_client) as mock_client_factory:
                s3_path = report_parser.upload_logs_to_s3(
                    log_directory=tmp_dir,
                    bucket_name="mtv-bucket",
                    key_prefix=key_prefix,
                    endpoint_url="http://minio.example.com:9000",
                    access_key="key",
                    secret_key="secret",
                )

            mock_client_factory.assert_called_once_with(
                "s3",
                endpoint_url="http://minio.example.com:9000",
                aws_access_key_id="key",
                aws_secret_access_key="secret",
            )

            self.assertEqual(s3_path, f"s3://mtv-bucket/{key_prefix}/")

            expected_calls = [
                call(
                    os.path.join(tmp_dir, "1vm-1disk-1tb-820usage-cold-tc2-4_STDOUT.log"),
                    "mtv-bucket",
                    f"{key_prefix}/1vm-1disk-1tb-820usage-cold-tc2-4_STDOUT.log",
                ),
                call(
                    os.path.join(
                        tmp_dir,
                        "MigrationBreakdown_1vm-1disk-1tb-820usage-cold-tc2-4_20260808-142034.txt",
                    ),
                    "mtv-bucket",
                    f"{key_prefix}/MigrationBreakdown_1vm-1disk-1tb-820usage-cold-tc2-4_20260808-142034.txt",
                ),
                call(
                    os.path.join(tmp_dir, "METRICS", "esx1-NetworkTransmitRate.csv"),
                    "mtv-bucket",
                    f"{key_prefix}/METRICS/esx1-NetworkTransmitRate.csv",
                ),
            ]
            mock_s3_client.upload_file.assert_has_calls(expected_calls, any_order=True)
            self.assertEqual(mock_s3_client.upload_file.call_count, 3)

    def test_continues_uploading_after_a_single_file_failure(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmp_dir:
            self._write(tmp_dir, "good.log")
            self._write(tmp_dir, "bad.log")

            mock_s3_client = MagicMock()
            mock_s3_client.upload_file.side_effect = [None, Exception("boom")]

            captured = io.StringIO()
            with patch.object(report_parser.boto3, "client", return_value=mock_s3_client):
                with redirect_stdout(captured):
                    report_parser.upload_logs_to_s3(
                        log_directory=tmp_dir,
                        bucket_name="mtv-bucket",
                        key_prefix="results/5-0-0-8/dsl-4-small/logs/dsl-4-small_20250531-233720",
                        endpoint_url="http://minio.example.com:9000",
                        access_key="key",
                        secret_key="secret",
                    )

            self.assertEqual(mock_s3_client.upload_file.call_count, 2)
            output = captured.getvalue()
            self.assertIn("Successfully uploaded 1 files", output)
            self.assertIn("1 failed", output)

    def test_reports_failure_when_no_files_uploaded(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmp_dir:
            self._write(tmp_dir, "only.log")

            mock_s3_client = MagicMock()
            mock_s3_client.upload_file.side_effect = Exception("boom")

            captured = io.StringIO()
            with patch.object(report_parser.boto3, "client", return_value=mock_s3_client):
                with redirect_stdout(captured):
                    report_parser.upload_logs_to_s3(
                        log_directory=tmp_dir,
                        bucket_name="mtv-bucket",
                        key_prefix="results/5-0-0-8/dsl-4-small/logs/dsl-4-small_20250531-233720",
                        endpoint_url="http://minio.example.com:9000",
                        access_key="key",
                        secret_key="secret",
                    )

            output = captured.getvalue()
            self.assertNotIn("Successfully uploaded", output)
            self.assertIn("Failed to upload any files", output)


if __name__ == "__main__":
    unittest.main()
