# Repository Map

This repository documents the IOMETE single-node lab deployment and the Banco de Moçambique Data Quality Reporting PoC.

## Root

| Path | Purpose |
|---|---|
| `README.md` | Main project overview, lab environment, deployment flow, final state, and links |
| `.gitignore` | Files excluded from Git |

## docs/

| Path | Purpose |
|---|---|
| `docs/data-quality-reporting-framework.md` | Main Data Quality Reporting Framework |
| `docs/banking-data-profile-report.md` | Banking dataset inventory and profile |
| `docs/credit-risk-analytics-solution-report.md` | Credit risk analytics use-case documentation |
| `docs/deployment-commands.md` | Deployment command history |
| `docs/images/` | Architecture diagrams and visual assets |

## data/

| Path | Purpose |
|---|---|
| `data/README.md` | Description of the synthetic Banco de Moçambique data |
| `data/poc_bm_dados_sinteticos_csv/` | Synthetic supervisory banking CSV submissions |
| `data/Exchange_rates_csv.sql` | Exchange-rate reference data |

## scripts/

| Path | Purpose |
|---|---|
| `scripts/03_bronze_quality_framework_v2.sql` | Current SQL implementation for Bronze quality reporting |
| `scripts/reapply-mac-lab-patches.sh` | Recovery script for lab-specific IOMETE patches |

## evidence/

| Path | Purpose |
|---|---|
| `evidence/` | Captured Kubernetes and IOMETE final working state evidence |

## Main Workstreams

1. IOMETE single-node lab deployment
2. Synthetic banking data profiling
3. Data Quality Reporting Framework
4. Credit risk analytics documentation
5. Evidence capture and recovery notes
