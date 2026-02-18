#!/usr/bin/env bash
# brave-search-carvana.sh
# Reusable script to search Brave API for Carvana vehicle listings
# and extract structured data (URLs, titles, descriptions) from results.
#
# Usage:
#   ./brave-search-carvana.sh                    # Run all default queries
#   ./brave-search-carvana.sh "custom query"     # Run a single custom query
#   BRAVE_API_KEY=xxx ./brave-search-carvana.sh  # Override API key
#
# Output: JSON lines to stdout, one per search result, with fields:
#   url, title, description, query
#
# Rate limiting: Brave free plan allows 1 req/sec. The script sleeps
# between queries to stay within limits.

set -euo pipefail

BRAVE_API_KEY="${BRAVE_API_KEY:?Set BRAVE_API_KEY environment variable}"
BRAVE_SEARCH_URL="https://api.search.brave.com/res/v1/web/search"
RESULT_COUNT="${BRAVE_RESULT_COUNT:-20}"
RATE_LIMIT_SLEEP="${BRAVE_RATE_SLEEP:-1.5}"
OUTPUT_DIR="${BRAVE_OUTPUT_DIR:-/tmp/brave-search-results}"

mkdir -p "$OUTPUT_DIR"

# Default queries if none provided on command line
DEFAULT_QUERIES=(
  # Toyota RAV4
  "site:carvana.com 2021 Toyota RAV4 under 55000 miles"
  "site:carvana.com 2020 Toyota RAV4 under 55000 miles"
  "site:carvana.com 2022 Toyota RAV4 under 55000 miles"
  "carvana RAV4 2020 2021 2022 price mileage"
  # Porsche Macan
  "site:carvana.com Porsche Macan 2019 2020 2021 under 55000 miles"
  "carvana Porsche Macan 2019 2020 price mileage"
  "site:carvana.com Porsche Macan S 2019 2020 under 50000"
  # Acura RDX
  "site:carvana.com Acura RDX 2020 2021 2022 under 55000 miles"
  "carvana Acura RDX 2020 2021 price mileage"
  # Other popular SUVs
  "carvana SUV under 27000 low mileage 2020 2021 2022"
  "site:carvana.com Mazda CX-5 2020 2021 2022 under 55000 miles"
  "site:carvana.com Honda CR-V 2020 2021 2022 under 55000 miles"
  "site:carvana.com Hyundai Tucson 2021 2022 under 55000 miles"
)

# ---- Functions ----

urlencode() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
}

search_brave() {
  local query="$1"
  local encoded
  encoded=$(urlencode "$query")

  curl -s "${BRAVE_SEARCH_URL}?q=${encoded}&count=${RESULT_COUNT}" \
    -H "Accept: application/json" \
    -H "X-Subscription-Token: ${BRAVE_API_KEY}"
}

extract_results() {
  # Takes raw JSON on stdin, query as $1
  # Outputs JSON lines with url, title, description, query
  local query="$1"
  python3 -c "
import json, sys

query = sys.argv[1]
data = json.load(sys.stdin)

# Check for errors
if data.get('type') == 'ErrorResponse':
    err = data.get('error', {})
    print(json.dumps({
        'error': True,
        'status': err.get('status'),
        'detail': err.get('detail'),
        'query': query
    }))
    sys.exit(1)

results = data.get('web', {}).get('results', [])
for r in results:
    out = {
        'url': r.get('url', ''),
        'title': r.get('title', ''),
        'description': r.get('description', ''),
        'query': query
    }
    print(json.dumps(out))
" "$query"
}

extract_carvana_listings() {
  # Filter JSON lines on stdin for carvana.com URLs only
  # and parse vehicle details from title/description
  python3 -c "
import json, sys, re

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        rec = json.loads(line)
    except json.JSONDecodeError:
        continue

    url = rec.get('url', '')
    if 'carvana.com' not in url:
        continue

    title = rec.get('title', '')
    desc = rec.get('description', '')

    # Try to extract price from description
    prices = re.findall(r'\\\$([0-9,]+(?:\.[0-9]{2})?)', desc)
    # Try to extract mileage from description
    miles = re.findall(r'([0-9,]+k?\s*miles?)', desc, re.IGNORECASE)

    rec['extracted_prices'] = prices
    rec['extracted_mileages'] = miles
    print(json.dumps(rec))
"
}

