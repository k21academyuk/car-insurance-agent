# Data Model

## Postgres Tables
- `customers` — id, name, email, phone, dob, kyc_status, created_at
- `vehicles` — id, customer_id, registration_no, make, model, variant, year, fuel, idv
- `quotes` — id, customer_id, vehicle_id, plan, premium_breakdown_jsonb, expires_at
- `policies` — id, quote_id, policy_no, start_date, end_date, status, pdf_s3_key
- `claims` — id, policy_id, claim_no, incident_date, description, damage_assessment_jsonb, payout_estimate, fraud_score, status
- `hitl_queue` — id, interrupt_id, reason, payload_jsonb, status, assignee, decided_at
- `audit_log` — id, session_id, agent, tool, input_jsonb, output_jsonb, latency_ms, ts
- `fraud_signals` — id, claim_id, signal_type, score, detail_jsonb
