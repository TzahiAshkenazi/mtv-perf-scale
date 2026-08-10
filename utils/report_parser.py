import argparse
import json
import os
import sys
import boto3
import requests
import re
import uuid
from datetime import datetime

"""
This Python script performs the following steps:
1. Reads test_result.txt from the specified path.
2. Parses the test results, including VM results.
3. Reads all JSON files in a specified metadata_path_dir and combines them.
4. Combines data into a single JSON document.
5. Adjust datafields to elastic friendly format for timedate and secs
5. Writes the combined JSON to an output file.
6. Uploads the combined JSON to an Elasticsearch index.
7. Mirrors all files in log_dir to a MinIO S3 bucket, preserving the on-disk
   directory structure (starting at 'results/') as the object key prefix.
"""

# # Configuration variables (adjust as needed)
metadata_path_dir = ''
output_json_path = ''
test_result_path = ''
# Result Json
result ={

}
# Elasticsearch config (values injected via bws run or environment variables)
ES_HOST = os.environ.get("ES_URL", "http://elasticsearch.example.com:9200")
ES_INDEX = os.environ.get("ES_INDEX", "mtv")
ES_DOC_ID = None

# MinIO/S3 config (values injected via bws run or environment variables)
MINIO_ENDPOINT_URL = os.environ.get("MINIO_ENDPOINT_URL", "http://minio.example.com:9000")
MINIO_ACCESS_KEY = os.environ.get("MINIO_ACCESS_KEY", "")
MINIO_SECRET_KEY = os.environ.get("MINIO_SECRET_KEY", "")
MINIO_BUCKET_NAME = os.environ.get("MTV_MINIO_BUCKET_NAME", "mtv-bucket")

log_dir = "/mnt/data/logs"  # Directory containing logs to be archived


def extract_value(line: str, key: str) -> str:
    """Safely extract a value for a given key from a line (split by colon)."""
    try:
        return line.split(f"{key}:")[1].split(",")[0].strip()
    except IndexError:
        return ""

def compute_s3_key_prefix(log_directory: str) -> str:
    """Builds an S3 key prefix that mirrors the on-disk results path.

    e.g. '/home/kni/MTV/results/5-0-0-8/1vm-1disk-1tb-820usage-cold-tc2-4/logs/
    1vm-1disk-1tb-820usage-cold-tc2-4_20260808-142034' ->
    'results/5-0-0-8/1vm-1disk-1tb-820usage-cold-tc2-4/logs/
    1vm-1disk-1tb-820usage-cold-tc2-4_20260808-142034'
    """
    match = re.search(r"(results/.+)$", log_directory.rstrip("/"))
    if match:
        return match.group(1)
    # Fallback: never upload directly to the bucket root.
    return os.path.basename(log_directory.rstrip("/"))

def parse_result_path(path: str) -> tuple[str, str, str, str]:
    # Configuration variables (adjust as needed)
    # test_result_path = "/tmp/MTV/results/mtv280-5vms-dsl-cold_20250305-122651/MigrationBreakdown_mtv280-5vms-dsl-cold_20250305-122713.txt"  # Path to your test result TXT file
    # metadata_path_dir = "/tmp/MTV/results/mtv280-5vms-dsl-cold_20250305-122651/.report-artifacts/"   # Directory containing multiple JSON files
    # output_json_path = "/tmp/MTV/results/mtv280-5vms-dsl-cold_20250305-122651/combine_report.json"  # Where to write the final combined JSON
    test_result_path_folder = os.path.dirname(path)
    s3_key_prefix = compute_s3_key_prefix(test_result_path_folder)
    metadata_path_dir = test_result_path_folder + '/.report-artifacts/'   # Directory containing multiple JSON files
    output_json_path = test_result_path_folder + '/.combine_report.json'  # Where to write the final combined JSON
    return test_result_path_folder, s3_key_prefix, metadata_path_dir, output_json_path

 
