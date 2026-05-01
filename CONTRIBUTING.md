# Contributing to AutoShield AI

Thanks for your interest! Please follow these steps:

1. Fork and create a feature branch
2. Run tests: `pytest` and `npm run lint`
3. Don't regress evals: `bash scripts/eval_run.sh`
4. Submit a PR with a clear description

## Code style
- Python: `ruff` + `black` (line length 100)
- TypeScript: `eslint` + `prettier`

## Commit message format
- `feat: add fraud anomaly detector tool`
- `fix: handle empty image upload in claims agent`
- `docs: clarify HITL flow in README`
- `test: cover NCB ladder edge cases`
