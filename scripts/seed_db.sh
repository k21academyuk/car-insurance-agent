#!/usr/bin/env bash
set -e
docker compose exec backend alembic upgrade head
docker compose exec backend python -m app.database.seed
echo "DB seeded ✓"
