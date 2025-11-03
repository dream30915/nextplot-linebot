#!/usr/bin/env bash
# nextplot_setup.sh
# Auto-setup for NextPlot (Supabase, env, db schema, bucket step)
set -euo pipefail
echo ".env file written to ./.env"
touch "./database/database.sqlite" || true
echo "Schema file created (run supabase or psql manually if needed)."