# ---- Main ----

if [[ $# -gt 0 ]]; then
  QUERIES=("$@")
else
  QUERIES=("${DEFAULT_QUERIES[@]}")
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RAW_FILE="${OUTPUT_DIR}/raw_${TIMESTAMP}.jsonl"
CARVANA_FILE="${OUTPUT_DIR}/carvana_${TIMESTAMP}.jsonl"
SUMMARY_FILE="${OUTPUT_DIR}/summary_${TIMESTAMP}.txt"

echo "Brave Search -> Carvana listing extractor"
echo "=========================================="
echo "Queries: ${#QUERIES[@]}"
echo "Results per query: ${RESULT_COUNT}"
echo "Output dir: ${OUTPUT_DIR}"
echo ""

total_results=0
total_carvana=0

for i in "${!QUERIES[@]}"; do
  query="${QUERIES[$i]}"
  echo "[$(( i + 1 ))/${#QUERIES[@]}] Searching: ${query}"

  # Rate limit (skip sleep on first query)
  if [[ $i -gt 0 ]]; then
    sleep "$RATE_LIMIT_SLEEP"
  fi

  raw_json=$(search_brave "$query")

  # Check for rate limit / error
  if echo "$raw_json" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('type')=='ErrorResponse' else 1)" 2>/dev/null; then
    echo "  ERROR: Rate limited or API error. Waiting 5s and retrying..."
    sleep 5
    raw_json=$(search_brave "$query")
  fi

  # Extract and save
  results=$(echo "$raw_json" | extract_results "$query" 2>/dev/null || echo "")
  if [[ -z "$results" ]]; then
    echo "  No results or error"
    continue
  fi

  count=$(echo "$results" | wc -l)
  echo "$results" >> "$RAW_FILE"

  carvana_results=$(echo "$results" | extract_carvana_listings)
  carvana_count=0
  if [[ -n "$carvana_results" ]]; then
    carvana_count=$(echo "$carvana_results" | wc -l)
    echo "$carvana_results" >> "$CARVANA_FILE"
  fi

  echo "  Found ${count} results, ${carvana_count} from carvana.com"
  total_results=$(( total_results + count ))
  total_carvana=$(( total_carvana + carvana_count ))
done

echo ""
echo "=========================================="
echo "Total results: ${total_results}"
echo "Carvana results: ${total_carvana}"
echo ""
echo "Raw results:     ${RAW_FILE}"
echo "Carvana results: ${CARVANA_FILE}"

# Generate summary
{
  echo "Brave Search Results Summary - $(date)"
  echo "========================================"
  echo "Total results: ${total_results}"
  echo "Carvana results: ${total_carvana}"
  echo ""
  echo "--- Carvana URLs with extracted data ---"
  if [[ -f "$CARVANA_FILE" ]]; then
    python3 -c "
import json, sys

seen_urls = set()
for line in open(sys.argv[1]):
    rec = json.loads(line.strip())
    url = rec['url']
    if url in seen_urls:
        continue
    seen_urls.add(url)
    prices = rec.get('extracted_prices', [])
    miles = rec.get('extracted_mileages', [])
    print(f'  URL: {url}')
    print(f'  Title: {rec[\"title\"]}')
    if prices:
        print(f'  Prices: {\", \".join(prices)}')
    if miles:
        print(f'  Mileage: {\", \".join(miles)}')
    print()
" "$CARVANA_FILE"
  fi
} > "$SUMMARY_FILE"

echo "Summary:         ${SUMMARY_FILE}"
echo ""
echo "To generate SQL from these results, run:"
echo "  python3 $(dirname "$0")/brave-to-sql.py ${CARVANA_FILE}"
