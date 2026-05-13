# 🚗 Car Insurance AI Agent

> A production-ready multi-agent car insurance assistant built with **LangGraph** supervisor pattern, **GPT-4o Vision** for damage analysis, **RAG** over IRDAI guidelines, and the actual math used by Indian motor insurers.

[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)](https://python.org)
[![LangGraph](https://img.shields.io/badge/LangGraph-0.2-1C3C3C)](https://langchain-ai.github.io/langgraph/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## ✨ What it does

A chat assistant that handles three real insurance workflows end-to-end:

| Workflow | Example | What happens |
|---|---|---|
| 📋 **Quote** | "Get me a quote for a 2-year-old Maruti Swift, 1 NCB" | Looks up vehicle specs → calculates IDV per IRDAI depreciation slab → returns 3 plans (TP / Comprehensive / Zero-Dep) with full premium breakdown |
| 🛠️ **Claim** | Upload damage photo + "I had an accident" | GPT-4o Vision classifies damage severity → estimates repair cost → calculates payout (after depreciation + deductible) |
| ❓ **Policy Q&A** | "What is the NCB ladder?" | RAG over IRDAI guidelines + policy terms → grounded, accurate answer |

## 🏗️ Architecture

```
                    ┌──────────────────┐
                    │   SUPERVISOR     │  ← Classifies intent (GPT-4o-mini)
                    │   (router)       │
                    └────────┬─────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
   ┌─────────┐        ┌──────────┐        ┌──────────┐
   │  QUOTE  │        │  CLAIMS  │        │  POLICY  │
   │  AGENT  │        │  AGENT   │        │   Q&A    │
   │ (4o)    │        │  (4o+v)  │        │ (4o-mini)│
   └────┬────┘        └─────┬────┘        └────┬─────┘
        │                   │                   │
        ▼                   ▼                   ▼
   ┌─────────┐        ┌──────────┐        ┌──────────┐
   │ 3 tools │        │ 3 tools  │        │ 1 tool   │
   │ vehicle │        │ verify   │        │ kb_search│
   │ premium │        │ vision   │        │ (RAG)    │
   │ pincode │        │ payout   │        │          │
   └─────────┘        └──────────┘        └──────────┘
                             │
                    ┌────────▼─────────┐
                    │ LangGraph        │
                    │ checkpointer     │  ← Resumable conversations
                    └──────────────────┘
```

**Why supervisor pattern?**
- Fast classification (cheap model) → expensive reasoning only on the right agent
- Each agent has a focused tool set → fewer hallucinations
- Easy to add new agents without touching existing ones

## 🇮🇳 Real Indian insurance domain

This isn't a generic Western insurance demo. It models **actual** Indian motor insurance:

| Concept | Implementation |
|---|---|
| **IDV** (Insured Declared Value) | IRDAI depreciation slabs: 5% → 50% over 5 years |
| **NCB** (No Claim Bonus) | Real ladder: 20% → 25% → 35% → 45% → 50% |
| **OD vs TP** | Own Damage premium (3% of IDV) + Third-Party tariff per engine cc |
| **GST** | 18% GST on motor premiums |
| **Zero Depreciation** | 15% loading on OD; no depreciation on parts at claim time |
| **IRDAI** | Policy terms ingested as RAG knowledge base |

Sample quote for a 2-year-old Maruti Swift with 1 year NCB:
- Third Party Only: **₹4,030**
- Comprehensive: **₹18,757**
- Comprehensive + Zero Dep: **₹20,966**

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Orchestration | LangGraph (supervisor + checkpointing) |
| LLMs | GPT-4o (reasoning + vision), GPT-4o-mini (routing + Q&A) |
| Embeddings | OpenAI `text-embedding-3-small` |
| Vector DB | ChromaDB (persistent) |
| Backend | FastAPI + Pydantic v2 |
| Frontend | Vanilla HTML/CSS/JavaScript (single page) |
| Deployment | Docker + Docker Compose + NGINX |
| Total LOC | ~1,500 |

## 📁 Project Structure

```
car-insurance-agent/
├── backend/
│   ├── app/
│   │   ├── agents/                # 3 specialist agents + supervisor
│   │   │   ├── supervisor.py       # Intent classifier + router
│   │   │   ├── quote_agent.py      # Premium quote agent
│   │   │   ├── claims_agent.py     # FNOL with vision
│   │   │   └── policy_qa_agent.py  # RAG-based Q&A
│   │   ├── tools/                  # 7 tools across 3 categories
│   │   │   ├── quote_tools.py      # vehicle_lookup, calculate_premium, pincode_risk
│   │   │   ├── claims_tools.py     # verify_policy, analyze_damage_image, estimate_payout
│   │   │   └── rag_tools.py        # policy_kb_search
│   │   ├── workflows/
│   │   │   ├── state.py            # AgentState TypedDict
│   │   │   └── main_graph.py       # LangGraph wiring
│   │   ├── services/
│   │   │   ├── premium_calc.py     # IRDAI premium math
│   │   │   └── vehicle_catalog.py  # Mock VAHAN database
│   │   └── main.py                 # FastAPI app
│   ├── data/
│   │   └── knowledge_base/         # IRDAI guidelines, policy terms, FAQs
│   ├── scripts/
│   │   └── ingest_kb.py            # Load KB into ChromaDB
│   ├── tests/
│   │   └── test_premium_calc.py
│   ├── requirements.txt
│   └── .env.example
├── frontend/
│   ├── index.html                  # Chat UI
│   └── static/
│       ├── style.css
│       └── app.js
├── deployment/
│   ├── docker/
│   │   └── docker-compose.yml
│   ├── nginx/
│   │   └── nginx.conf
│   └── systemd/
│       └── setup_ec2.sh            # One-shot EC2 provisioning
├── Dockerfile
├── README.md
└── LICENSE
```

## 🚀 Quick Start

### Prerequisites
- Python 3.12+
- Docker & Docker Compose
- OpenAI API key (~$5–10 covers extensive testing)

```

## 🚢 Deploy to AWS EC2

One-shot script provisions a fresh Ubuntu 26.04 EC2 with everything (Docker, NGINX, systemd):

```bash
# On the EC2 instance:
git clone https://github.com/k21academyuk/car-insurance-agent.git
cd car-insurance-agent
chmod +x deployment/systemd/setup_ec2.sh
sudo bash deployment/systemd/setup_ec2.sh

# Then add your OpenAI key and start
sudo nano backend/.env
sudo systemctl start car-insurance-agent

# Initialize KB
cd deployment/docker
docker compose exec app python scripts/ingest_kb.py
```

App is then live at `http://YOUR-EC2-IP/`.

## 🎯 Demo Conversations

### Quote flow
```
User: Get me a quote for a Maruti Swift, 2 years old, 1 NCB
Bot:  [calls vehicle_lookup, calculate_premium]
      Here are 3 plans for your Maruti Swift (2 years old, IDV ₹5,20,000):

      🛡️ Third Party Only         ₹4,030 (mandatory minimum)
      🛡️ Comprehensive            ₹18,757 (recommended)
      🛡️ Comprehensive + Zero-Dep ₹20,966 (best protection)

      Which plan would you like to proceed with?
```

### Claims flow with vision
```
User: [uploads damage photo] I hit a divider on the highway
Bot:  [calls analyze_damage_image, estimate_payout]
      I'm sorry to hear about that. Based on the photo:

      Damage assessed:
      • Front bumper: severe
      • Left headlight: moderate
      • Hood: minor

      Estimated repair cost: ₹68,000
      Estimated payout (after 30% dep + ₹2,500 deductible): ₹45,100
      Out of pocket: ₹22,900

      Since payout is < ₹50,000, no surveyor visit needed.
      Claim ID: CLM-2026-08123. We'll email next steps.
```

### Policy Q&A with RAG
```
User: What is NCB and how does it work?
Bot:  [calls policy_kb_search]
      NCB (No Claim Bonus) is a discount on your Own Damage premium for
      claim-free years. It starts at 20% after 1 year and goes up to 50%
      after 5 years. Per IRDAI rules:
      
      • Year 1: 20%
      • Year 2: 25%
      • Year 3: 35%
      • Year 4: 45%
      • Year 5+: 50%
      
      NCB belongs to you, not the car — you can transfer it to a new vehicle.
```

## 🧪 Testing

```bash
cd backend
pytest tests/                    # unit tests
pytest tests/ -v --tb=short      # verbose
```

## 🔐 Configuration

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `OPENAI_API_KEY` | ✅ | — | OpenAI API access |
| `LANGSMITH_API_KEY` | optional | — | LangSmith tracing |
| `LANGSMITH_TRACING` | optional | `false` | Enable tracing |
| `CORS_ORIGINS` | optional | `*` | Comma-separated origins |
| `CHROMA_PERSIST_DIR` | optional | `/app/chroma_db` | ChromaDB persistence path |

## 💰 Cost Estimate

Running the demo for a month with moderate use (~50 conversations/day):
- OpenAI API: **~$3–8/month**
- AWS t3.medium EC2: **~$30/month**
- Total: **~$35/month**

Vision calls are the most expensive piece — about $0.005 per damage photo analysis.

## 🎓 What this demonstrates (capstone-level)

✅ **Hierarchical multi-agent** orchestration with LangGraph
✅ **Multimodal AI** — GPT-4o Vision actually classifies real damage
✅ **RAG** with proper chunking, embeddings, and grounded responses
✅ **Tool calling** with Pydantic-validated schemas
✅ **Stateful conversations** via LangGraph checkpointing
✅ **Domain modeling** — real Indian motor insurance math (IRDAI-compliant)
✅ **Production deployment** — Docker, NGINX, systemd, EC2
✅ **Clean separation** — agents, tools, services, frontend all isolated

## 📜 License

MIT — see [LICENSE](LICENSE).

## 🙏 Built by

Capstone project demonstrating production-grade agentic AI engineering.
