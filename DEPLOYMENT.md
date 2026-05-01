# Deployment Guide

## Option A — Single EC2 (cheap, recommended for demos)
Same as your customer-support-agent:
1. Launch t3.medium Ubuntu 24.04 + Elastic IP, open ports 22/80/443
2. SSH in, install Docker + Docker Compose
3. Clone repo, configure `.env`
4. `cd deployment/docker && docker compose up -d`
5. `sudo cp deployment/systemd/autoshield.service /etc/systemd/system/`
6. `sudo systemctl enable --now autoshield`

## Option B — AWS ECS Fargate (production)
1. Provision via Terraform: `cd deployment/aws/terraform && terraform apply`
2. Push images: `bash deployment/aws/deploy.sh build`
3. Update service: `bash deployment/aws/deploy.sh deploy`

## TLS
Use Caddy or NGINX + Let's Encrypt:
```bash
sudo certbot --nginx -d autoshield.example.com
```

## Backups
- Postgres: `pg_dump` cron to S3
- ChromaDB: persistent volume snapshot
- S3 (uploads): versioning enabled
