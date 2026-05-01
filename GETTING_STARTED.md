# Getting Started — AutoShield AI

## Step 1 — Prerequisites
- Python 3.12+, Node 20+, Docker, OpenAI API key

## Step 2 — Clone & configure
```bash
git clone https://github.com/prashant9501/autoshield-ai.git
cd autoshield-ai
cp backend/.env.example backend/.env
# Edit backend/.env and add OPENAI_API_KEY
```

## Step 3 — Spin up Docker stack
```bash
cd deployment/docker
docker compose up -d
```

## Step 4 — Initialize data
```bash
docker compose exec backend alembic upgrade head
docker compose exec backend python -m app.database.seed
docker compose exec backend python scripts/ingest_kb.py
docker compose exec backend python -m app.ml_models.train_risk
docker compose exec backend python -m app.ml_models.train_fraud
```

## Step 5 — Open
- Frontend: http://localhost:3000
- API docs: http://localhost:8000/docs
- Grafana: http://localhost:3001 (admin/admin)

## Phase-by-phase build
See README → Roadmap.
