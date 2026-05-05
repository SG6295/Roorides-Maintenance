#!/usr/bin/env bash
set -euo pipefail

# cd to nvs-maintenance/ regardless of where the script is invoked from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"

# Load vars from .env.local if not already in environment
if [[ -f .env.local ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    varname="${line%%=*}"
    [[ -z "${!varname:-}" ]] && export "$line"
  done < .env.local
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL not set and not found in .env.local" >&2
  exit 1
fi

mkdir -p docs

echo "→ Dumping schema to docs/schema.sql…"
/opt/homebrew/opt/libpq/bin/pg_dump --schema-only "$DATABASE_URL" \
  | sed '/^\\restrict/d; /^\\unrestrict/d' \
  > docs/schema.sql

echo "→ Generating TypeScript types to src/types/database.types.ts…"
supabase gen types typescript --project-id awbovpblaxwpsuclpiyh > src/types/database.types.ts

echo "✓ Done."