def parse_test_results(path: str) -> dict:
    """Parse test_result.txt and return a nested dictionary with test_metadata, results_by_vm, env, and sessions."""
    with open(path, "r") as file:
        lines = file.readlines()

    # generate current date time
    from datetime import datetime
    report_timestamp = datetime.now().strftime('%Y-%m-%d %H:%M')

    # Extract general migration metadata
    migration_metadata = {
        "report_date": report_timestamp,
        "result_id": str(uuid.uuid4()),
        "migration": {
            "name": extract_value(lines[3], "MigrationName"),
            "type": extract_value(lines[5], "MigrationType"),
            "status": extract_value(lines[6], "MigrationStatus"),
            "start_time": extract_value(lines[2], "MigrationStartTime"),
            "end_time": extract_value(lines[2], "MigrationEndTime"),
            "duration": extract_value(lines[3], "Total Duration"),
            "total_vms": int(extract_value(lines[3], "Total VMs")) if extract_value(lines[3], "Total VMs").isdigit() else None,
            "namespace": extract_value(lines[4], "TargetNamespace"),
        }
    }

    # Find the start of the VM table
    vm_start_line = None
    for i, line in enumerate(lines):
        if line.startswith("VM "):
            vm_start_line = i + 2
            break

    # Extract VM migration results
    vm_results = []
    if vm_start_line is not None:
        for line in lines[vm_start_line:]:
            parts = line.split()
            if len(parts) < 7:
                continue  # Skip malformed or empty lines

            if parts[0] in ["avg", "min", "max"]:
                # This is one of the summary lines
                summary_type = parts[0]
                migration_metadata["summary"] = migration_metadata.get("summary", {})
                migration_metadata["summary"][f"{summary_type}_migration_time"] = parts[1]
                migration_metadata["summary"][f"{summary_type}_initialize"] = parts[2]
                migration_metadata["summary"][f"{summary_type}_disk_allocation"] = parts[3]
                migration_metadata["summary"][f"{summary_type}_image_conversion"] = parts[4]
                migration_metadata["summary"][f"{summary_type}_disk_transfer_v2v"] = parts[5]
                migration_metadata["summary"][f"{summary_type}_vm_creation"] = parts[6]
            else:
                vm_results.append({
                    "name": parts[0],
                    "migration_time": parts[1],
                    "initialize": parts[2],
                    "disk_allocation": parts[3],
                    "image_conversion": parts[4],
                    "disk_transfer_v2v": parts[5],
                    "vm_creation": parts[6],
                })

    # Return the structured data per user request
    return {
        "test_metadata": {
            "report_date": migration_metadata.get("report_date"),
            "result_id": migration_metadata.get("result_id"),
            "migration": migration_metadata.get("migration", {}),
            "summary": migration_metadata.get("summary", {}),
            "results_by_vm": vm_results,
            "env": {
                "target": {},
                "source": {},
                "source_vm": {}
            },
            "sessions": {}
        }
    }


def parse_metadata_files(metadata_dir: str) -> list:
    """Parse all JSON files in a directory, returning a list of loaded JSON objects."""
    metadata_list = []
    if not os.path.isdir(metadata_dir):
        print(f"Metadata directory not found: {metadata_dir}")
        return metadata_list

    for filename in os.listdir(metadata_dir):
        if filename.lower().endswith(".json"):
            file_path = os.path.join(metadata_dir, filename)
            with open(file_path, "r") as f:
                try:
                    data = json.load(f)
                    metadata_list.append(data)
                except json.JSONDecodeError:
                    print(f"Skipping invalid JSON file: {filename}")
    return metadata_list


def update_test_metadata_env_sessions(test_metadata: dict, metadata_list: list):
    """Check each item in metadata_list for specific keys and store them in test_metadata accordingly."""
    for item in metadata_list:
        if "target_env" in item:
            test_metadata["env"]["target"] = item["target_env"]
        if "source_env" in item:
            test_metadata["env"]["source"] = item["source_env"]
        if "source_vm" in item:
            test_metadata["env"]["source_vm"] = item["source_vm"]["vm_details"]
        if "sessions" in item:
            test_metadata["sessions"] = item["sessions"]


def parse_duration_to_seconds(duration_str: str) -> int:
    """Convert a duration string HH:MM:SS into total seconds."""
    try:
        h, m, s = map(int, duration_str.split(':'))
        return h * 3600 + m * 60 + s
    except ValueError:
        return 0


def calculate_utilized_throughput(test_metadata: dict):
    """Calculate the throughput = total MB / duration in seconds."""
    # Attempt to retrieve the plan_total_util_mb from env.source_vm
    try:
        plan_total_util_mb = float(test_metadata["env"]["source_vm"]["plan_total_util_mb"])
    except (KeyError, ValueError, TypeError):
        plan_total_util_mb = 0.0

    # Convert duration HH:MM:SS to total seconds
    duration_str = test_metadata["migration"].get("duration", "0:0:0")
    duration_secs = parse_duration_to_seconds(duration_str)

    if duration_secs > 0:
        throughput = plan_total_util_mb / duration_secs  # MB per second
        throughput = ("%.1f" % throughput)
    else:
        throughput = 0.0

    # Store the result
    test_metadata["migration"]["utilized_throughput"] = throughput


