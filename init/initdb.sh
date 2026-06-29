#!/bin/bash
# Initialize Guacamole database schema
# This script generates and applies the MySQL schema for Guacamole.
# It uses the official guacamole image to generate the SQL.
#
# Usage:
#   ./init/initdb.sh              # Generate and apply
#   ./init/initdb.sh --generate   # Only generate initdb.sql
#   ./init/initdb.sh --apply      # Only apply initdb.sql to MySQL

set -e

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpass}"
MYSQL_DATABASE="${MYSQL_DATABASE:-guacamole_db}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${SCRIPT_DIR}/initdb.sql"

generate() {
    echo "Generating Guacamole MySQL schema..."
    docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --mysql > "$OUTPUT"
    echo "Schema saved to $OUTPUT ($(wc -l < "$OUTPUT") lines)"
}

apply() {
    if [ ! -f "$OUTPUT" ]; then
        echo "File $OUTPUT not found. Run './init/initdb.sh --generate' first."
        exit 1
    fi
    echo "Applying schema to MySQL..."
    docker exec -i lab-mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" < "$OUTPUT"
    echo "Schema applied successfully."
}

case "${1:-}" in
    --generate) generate ;;
    --apply)    apply ;;
    *)
        generate
        apply
        ;;
esac
