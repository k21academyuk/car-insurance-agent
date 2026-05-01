# 🚗 AutoShield AI — Multi-Agent Car Insurance Platform

> **Capstone Project** — A production-grade agentic AI system that handles the entire car insurance lifecycle (quote → underwriting → policy issuance → claims with damage AI → fraud detection → renewal) using **LangGraph supervisor pattern** with 6 specialized sub-agents, multimodal inputs, human-in-the-loop interrupts, and full observability.

[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)](https://python.org)
[![LangGraph](https://img.shields.io/badge/LangGraph-0.2+-1C3C3C)](https://langchain-ai.github.io/langgraph/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Next.js](https://img.shields.io/badge/Next.js-14-000000?logo=next.js&logoColor=white)](https://nextjs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](https://postgresql.org)
[![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)](https://docker.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📑 Table of Contents

1. [Why This Project](#-why-this-project)
2. [Demo](#-demo)
3. [Key Features](#-key-features)
4. [System Architecture](#-system-architecture)
5. [The 6 Agents](#-the-6-agents)
6. [Tool Inventory](#-tool-inventory)
7. [Tech Stack](#-tech-stack)
8. [Indian Insurance Domain Concepts](#-indian-insurance-domain-concepts)
9. [Project Structure](#-project-structure)
10. [Quick Start](#-quick-start)
11. [Configuration](#-configuration)
12. [API Reference](#-api-reference)
13. [LangGraph State Schema](#-langgraph-state-schema)
14. [Human-in-the-Loop Workflow](#-human-in-the-loop-workflow)
15. [Evaluation & Testing](#-evaluation--testing)
16. [Observability](#-observability)
17. [Deployment](#-deployment)
18. [Roadmap](#-roadmap)
19. [Learning Outcomes](#-learning-outcomes)

---

## 🎯 Why This Project

Most "AI agent" tutorials build a single ReAct loop with 2–3 tools and call it a day. **AutoShield AI** is different — it's a faithful simulation of how a real insurance company would deploy agentic AI in production:

- **Hierarchical multi-agent**, not a single mega-prompt
- **Multimodal** — vision actually does work (damage classification, RC/license OCR)
- **Domain depth** — uses real Indian insurance vocabulary (IDV, NCB, IRDAI, FNOL, OD/TP)
- **Human-in-the-loop** for high-value decisions using LangGraph `interrupt`
- **Real ML models** wrapped as tools, not "everything is an LLM call"
- **Production concerns** — checkpointing, resumability, evaluation, tracing, deployment

This isn't a toy. It's the kind of system you can demo in a job interview and have a real architectural conversation about.

---

## 🎬 Demo

| Flow | Walkthrough |
|---|---|
| 🆕 Get a quote | User describes their car → Quote Agent collects details → returns 3-tier premium (TP / Comprehensive / Zero-Dep) |
| 📄 Buy a policy | Upload RC book + driver's license photos → Vision OCR extracts data → Policy PDF generated and emailed |
| 🚨 File a claim | Upload damage photos → Vision model classifies severity → estimates payout → routes to nearest network garage; high-value claims trigger HITL approval |
| 🔍 Fraud check | Background fraud agent scores every claim using ML anomaly detection on customer history, prior claims, image hash reuse |
| 🔁 Renewal | Proactive nudge 30 days before expiry → renewal quote with NCB → retention pitch on cancellation |

> 📹 **Demo video**: [`docs/demo/walkthrough.mp4`](docs/demo/walkthrough.mp4)
> 🌐 **Live demo**: `https://autoshield.example.com` *(after deployment)*

---

## ✨ Key Features

### 🧠 Agentic Intelligence
- **Supervisor pattern** in LangGraph routes user intent to the right specialist agent
- **6 specialist sub-agents** — each owns one stage of the insurance lifecycle
- **Stateful conversations** via LangGraph checkpointing (resumable across sessions)
- **Tool-calling** with structured outputs validated by Pydantic
- **Multi-LLM routing** — GPT-4o for reasoning, Claude Sonnet 4.5 for long policy docs, GPT-4o-mini for cheap tasks

### 👁️ Multimodal
- **Damage image classification** — severity scoring (Minor / Moderate / Severe / Total Loss)
- **RC book OCR** — extracts registration number, owner, chassis, engine, fuel type
- **Driver's license OCR** — extracts name, DL number, DOB, validity, state
- **Image hash deduplication** — detects reused damage photos across claims (fraud signal)

### 🔒 Production Quality
- **Human-in-the-loop interrupts** for claims > ₹50,000 or anomalous patterns
- **Postgres checkpointer** — conversations survive restarts
- **LangSmith + Langfuse tracing** — every tool call, token, and decision is logged
- **RAGAS + DeepEval** — automated evaluation harness with golden datasets
- **Rate limiting, JWT auth, structured logging, Prometheus metrics**

### 📚 Domain Knowledge
- **IRDAI-compliant** policy templates and claim forms
- **IDV (Insured Declared Value)** auto-calculation per IRDAI depreciation slab
- **NCB (No Claim Bonus)** ladder applied on renewals
- **OD vs TP premium split** correctly modeled
- **Pin-code based risk scoring** (urban vs rural, high-claim zones)

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FRONTEND (Next.js 14)                        │
│      Chat UI · File upload · Live agent visualization · Auth         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ REST / WebSocket
┌──────────────────────────────▼──────────────────────────────────────┐
│                    API GATEWAY (FastAPI + NGINX)                     │
│              JWT · Rate Limiting · CORS · Request Logging            │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│                    LANGGRAPH ORCHESTRATOR                            │
│                                                                      │
│                    ┌──────────────────┐                              │
│                    │   SUPERVISOR     │  Intent classification        │
│                    │   (GPT-4o)       │  + agent routing              │
│                    └────────┬─────────┘                              │
│                             │                                        │
│   ┌──────┬───────────┬──────┴──────┬───────────┬───────────┐        │
│   ▼      ▼           ▼             ▼           ▼           ▼         │
│ ┌────┐┌──────┐  ┌─────────┐  ┌────────┐  ┌────────┐  ┌─────────┐    │
│ │QUOT││UNDER-│  │ POLICY  │  │ CLAIMS │  │ FRAUD  │  │RENEWAL/ │    │
│ │ E  ││WRITER│  │ ISSUER  │  │ AGENT  │  │ AGENT  │  │RETENTION│    │
│ └─┬──┘└───┬──┘  └────┬────┘  └───┬────┘  └───┬────┘  └────┬────┘    │
│   │       │          │           │           │            │          │
│   └───────┴──────────┴───────────┴───────────┴────────────┘          │
│                             │                                        │
│                    ┌────────▼─────────┐                              │
│                    │   TOOL LAYER     │                              │
│                    └────────┬─────────┘                              │
└─────────────────────────────┼────────────────────────────────────────┘
                              │
   ┌──────────┬───────────┬───┴───────┬──────────┬──────────────┐
   ▼          ▼           ▼           ▼          ▼              ▼
┌─────┐  ┌────────┐  ┌──────────┐  ┌─────┐  ┌────────┐  ┌──────────┐
│RAG  │  │POSTGRES│  │  REDIS   │  │  S3 │  │ ML     │  │  VISION  │
│Chrm │  │Custmrs │  │ Sessions │  │Images│  │ XGBst  │  │ GPT-4o-V │
│KB   │  │Pol/Clm │  │Rate Lmt  │  │      │  │ Frd    │  │ + YOLO   │
└─────┘  └────────┘  └──────────┘  └─────┘  └────────┘  └──────────┘
```

> 📊 **Detailed diagrams**: [`docs/architecture/`](docs/architecture/)

---

## 🤖 The 6 Agents

### 1️⃣ Quote Agent
**Job**: Help a prospect get a premium quote in under 90 seconds.

**Responsibilities**:
- Collects vehicle details (make, model, variant, year, fuel, RTO)
- Collects driver details (DOB, license validity, prior insurance)
- Calls `idv_calculator` and `premium_calculator` tools
- Returns 3 plan options: **Third-party only**, **Comprehensive**, **Comprehensive + Zero-Dep**
- Saves quote to Postgres with a `quote_id` for resumption

**Tools**: `vehicle_lookup`, `idv_calculator`, `premium_calculator`, `pincode_risk_api`, `save_quote`

### 2️⃣ Underwriting Agent
**Job**: Decide whether to accept the risk, at what premium loading.

**Responsibilities**:
- Pulls customer history (prior claims, prior policies, defaulted payments)
- Calls **XGBoost risk model** (`risk_score_predictor`) trained on synthetic claims data
- Applies underwriting rules (age < 25 → +15%, vehicle age > 10 → loading, high-claim pincode → loading)
- Returns: **Accept** / **Accept with loading** / **Refer to human underwriter** / **Decline**
- For "Refer to human" — triggers `interrupt()` and waits for underwriter decision

**Tools**: `get_customer_history`, `risk_score_predictor`, `pincode_risk_api`, `request_human_approval`

### 3️⃣ Policy Issuance Agent
**Job**: Convert an accepted quote into a live policy.

**Responsibilities**:
- Accepts uploaded **RC book** and **driver's license** images
- Runs OCR via `rc_ocr_extractor` and `license_ocr` (GPT-4o Vision)
- Cross-validates OCR data against quote data (mismatch → escalate)
- Generates policy PDF using IRDAI-compliant template
- Stores policy in Postgres, uploads PDF to S3
- Sends policy via email (and WhatsApp stub)

**Tools**: `rc_ocr_extractor`, `license_ocr`, `validate_documents`, `generate_policy_pdf`, `send_email`, `create_policy`

### 4️⃣ Claims Agent ⭐ *(showcase agent)*
**Job**: Handle FNOL (First Notice of Loss) end-to-end.

**Responsibilities**:
- Verifies policy is active and within coverage
- Accepts **damage photos** (1–6 images) from user
- Calls `damage_image_analyzer` — classifies parts affected and severity per part
- Calls `payout_estimator` — combines part costs + labour from internal cost catalog
- Geo-locates incident (lat/lng or pin code), calls `find_network_garage`
- **If estimated payout > ₹50,000 → triggers HITL interrupt** for human adjuster review
- Generates claim form, assigns `claim_id`, notifies customer

**Tools**: `verify_policy_active`, `damage_image_analyzer`, `payout_estimator`, `find_network_garage`, `weather_api`, `request_human_approval`, `log_claim`, `send_email`

### 5️⃣ Fraud Detection Agent
**Job**: Run in parallel with Claims Agent — score every claim for fraud risk.

**Responsibilities** (Neo4j replaced with Postgres + ML for lighter footprint):
- Image hash deduplication: SHA256 + perceptual hash (`pHash`) of damage photos against historical claims
- Pattern detection via SQL: same garage + same surveyor + 3+ claims in 30 days
- ML anomaly detection: **Isolation Forest** on claim features (claim amount vs IDV, time since policy start, prior claim density)
- Returns fraud score 0.0–1.0; >0.7 → flag, >0.9 → auto-reject + escalate

**Tools**: `image_hash_lookup`, `claim_pattern_query`, `fraud_anomaly_detector`, `flag_claim_suspicious`

### 6️⃣ Renewal & Retention Agent
**Job**: Proactive renewals and save-the-customer flow.

**Responsibilities**:
- Cron-triggered: 30/15/7 days before expiry → drafts renewal quote with NCB applied
- Handles inbound cancellation requests → retention script with discount offer
- A/B test different retention messages (logged for analysis)
- Generates renewal policy seamlessly when customer accepts

**Tools**: `get_expiring_policies`, `apply_ncb_ladder`, `premium_calculator`, `retention_offer_generator`, `send_email`

---

## 🛠️ Tool Inventory

> 17 tools across 6 categories. All tools have Pydantic input/output schemas and are auto-registered via decorators.

| Category | Tool | Purpose |
|---|---|---|
| **RAG** | `policy_kb_search` | Retrieve policy clauses, exclusions, FAQs from ChromaDB |
| | `irdai_regulations_search` | Look up IRDAI guidelines for compliance answers |
| **External APIs** | `vehicle_lookup` | Mock VAHAN API — returns vehicle metadata from registration number |
| | `pincode_risk_api` | Returns risk tier (low/med/high) per pin code |
| | `weather_api` | Validates incident weather context (e.g., flood claims) |
| **ML Models** | `risk_score_predictor` | XGBoost — underwriting risk score |
| | `damage_severity_classifier` | Vision-based damage severity scorer |
| | `fraud_anomaly_detector` | Isolation Forest fraud anomaly score |
| | `premium_calculator` | Rule-based premium calc (OD + TP + GST) |
| **Vision** | `damage_image_analyzer` | GPT-4o Vision — describes damaged parts |
| | `rc_ocr_extractor` | Extracts structured data from RC book photo |
| | `license_ocr` | Extracts structured data from driver's license |
| | `image_hash_lookup` | Perceptual hash dedup against past claims |
| **Database** | `get_customer_history` | Postgres — past policies, claims, payments |
| | `save_quote` / `create_policy` / `log_claim` | CRUD on core entities |
| **Communication** | `generate_policy_pdf` / `generate_claim_pdf` | ReportLab PDFs |
| | `send_email` | SMTP / SendGrid stub |
| **Human-in-Loop** | `request_human_approval` | LangGraph interrupt — pauses graph for human input |

---

## ⚙️ Tech Stack

### Core
- **Language**: Python 3.12, TypeScript 5
- **Orchestration**: [LangGraph](https://langchain-ai.github.io/langgraph/) 0.2+ (supervisor pattern, checkpointing, interrupts)
- **LLMs**: OpenAI **GPT-4o** + **GPT-4o-mini**, Anthropic **Claude Sonnet 4.5**
- **Embeddings**: OpenAI `text-embedding-3-small`

### Data Layer
- **Vector DB**: ChromaDB (policy KB, IRDAI docs, FAQs)
- **Relational**: PostgreSQL 16 (customers, policies, claims, quotes, audit log)
- **Cache / Sessions**: Redis 7
- **Object Storage**: AWS S3 (damage images, policy PDFs)
- **LangGraph Checkpointer**: Postgres-backed (resumable conversations)

### ML & Vision
- **Risk model**: XGBoost (synthetic dataset of 50k claims)
- **Fraud anomaly**: scikit-learn Isolation Forest
- **Vision**: GPT-4o Vision (primary) + optional fine-tuned YOLOv8 for car part detection
- **OCR**: GPT-4o Vision with structured-output prompts
- **Perceptual hashing**: `imagehash` library (pHash + dHash)

### Backend
- **API**: FastAPI 0.115 with Pydantic v2
- **Async**: asyncio, httpx, asyncpg
- **Auth**: JWT (PyJWT) + optional Clerk integration
- **PDF**: ReportLab + Jinja2 templates
- **Background jobs**: Celery + Redis (renewal cron)

### Frontend
- **Framework**: Next.js 14 (App Router) + React 18
- **Styling**: Tailwind CSS + shadcn/ui
- **State**: Zustand + React Query
- **Chat UI**: Custom components with streaming SSE / WebSocket
- **File upload**: react-dropzone with image preview

### Observability
- **LLM tracing**: LangSmith (primary) + Langfuse (self-hosted alternative)
- **Metrics**: Prometheus + Grafana (token spend, latency, agent routing distribution)
- **Logs**: structlog → JSON → Loki
- **Errors**: Sentry

### Evaluation
- **RAG evals**: RAGAS (faithfulness, answer relevancy, context precision)
- **Agent evals**: DeepEval + custom golden dataset (50 scenarios)
- **Regression**: pytest + LangGraph test harness

### DevOps
- **Containers**: Docker + Docker Compose (local) → AWS ECS Fargate (prod)
- **Database**: AWS RDS Postgres + ElastiCache Redis + S3
- **CI/CD**: GitHub Actions (lint, test, build, deploy)
- **IaC**: Terraform (optional, for AWS resources)

---

## 🇮🇳 Indian Insurance Domain Concepts

This project models real Indian motor insurance — not a generic Western template.

| Term | What it means | Where it appears |
|---|---|---|
| **IDV** (Insured Declared Value) | Maximum sum insured = current market value of the car (manufacturer's listed price minus depreciation per IRDAI slab) | Quote Agent — `idv_calculator` |
| **NCB** (No Claim Bonus) | Discount on Own Damage premium for claim-free years (20% → 25% → 35% → 45% → 50%) | Renewal Agent — `apply_ncb_ladder` |
| **OD vs TP** | Premium has two parts: **Own Damage** (your car) and **Third Party** (legally mandatory under Motor Vehicles Act) | Premium calculator |
| **Zero Depreciation** | Add-on cover where claim payout doesn't deduct depreciation on replaced parts | Quote plans |
| **IRDAI** | Insurance Regulatory and Development Authority of India — regulator | Policy templates, KB |
| **FNOL** (First Notice of Loss) | The moment a claim is first reported | Claims Agent entry point |
| **RTO** | Regional Transport Office (e.g., MH-12 for Pune) — affects premium | Vehicle lookup |
| **Cashless garage** | Network garage where insurer pays directly | Claims Agent — `find_network_garage` |
| **Surveyor** | Licensed person who assesses claim damage | Fraud Agent — pattern detection |
| **VAHAN** | Government vehicle registration database | Mocked via `vehicle_lookup` |
| **GST** | 18% GST on motor premiums | Premium calculator |

---

## 📁 Project Structure

```
autoshield-ai/
│
├── backend/
│   ├── app/
│   │   ├── agents/                       # 6 specialist agents
│   │   │   ├── supervisor.py             # Top-level router
│   │   │   ├── quote_agent.py
│   │   │   ├── underwriting_agent.py
│   │   │   ├── policy_agent.py
│   │   │   ├── claims_agent.py
│   │   │   ├── fraud_agent.py
│   │   │   └── renewal_agent.py
│   │   │
│   │   ├── workflows/                    # LangGraph definitions
│   │   │   ├── main_graph.py             # Supervisor + sub-agent wiring
│   │   │   ├── state.py                  # AgentState (Pydantic + TypedDict)
│   │   │   ├── checkpointer.py           # Postgres checkpointer setup
│   │   │   └── interrupts.py             # HITL interrupt handlers
│   │   │
│   │   ├── tools/                        # All 17 tools
│   │   │   ├── rag_tools.py
│   │   │   ├── api_tools.py
│   │   │   ├── ml_tools.py
│   │   │   ├── vision_tools.py
│   │   │   ├── db_tools.py
│   │   │   ├── comm_tools.py
│   │   │   └── hitl_tools.py
│   │   │
│   │   ├── ml_models/                    # ML training + inference
│   │   │   ├── risk_model.py             # XGBoost — underwriting
│   │   │   ├── fraud_model.py            # Isolation Forest
│   │   │   ├── train_risk.py             # Training script
│   │   │   ├── train_fraud.py
│   │   │   └── artifacts/                # .pkl models (gitignored)
│   │   │
│   │   ├── vision/                       # Multimodal pipeline
│   │   │   ├── damage_classifier.py
│   │   │   ├── ocr_rc.py
│   │   │   ├── ocr_license.py
│   │   │   └── image_hash.py             # pHash dedup
│   │   │
│   │   ├── database/
│   │   │   ├── postgres.py               # SQLAlchemy + asyncpg
│   │   │   ├── chroma_client.py
│   │   │   ├── redis_client.py
│   │   │   ├── s3_client.py
│   │   │   ├── schemas.sql               # DDL
│   │   │   └── seed.py                   # Synthetic data seeder
│   │   │
│   │   ├── models/                       # Pydantic schemas
│   │   │   ├── vehicle.py
│   │   │   ├── policy.py
│   │   │   ├── claim.py
│   │   │   ├── customer.py
│   │   │   └── api.py                    # Request/response DTOs
│   │   │
│   │   ├── services/                     # Business logic helpers
│   │   │   ├── premium_calc.py           # IDV + OD + TP + GST
│   │   │   ├── ncb_ladder.py
│   │   │   ├── pdf_generator.py
│   │   │   └── email_service.py
│   │   │
│   │   ├── config/
│   │   │   ├── settings.py               # Pydantic Settings
│   │   │   ├── logging.py                # structlog
│   │   │   └── prompts/                  # All prompts as .txt/.md
│   │   │
│   │   ├── utils/
│   │   │   ├── auth.py                   # JWT
│   │   │   ├── rate_limit.py             # Redis-backed
│   │   │   └── observability.py          # LangSmith + Prometheus
│   │   │
│   │   ├── evals/                        # Evaluation harness
│   │   │   ├── golden_dataset.json       # 50 scenarios
│   │   │   ├── ragas_eval.py
│   │   │   ├── agent_eval.py
│   │   │   └── reports/
│   │   │
│   │   └── main.py                       # FastAPI entrypoint
│   │
│   ├── data/
│   │   ├── knowledge_base/               # PDFs/MDs ingested into ChromaDB
│   │   │   ├── irdai_motor_guidelines.md
│   │   │   ├── policy_terms_template.md
│   │   │   └── faqs.md
│   │   ├── sample_documents/             # Sample RC, license, claim images
│   │   └── damage_images/                # Test damage photos
│   │
│   ├── tests/
│   │   ├── unit/
│   │   │   ├── test_premium_calc.py
│   │   │   ├── test_ncb.py
│   │   │   └── test_tools.py
│   │   └── integration/
│   │       ├── test_quote_flow.py
│   │       ├── test_claim_flow.py
│   │       └── test_hitl_interrupt.py
│   │
│   ├── requirements.txt
│   ├── pyproject.toml
│   ├── alembic.ini                       # DB migrations
│   ├── .env.example
│   └── Dockerfile
│
├── frontend/
│   ├── src/
│   │   ├── app/                          # Next.js 14 App Router
│   │   │   ├── page.tsx                  # Landing
│   │   │   ├── chat/page.tsx             # Main chat UI
│   │   │   ├── quote/page.tsx
│   │   │   ├── claims/page.tsx
│   │   │   ├── dashboard/page.tsx        # Customer dashboard
│   │   │   └── admin/page.tsx            # HITL approval queue
│   │   ├── components/
│   │   │   ├── ChatWindow.tsx
│   │   │   ├── AgentTrace.tsx            # Live agent visualization
│   │   │   ├── FileUpload.tsx
│   │   │   ├── PolicyCard.tsx
│   │   │   └── ClaimTimeline.tsx
│   │   ├── lib/                          # API client, utils
│   │   ├── hooks/                        # useChat, useAuth, etc.
│   │   └── types/                        # Shared TS types
│   ├── public/
│   ├── package.json
│   ├── tailwind.config.ts
│   └── Dockerfile
│
├── deployment/
│   ├── docker/
│   │   ├── docker-compose.yml            # Full local stack
│   │   ├── docker-compose.prod.yml
│   │   └── .env.docker
│   ├── aws/
│   │   ├── ecs-task-definition.json
│   │   ├── terraform/                    # Optional IaC
│   │   └── deploy.sh
│   ├── nginx/
│   │   └── nginx.conf
│   └── systemd/
│       └── autoshield.service
│
├── docs/
│   ├── architecture/
│   │   ├── system_diagram.png
│   │   ├── langgraph_flow.png
│   │   └── data_model.png
│   ├── api/
│   │   └── openapi.yaml
│   └── demo/
│       ├── walkthrough.mp4
│       └── screenshots/
│
├── notebooks/                            # Exploratory work
│   ├── 01_train_risk_model.ipynb
│   ├── 02_train_fraud_model.ipynb
│   ├── 03_damage_classifier_eval.ipynb
│   └── 04_ragas_evaluation.ipynb
│
├── scripts/
│   ├── seed_db.sh
│   ├── ingest_kb.py                      # Loads KB into ChromaDB
│   ├── generate_synthetic_data.py
│   └── eval_run.sh
│
├── .github/
│   └── workflows/
│       ├── ci.yml                        # Lint + test
│       ├── eval.yml                      # Nightly RAGAS run
│       └── deploy.yml
│
├── .gitignore
├── LICENSE
└── README.md                             # This file
```

---

## 🚀 Quick Start

### Prerequisites

- **Python 3.12+**
- **Node.js 20+**
- **Docker & Docker Compose**
- **OpenAI API key** (and optionally Anthropic API key)
- **AWS credentials** (only for S3 / production deployment)

### Local Development (Docker Compose — recommended)

```bash
# 1. Clone
git clone https://github.com/prashant9501/autoshield-ai.git
cd autoshield-ai

# 2. Configure environment
cp backend/.env.example backend/.env
# Edit backend/.env — add your OPENAI_API_KEY

# 3. Spin up the full stack (Postgres, Redis, ChromaDB, backend, frontend)
cd deployment/docker
docker compose up -d

# 4. Run database migrations + seed synthetic data
docker compose exec backend alembic upgrade head
docker compose exec backend python -m app.database.seed
docker compose exec backend python scripts/ingest_kb.py

# 5. Train the ML models (one-time, ~3 min)
docker compose exec backend python -m app.ml_models.train_risk
docker compose exec backend python -m app.ml_models.train_fraud

# 6. Open the app
open http://localhost:3000          # Next.js frontend
open http://localhost:8000/docs     # FastAPI Swagger
open http://localhost:3001          # Grafana (admin/admin)
```

### Manual setup (without Docker)

<details>
<summary>Click to expand</summary>

```bash
# Backend
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # add your keys

# Start Postgres, Redis, ChromaDB locally (or use Docker for these only)
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=dev postgres:16
docker run -d -p 6379:6379 redis:7
docker run -d -p 8001:8000 chromadb/chroma

# Run migrations + seed
alembic upgrade head
python -m app.database.seed
python scripts/ingest_kb.py

# Start backend
uvicorn app.main:app --reload --port 8000

# Frontend (in a new terminal)
cd ../frontend
npm install
npm run dev  # http://localhost:3000
```
</details>

---

## ⚙️ Configuration

### `backend/.env`

```bash
# ─── LLM Providers ──────────────────────────────────────
OPENAI_API_KEY=sk-...                      # Required
ANTHROPIC_API_KEY=sk-ant-...               # Optional, for Claude
LLM_PRIMARY=gpt-4o                         # Supervisor + reasoning
LLM_FAST=gpt-4o-mini                       # Cheap classification
LLM_LONG_CONTEXT=claude-sonnet-4-5         # Long policy docs
EMBEDDING_MODEL=text-embedding-3-small

# ─── Databases ──────────────────────────────────────────
POSTGRES_URL=postgresql+asyncpg://autoshield:dev@postgres:5432/autoshield
REDIS_URL=redis://redis:6379/0
CHROMA_HOST=chromadb
CHROMA_PORT=8000

# ─── AWS (S3 for images) ────────────────────────────────
AWS_REGION=ap-south-1
S3_BUCKET=autoshield-uploads
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...

# ─── Observability ──────────────────────────────────────
LANGSMITH_API_KEY=...                      # Optional but recommended
LANGSMITH_PROJECT=autoshield-prod
LANGFUSE_PUBLIC_KEY=...                    # Alternative
LANGFUSE_SECRET_KEY=...

# ─── Auth ───────────────────────────────────────────────
JWT_SECRET=change-me
JWT_ALGORITHM=HS256
JWT_EXPIRY_MIN=60

# ─── Business Rules ─────────────────────────────────────
HITL_CLAIM_THRESHOLD_INR=50000             # Claims above this need human approval
FRAUD_AUTO_REJECT_THRESHOLD=0.9
GST_RATE=0.18

# ─── Email (SMTP) ───────────────────────────────────────
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=noreply@autoshield.example.com
SMTP_PASSWORD=...
```

---

## 📡 API Reference

### Core Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/v1/chat` | Send a message; returns agent response (streaming via SSE) |
| `WS`   | `/ws/chat/{session_id}` | WebSocket chat — preferred for live agent traces |
| `POST` | `/api/v1/quotes` | Programmatic quote endpoint |
| `POST` | `/api/v1/policies` | Issue a policy |
| `POST` | `/api/v1/claims` | File a new claim (multipart with images) |
| `GET`  | `/api/v1/claims/{id}` | Claim status |
| `POST` | `/api/v1/admin/approve/{interrupt_id}` | HITL — underwriter / adjuster approval |
| `GET`  | `/api/v1/admin/queue` | Pending HITL items |
| `GET`  | `/health` | Liveness |
| `GET`  | `/metrics` | Prometheus scrape endpoint |

### Example: Filing a claim

```bash
curl -X POST http://localhost:8000/api/v1/claims \
  -H "Authorization: Bearer $TOKEN" \
  -F "policy_id=POL-2026-00042" \
  -F "incident_date=2026-04-25" \
  -F "incident_pincode=400001" \
  -F "description=Hit a divider on Western Express Highway" \
  -F "images=@damage1.jpg" \
  -F "images=@damage2.jpg"
```

Response:
```json
{
  "claim_id": "CLM-2026-00913",
  "status": "PENDING_REVIEW",
  "estimated_payout_inr": 78450,
  "fraud_score": 0.12,
  "damage_summary": {
    "front_bumper": "severe",
    "left_headlight": "moderate"
  },
  "next_step": "Awaiting human adjuster approval (claim > ₹50,000)",
  "interrupt_id": "intr_a1b2c3"
}
```

> 📘 Full OpenAPI spec: [`docs/api/openapi.yaml`](docs/api/openapi.yaml)

---

## 🧬 LangGraph State Schema

```python
# backend/app/workflows/state.py
from typing import TypedDict, Annotated, Literal
from langgraph.graph.message import add_messages
from pydantic import BaseModel

class AgentState(TypedDict):
    # Conversation
    messages: Annotated[list, add_messages]
    session_id: str
    user_id: str | None

    # Routing
    next_agent: Literal[
        "supervisor", "quote", "underwriting", "policy",
        "claims", "fraud", "renewal", "human", "END"
    ]
    intent: str | None
    intent_confidence: float | None

    # Domain context (populated by agents)
    quote_id: str | None
    policy_id: str | None
    claim_id: str | None
    customer: dict | None
    vehicle: dict | None

    # Artifacts produced
    uploaded_images: list[str]            # S3 keys
    extracted_documents: dict | None      # OCR results
    damage_assessment: dict | None
    fraud_score: float | None
    premium_breakdown: dict | None

    # Human-in-the-loop
    hitl_required: bool
    hitl_reason: str | None
    hitl_decision: dict | None            # populated after Command(resume=...)

    # Audit
    tool_calls: list[dict]
    errors: list[str]
```

---

## 👥 Human-in-the-Loop Workflow

LangGraph's `interrupt()` is used for three scenarios:

1. **Underwriting referral** — risk score in grey zone (0.55–0.75)
2. **High-value claim** — estimated payout > `HITL_CLAIM_THRESHOLD_INR`
3. **Fraud flag** — fraud score in 0.7–0.9 range (>0.9 is auto-rejected)

**Flow**:

```
Agent runs → reaches HITL trigger
   ↓
interrupt() pauses graph; state checkpointed to Postgres
   ↓
Backend creates a row in `hitl_queue` table; pushes to admin dashboard
   ↓
Underwriter/adjuster reviews on /admin → approves/rejects/edits
   ↓
POST /api/v1/admin/approve/{interrupt_id}
   ↓
Graph resumes via Command(resume={"decision": "approve", "loading_pct": 10})
   ↓
Agent continues from exactly where it left off
```

This is a real production pattern — most "agentic" demos skip it entirely.

---

## 🧪 Evaluation & Testing

### Unit & integration tests

```bash
cd backend
pytest                              # all tests
pytest tests/integration/           # end-to-end flows
pytest --cov=app                    # coverage report
```

### LLM evaluation (RAGAS + custom)

```bash
# RAG quality on policy KB queries
python -m app.evals.ragas_eval

# Agent routing accuracy on golden dataset (50 scenarios)
python -m app.evals.agent_eval

# Output: app/evals/reports/eval_<timestamp>.html
```

**Golden dataset** ([`backend/app/evals/golden_dataset.json`](backend/app/evals/golden_dataset.json)) covers:
- 10 quote flows (different vehicles, ages, locations)
- 10 underwriting decisions (clean / risky / decline cases)
- 10 claim scenarios (minor / moderate / severe / fraud)
- 10 RAG questions (policy clauses, IRDAI rules)
- 10 multi-turn conversations with topic switches

### CI evaluation gate

GitHub Actions runs the agent eval suite nightly. PRs fail if:
- RAGAS faithfulness drops below **0.85**
- Agent routing accuracy drops below **0.90**
- Tool-call success rate drops below **0.95**

---

## 📊 Observability

| Signal | Tool | What you see |
|---|---|---|
| **LLM traces** | LangSmith | Every prompt, completion, tool call, latency, cost |
| **Metrics** | Prometheus + Grafana | Token spend per agent, p95 latency, HITL queue depth |
| **Logs** | structlog → JSON → Loki | Structured, correlation-ID-tagged |
| **Errors** | Sentry | Stack traces with LLM context |
| **Audit trail** | Postgres `audit_log` | Every state mutation tied to `session_id` |

Pre-built Grafana dashboard: [`deployment/grafana/autoshield-dashboard.json`](deployment/grafana/autoshield-dashboard.json)

Key dashboards:
- **Agent routing distribution** — which agents get used most?
- **Token spend by model** — cost attribution per agent
- **HITL queue health** — pending items, average resolution time
- **Fraud score distribution** — calibration check

---

## 🚢 Deployment

### Local (Docker Compose)
Already covered in [Quick Start](#-quick-start).

### Production (AWS ECS Fargate)

```bash
# 1. Build & push images
./deployment/aws/deploy.sh build

# 2. Apply Terraform (RDS, ElastiCache, S3, ECR, ECS, ALB)
cd deployment/aws/terraform
terraform init && terraform apply

# 3. Deploy task definition
./deployment/aws/deploy.sh deploy

# 4. DB migration
./deployment/aws/deploy.sh migrate
```

### Single-EC2 (cheap demo deployment, like your previous project)

```bash
# Provision t3.medium Ubuntu 24.04 + Elastic IP
sudo bash deployment/systemd/setup_ec2.sh
# Same flow as your customer-support-agent — NGINX + systemd + Docker Compose
```

---

## 🗺️ Roadmap

- [x] Phase 1: Supervisor + Quote + Underwriting agents (Week 1)
- [x] Phase 2: Vision OCR + Policy Issuance (Week 2)
- [x] Phase 3: Claims + Fraud + HITL (Week 3)
- [x] Phase 4: Renewal + Evals + Production deploy (Week 4)
- [ ] Phase 5: Voice input via Whisper (stretch)
- [ ] Phase 6: WhatsApp Business API integration
- [ ] Phase 7: Multilingual (Hindi, Tamil, Marathi)
- [ ] Phase 8: Fine-tune YOLOv8 on Indian car damage dataset

---

## 🎓 Learning Outcomes

By building this end-to-end, you will have hands-on experience with:

✅ **LangGraph** — supervisor pattern, state design, checkpointing, interrupts, streaming
✅ **Multi-agent orchestration** — when to split agents vs use one big agent
✅ **Tool design** — Pydantic schemas, error handling, retries, idempotency
✅ **Multimodal AI** — vision OCR, damage classification, image hashing
✅ **RAG** — chunking strategy, hybrid search, re-ranking, eval with RAGAS
✅ **Production ML** — XGBoost training, model artifacts, inference latency
✅ **Human-in-the-loop** — interrupts, approval queues, audit trails
✅ **Observability** — LangSmith tracing, Prometheus, structured logging
✅ **Full-stack** — FastAPI + Next.js + Postgres + Redis + Docker
✅ **Domain modeling** — Indian motor insurance regulations, premium math

---

## 🤝 Contributing

PRs welcome. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) and ensure:
- All tests pass (`pytest`)
- RAGAS eval doesn't regress
- Code is formatted with `ruff` + `black`

---

## 📜 License

MIT License — see [LICENSE](LICENSE).

---

## 🙏 Acknowledgements

- [LangGraph](https://langchain-ai.github.io/langgraph/) team for the orchestration framework
- [IRDAI](https://www.irdai.gov.in/) — public regulatory documentation used for policy templates
- [K21 Academy](https://k21academy.com) — capstone mentorship and review

---

## 📬 Contact

**Prashant** — [@prashant9501](https://github.com/prashant9501)

If this project helped you, ⭐ star the repo and share it.

> Built as a capstone project to demonstrate production-grade agentic AI engineering.