def upload_to_elasticsearch(es_host: str, es_index: str, doc_id: str | None, doc: dict):
    """Uploads a document to Elasticsearch using an HTTP POST/PUT request."""
    url = f"{es_host}/{es_index}/_doc"
    if doc_id:
        url += f"/{doc_id}"
    try:
        response = requests.post(url, json=doc)
        response.raise_for_status()
        print(f"Successfully uploaded document to Elasticsearch index '{es_index}'")
    except requests.exceptions.RequestException as e:
        print(f"Failed to upload document: {e}")


class S3ArchiveIncompleteError(Exception):
    """Raised when one or more files failed to upload to S3, so the archive
    for this run is partially or entirely missing."""

    def __init__(self, s3_path: str, uploaded: int, failed: int):
        self.s3_path = s3_path
        self.uploaded = uploaded
        self.failed = failed
        super().__init__(
            f"S3 archive incomplete under '{s3_path}': {uploaded} uploaded, {failed} failed"
        )


def upload_logs_to_s3(log_directory: str, bucket_name: str, key_prefix: str,
                       endpoint_url: str, access_key: str, secret_key: str) -> str:
    """Uploads every file under 'log_directory' to S3 (MinIO), preserving the
    directory's relative structure under 'key_prefix' so the bucket layout
    mirrors the on-disk results tree file-for-file.

    Raises S3ArchiveIncompleteError if any file failed to upload (partial or
    total failure) instead of silently reporting the archive as successful.
    """
    s3_client = boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key
    )

    s3_path = f"s3://{bucket_name}/{key_prefix}/"
    uploaded = 0
    failed = 0
    for root, _dirs, files in os.walk(log_directory):
        for filename in files:
            file_path = os.path.join(root, filename)
            rel_path = os.path.relpath(file_path, log_directory)
            key = f"{key_prefix}/{rel_path}"
            try:
                s3_client.upload_file(file_path, bucket_name, key)
                uploaded += 1
            except Exception as e:
                failed += 1
                print(f"[!] Failed to upload '{file_path}' to 's3://{bucket_name}/{key}': {e}")

    if uploaded:
        suffix = f" ({failed} failed)" if failed else ""
        print(f"Successfully uploaded {uploaded} files to '{s3_path}'{suffix}")
    else:
        print(f"Failed to upload any files to '{s3_path}'")

    if failed:
        raise S3ArchiveIncompleteError(s3_path, uploaded, failed)
    return s3_path

def hms_to_seconds(time_str: str) -> int:
    """Converts a time string in HH:MM:SS format to total seconds."""
    if not isinstance(time_str, str):
        return 0
    parts = time_str.split(':')
    if len(parts) != 3:
        return 0
    try:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    except (ValueError, IndexError):
        return 0 # Return 0 if conversion fails

def reformat_date(date_str: str) -> str | None:
    """Converts a date string to ISO 8601 format (UTC)."""
    if not isinstance(date_str, str):
        return None
    date_str = date_str.strip()
    # Try parsing 'YYYY-MM-DD HH:MM:SS' format first
    try:
        dt_obj = datetime.strptime(date_str, '%Y-%m-%d %H:%M:%S')
    except ValueError:
        # Fallback to 'YYYY-MM-DD HH:MM' format
        try:
            dt_obj = datetime.strptime(date_str, '%Y-%m-%d %H:%M')
        except ValueError:
            return None # Return None if all parsing fails
            
    return dt_obj.isoformat() + "Z"

