#!/bin/bash
# sync-openapi.sh
# Copies the filtered OpenAPI spec from uplint-service to the docs directory
# and converts it to Mintlify-compatible OpenAPI 3.0.3 format.
#
# The uplint-service generates a filtered spec at docs/openapi.json
# that only contains public-facing endpoints (Files, File Contexts, API Keys).
# This script copies it and converts 3.1.0 → 3.0.3 for Mintlify compatibility.
#
# Usage:
#   ./scripts/sync-openapi.sh
#
# Prerequisites:
#   - uplint-service repo must be at ../uplint-service relative to metricall-docs/docs/
#   OR set UPLINT_SERVICE_PATH environment variable
#   - Python 3 must be available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="$(dirname "$SCRIPT_DIR")"
DEST="$DOCS_DIR/api-reference/openapi.json"

# Determine uplint-service path
if [ -n "${UPLINT_SERVICE_PATH:-}" ]; then
  SOURCE="$UPLINT_SERVICE_PATH/docs/openapi.json"
else
  # Try common relative paths
  for candidate in \
    "$DOCS_DIR/../../uplint-service/docs/openapi.json" \
    "$DOCS_DIR/../../../uplint-service/docs/openapi.json" \
    "$HOME/uplint-service/docs/openapi.json"; do
    if [ -f "$candidate" ]; then
      SOURCE="$candidate"
      break
    fi
  done
fi

if [ -z "${SOURCE:-}" ] || [ ! -f "$SOURCE" ]; then
  echo "Error: Could not find uplint-service OpenAPI spec."
  echo "Set UPLINT_SERVICE_PATH or ensure uplint-service is at a sibling directory."
  exit 1
fi

echo "Syncing OpenAPI spec..."
echo "  From: $SOURCE"
echo "  To:   $DEST"

# Convert 3.1.0 → 3.0.3 for Mintlify compatibility
# Fixes: version downgrade + $ref with sibling properties → allOf wrapper
python3 -c "
import json, sys

def fix_ref_siblings(obj):
    if isinstance(obj, dict):
        if '\$ref' in obj and len(obj) > 1:
            ref_val = obj.pop('\$ref')
            obj['allOf'] = [{'\$ref': ref_val}]
            for key in list(obj.keys()):
                if key != 'allOf':
                    obj[key] = fix_ref_siblings(obj[key])
            return obj
        else:
            for key in list(obj.keys()):
                obj[key] = fix_ref_siblings(obj[key])
            return obj
    elif isinstance(obj, list):
        return [fix_ref_siblings(item) for item in obj]
    return obj

with open('$SOURCE') as f:
    spec = json.load(f)

original_version = spec.get('openapi', 'unknown')
spec['openapi'] = '3.0.3'

if 'paths' in spec:
    spec['paths'] = fix_ref_siblings(spec['paths'])
if 'components' in spec:
    spec['components'] = fix_ref_siblings(spec['components'])

with open('$DEST', 'w') as f:
    json.dump(spec, f, indent=2)

print(f'  Converted: {original_version} → 3.0.3')
"

echo ""
echo "Done. OpenAPI spec synced and converted."
echo ""
echo "Endpoints included:"
grep -o '"summary": "[^"]*"' "$DEST" | sed 's/"summary": "/ - /' | sed 's/"$//' | sort
