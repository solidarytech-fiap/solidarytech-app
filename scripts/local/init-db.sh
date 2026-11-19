#!/bin/sh
# Executado pelo entrypoint do postgres na primeira inicializacao.
set -e
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE ngo_db;"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE donation_db;"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d ngo_db -f /sql/ngo.sql
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d donation_db -f /sql/donation.sql