def modify_report_for_elastic(metadata: dict) -> dict:

    if not metadata:
        print("[!] ERROR: 'test_metadata' key not found in the JSON file.")
        return {}

    print("[*] Starting data transformation...")

    # 1. Reformat top-level date
    report_date = metadata.get('report_date')
    if isinstance(report_date, str):
        metadata['report_date'] = reformat_date(report_date)

    # 2. Transform 'migration' object
    if 'migration' in metadata:
        mig = metadata['migration']
        start_time = mig.get('start_time')
        end_time = mig.get('end_time')
        if isinstance(start_time, str):
            mig['start_time'] = reformat_date(start_time)
        if isinstance(end_time, str):
            mig['end_time'] = reformat_date(end_time)
        # Convert duration and rename key
        mig['duration_sec'] = hms_to_seconds(mig.get('duration'))
        mig.pop('duration', None) # Remove old key
        # Convert throughput to float
        if 'utilized_throughput' in mig:
            try:
                mig['utilized_throughput'] = float(mig['utilized_throughput'])
            except (ValueError, TypeError):
                mig['utilized_throughput'] = 0.0

    # 3. Transform 'summary' object
    # Note: The provided sample data includes min/max fields not in the original mapping.
    # This script will convert them anyway for completeness.
    if 'summary' in metadata:
        summary = metadata['summary']
        # Create a new dictionary to hold transformed summary data
        new_summary = {}
        for key, value in summary.items():
            # All summary fields are durations that need conversion
            new_key = f"{key}_sec"
            new_summary[new_key] = hms_to_seconds(value)
        # Replace the old summary with the new one
        metadata['summary'] = new_summary

    # 4. Transform 'results_by_vm' list
    if 'results_by_vm' in metadata:
        for vm_result in metadata['results_by_vm']:
            # Create a new dictionary for the transformed VM result
            new_vm_result = {'name': vm_result.get('name')}
            for key, value in vm_result.items():
                if key != 'name': # Skip the name field
                    new_key = f"{key}_sec"
                    new_vm_result[new_key] = hms_to_seconds(value)
            #Create new list to replace item
            
    # Rebuilding the list to ensure all items are replaced
    if 'results_by_vm' in metadata:
        transformed_vm_list = []
        for vm_result in metadata['results_by_vm']:
            new_vm_result = {'name': vm_result.get('name')}
            for key, value in vm_result.items():
                if key != 'name':
                    new_key = f"{key}_sec"
                    new_vm_result[new_key] = hms_to_seconds(value)
            transformed_vm_list.append(new_vm_result)
        metadata['results_by_vm'] = transformed_vm_list

    print("[+] Transformation complete.")
    return metadata


def main():
    parser = argparse.ArgumentParser(description="Convert test results to JSON with metadata, then upload")
    parser.add_argument("--test-result-path", required=True, help="Path to the test result .txt file.")
    args = parser.parse_args()

    test_result_path_folder, s3_key_prefix, metadata_path_dir, output_json_path = parse_result_path(
        args.test_result_path
    )
   
    # 1. Parse test results => returns a dict with a top-level key 'test_metadata'
    results_data = parse_test_results(args.test_result_path)

    # 2. Parse all JSON files in metadata_path_dir
    metadata_list = parse_metadata_files(metadata_path_dir)

    # 2a. Update results_data['test_metadata'] based on each JSON's content
    update_test_metadata_env_sessions(results_data["test_metadata"], metadata_list)

    # 3. Calculate utilized_throughput
    calculate_utilized_throughput(results_data["test_metadata"])

    # 4. Mirror the results directory to MinIO/S3, preserving its on-disk structure
    try:
        s3_path = upload_logs_to_s3(
            log_directory=test_result_path_folder,
            bucket_name=MINIO_BUCKET_NAME,
            key_prefix=s3_key_prefix,
            endpoint_url=MINIO_ENDPOINT_URL,
            access_key=MINIO_ACCESS_KEY,
            secret_key=MINIO_SECRET_KEY
        )
        s3_archive_status = "complete"
    except S3ArchiveIncompleteError as e:
        print(f"[!] {e}")
        s3_path = e.s3_path
        s3_archive_status = "incomplete"

    # Save S3 path/status in the results_data before writing/ES upload
    results_data["test_metadata"]["s3_archive_path"] = s3_path
    results_data["test_metadata"]["s3_archive_status"] = s3_archive_status

    # Update relevant fields to match Elastic field types 
    results_data = modify_report_for_elastic(results_data['test_metadata'])

    # 5. Write combined JSON to file (kept locally even on incomplete archive, for debugging)
    with open(output_json_path, "w") as file:
        json.dump(results_data, file, indent=4)

    # Don't publish results referencing an incomplete/missing archive.
    if s3_archive_status != "complete":
        print("[!] Skipping Elasticsearch publication because the S3 archive is incomplete.")
        sys.exit(1)

    # 6. Upload combined JSON to Elasticsearch
    upload_to_elasticsearch(
        es_host=ES_HOST,
        es_index=ES_INDEX,
        doc_id=ES_DOC_ID,
        doc=results_data
    )
if __name__ == "__main__":
    main()