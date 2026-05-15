#!/usr/bin/env bash
# Download GTEx v10 Whole Blood cis-eQTL allpairs and subset to chr21.
#
# scripts/02_filter_genotypes.R reads the chr21-only parquet at:
#   data/GTEx_Analysis_v10_QTLs_GTEx_Analysis_v10_eQTL_all_associations_Whole_Blood.v10.allpairs.chr21.parquet
#
# This script downloads the genome-wide Whole_Blood allpairs file from GTEx
# v10 (multi-GB), filters to chr21 with python + pyarrow, and writes the
# subset under the filename above. The full-genome download is removed
# afterwards unless KEEP_FULL=1 is set.
#
# Requirements:
#   - curl
#   - python3 with pyarrow (`pip install pyarrow`)

set -euo pipefail

DATA_DIR="data"
FULL_FILE="${DATA_DIR}/Whole_Blood.v10.allpairs.parquet"
CHR21_FILE="${DATA_DIR}/GTEx_Analysis_v10_QTLs_GTEx_Analysis_v10_eQTL_all_associations_Whole_Blood.v10.allpairs.chr21.parquet"
GTEX_URL="https://storage.googleapis.com/adult-gtex/bulk-qtl/v10/single-tissue-cis-qtl/GTEx_Analysis_v10_eQTL_all_associations/Whole_Blood.v10.allpairs.parquet"

mkdir -p "${DATA_DIR}"

if [ -f "${CHR21_FILE}" ]; then
    echo "chr21 subset already present: ${CHR21_FILE}"
    echo "Delete it first if you want to re-download / re-extract."
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 not found. Required to subset the parquet to chr21."
    exit 1
fi

if ! python3 -c "import pyarrow" >/dev/null 2>&1; then
    echo "ERROR: python3 pyarrow module not found."
    echo "Install with: pip install pyarrow"
    exit 1
fi

if [ ! -f "${FULL_FILE}" ]; then
    echo "Downloading GTEx v10 Whole_Blood allpairs (multi-GB)..."
    echo "  URL: ${GTEX_URL}"
    curl -L --fail -o "${FULL_FILE}" "${GTEX_URL}"
else
    echo "Found existing ${FULL_FILE}; skipping download."
fi

if [ ! -s "${FULL_FILE}" ]; then
    echo "ERROR: ${FULL_FILE} is missing or empty after download."
    exit 1
fi

echo "Filtering to chr21 -> ${CHR21_FILE}"
python3 - "${FULL_FILE}" "${CHR21_FILE}" <<'PY'
import sys
import pyarrow.parquet as pq
import pyarrow.compute as pc

src, dst = sys.argv[1], sys.argv[2]
table = pq.read_table(src)
# GTEx v10 variant_id format: "chr21_<pos>_<ref>_<alt>_b38"
mask = pc.starts_with(table["variant_id"], "chr21_")
table_chr21 = table.filter(mask)
pq.write_table(table_chr21, dst)
print(f"Wrote {table_chr21.num_rows:,} chr21 rows to {dst}")
PY

if [ "${KEEP_FULL:-0}" != "1" ]; then
    echo "Removing full-genome file (set KEEP_FULL=1 to retain)."
    rm -f "${FULL_FILE}"
fi

echo "Done. Pipeline-ready chr21 allpairs at: ${CHR21_FILE}"
