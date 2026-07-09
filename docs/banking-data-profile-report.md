# Banking Data Inventory & Profile Report

*Banco de Moçambique PoC — synthetic supervisory banking data on IOMETE*

---

## 1. Purpose and Provenance

This report profiles the synthetic banking dataset used in the Banco de Moçambique (BM) proof of concept. The data simulates regulatory submissions from **10 fictional reporting banks (BCO01–BCO10)** under BM's reporting circular *"Crédito e Depósito para o PoC BM"*, plus the reference tables and market data needed to interpret them. All data is synthetic; **725 anomalies were deliberately seeded** and documented in an answer key so that the platform's data-quality and ML anomaly-detection capabilities can be measured against a known ground truth.

The raw files live under `data/` in this repository; the regulatory circular is at `docs/Credito_e_Deposito_para_o_PoC_BM.pdf`.

---

## 2. Regulatory Basis

Each dataset corresponds to a *mapa* or *quadro* defined in the circular:

| File pattern | Circular reference | Content |
|---|---|---|
| `BCOxx_quadro_1_dados_mestres_credito.csv` | Quadro n.º 1 | Credit master data — 43 fields covering application, approval, product, amounts, rates, dates, collateral and geography |
| `BCOxx_quadro_2_operacoes_credito.csv` | Quadro n.º 2 | Credit operations — 23 fields covering operation status, balances, arrears, interest and collections |
| `BCOxx_quadro_9_depositos.csv` | Quadro n.º 9 | Deposits — 17 fields covering deposit type, counterparty, rates (TAE/TANB/TANL), currency and dates |
| `BCOxx_mapa_1c_transacoes_balcao.csv` | Mapa 1C | Branch (over-the-counter) transactions |
| `BCOxx_mapa_4a_listagem_pos.csv` | Mapa 4A | POS device inventory with merchant, MCC, district and coordinates |
| `BCOxx_mapa_4b_transacoes_pos.csv` | Mapa 4B | POS transactions |
| `BCOxx_mapa_5a_contas_bancarias.csv` | Mapa 5A | Bank accounts — 27 fields covering holder, type, status, channels and PEP flag |

Key coded domains defined by the circular (and therefore validatable by rule):

- **Deposit types:** DO (ordem), DP (prazo), PA (pré-aviso), DF (fundos consignados), DS (obrigatórios)
- **Interest-rate reference (credit):** 1 MIMO, 2 Prime Rate, 3 FPC, 4 EURIBOR, 5 SOFR, 6 JIBAR, 7 sem indexante, 8 outra
- **Interest-rate reference (deposits):** 1 MIMO, 2 FPD, 3 EURIBOR, 4 SOFR, 5 JIBAR, 6 sem indexante, 7 outro
- **Rejection reasons (Apêndice I):** coded 10–71 across risk, documentation, financial situation, collateral, compliance, purpose and fiscal/legal categories
- **Credit modality (Apêndice II):** codes 100–404; **credit purpose (Apêndice III):** codes 100–206; **collateral type (Apêndice IV):** codes 100–314
- **Identifiers:** NUIB (Texto 11) is the customer key joining credit, deposit and transaction datasets
- **Formats:** dates as dd-MM-yyyy strings; decimals in Portuguese locale (`1.234,56`); coordinates in decimal degrees

---

## 3. Bank Submission Inventory

Row counts per bank and dataset (70 submission files in total, as delivered):

| Dataset | BCO01 | BCO02 | BCO03 | BCO04 | BCO05 | BCO06 | BCO07 | BCO08 | BCO09 | BCO10 | **Total** |
|---|---|---|---|---|---|---|---|---|---|---|---|
| POS list (4A) | 360 | 300 | 260 | 240 | 200 | 180 | 160 | 120 | 100 | 80 | **2,000** |
| Bank accounts (5A) | 9,000 | 7,500 | 6,500 | 6,000 | 5,000 | 4,500 | 4,000 | 3,000 | 2,500 | 2,000 | **50,000** |
| Credit master (Q1) | 5,400 | 4,500 | 3,900 | 3,600 | 3,000 | 2,700 | 2,400 | 1,800 | 1,500 | 1,200 | **30,000** |
| Deposits (Q9) | 18,000 | 15,000 | 13,000 | 12,000 | 10,000 | 9,000 | 8,000 | 6,000 | 5,000 | 4,000 | **100,000** |
| Branch txns (1C) | 27,000 | 22,500 | 19,500 | 18,000 | 15,000 | 13,500 | 12,000 | 9,000 | 7,500 | 6,000 | **150,000** |
| POS txns (4B) | 36,000 | 30,000 | 26,000 | 24,000 | 20,000 | 18,000 | 16,000 | 12,000 | 10,000 | 8,000 | **200,000** |
| Credit ops (Q2) | 36,000 | 30,000 | 26,000 | 24,000 | 20,000 | 18,000 | 16,000 | 12,000 | 10,000 | 8,000 | **200,000** |
| **Bank total** | **131,760** | **109,800** | **95,160** | **87,840** | **73,200** | **65,880** | **58,560** | **43,920** | **36,600** | **29,280** | **732,000** |

The volumes scale linearly by bank size: BCO01 contributes 18% of all records and BCO10 contributes 4%, giving a realistic large-to-small bank distribution. Every dataset preserves the same 18:15:13:12:10:9:8:6:5:4 ratio, which also makes per-bank comparisons in dashboards directly proportional.

---

## 4. Reference Data

| File | Records | Role |
|---|---|---|
| `bancos_referencia.csv` | 10 | Reporting bank registry (banco_id, name) |
| `mcc_referencia.csv` | 11 | Merchant category codes with base average ticket |
| `distritos_referencia.csv` | 455 | Province / district / administrative post geography (INE coding) |
| `cae_referencia_utilizada_15_codigos.csv` | 15 | Economic activity codes used in the PoC |
| `resumo_taxas_juros_v2.csv` | 7 | Expected interest-rate ranges (min/p95/p99/max) per dataset field — the basis for rate reasonableness rules |
| `manifesto_ficheiros.csv` | 70 | File manifest with expected record counts per bank and dataset — the basis for reconciliation and presence (ROW001) checks |
| `anomalias_esperadas_para_validacao.csv` | 725 | Seeded anomaly answer key (banco_id, anomaly type, record id, description) — ground truth for quality validation and the supervised ML labels |

---

## 5. Exchange Rates — Profiled Series

`Exchange_rates_csv.sql` is, despite the extension, a semicolon-delimited CSV of daily MZN mid-rates. Profiled directly for this report:

| Property | Value |
|---|---|
| Observations | 617 daily rows (business days) |
| Coverage | 2024/01/02 → 2026/06/19 |
| Duplicated dates | 0 |
| Calendar gaps > 4 days | 1 (2025/12/31 → 2026/01/05, New Year holidays — expected) |

Per-currency behaviour:

| Currency | Min | Max | Mean | Observation |
|---|---|---|---|---|
| USD | 63.90 | 63.92 | 63.91 | Effectively pegged — only three distinct values across 2.5 years, consistent with the managed MZN/USD rate |
| EUR | 38.99 | 76.55 | 71.40 | Normal band ≈ 68–77; contains **one severe outlier** (see below) |
| ZAR | 3.23 | 4.06 | 3.61 | Plausible gradual drift, no anomalies detected |

**Finding — seeded or genuine data error:** on **2024/05/03 the EUR rate is 38.99**, roughly half the surrounding level (~70), and more than 4 standard deviations from the series mean. Neighbouring days are normal. This is exactly the class of "sensible data" violation the quality framework's reasonableness rules target, and it will distort any FX conversion of EUR-denominated positions on that date if used uncorrected. Recommended handling: flag via an EXR reasonableness rule (rate within ±20% of a rolling median) rather than silently fixing, consistent with the report-don't-clean principle.

---

## 6. Known Quality Findings from Pipeline Runs

Findings already evidenced by the quality framework against this data in the IOMETE environment:

| Finding | Detail | Where recorded |
|---|---|---|
| Negative effective interest rates | 640 `credit_operations` records with negative `effective_interest_rate` | Rule CREDITO008, `quality.rule_results` / `failed_records` |
| Bronze→Silver reconciliation mismatch | `credit_master_data`: 30,000 Bronze vs 25,981 Silver (−4,019); `credit_operations`: 200,000 Bronze vs 2,000,000 Silver (+1.8M, duplication in the Silver build) | `quality.reconciliation` |
| Seeded anomaly baseline | 725 documented anomalies across the 10 banks awaiting detection-rate measurement | `bronze.ref_anomalias_esperadas` |
| EUR rate outlier | 2024/05/03 = 38.99 MZN (see Section 5) | This report; candidate EXR reasonableness rule |

The seeded answer key means detection performance is measurable: the target end-state is a confusion matrix of framework findings versus the 725 expected anomalies, and precision/recall for the supervised ML classifier trained on the same labels.

---

## 7. Fitness for Purpose

The dataset is well suited to the PoC's three demonstration goals. For **data quality**, it contains verifiable seeded errors, a manifest for reconciliation, and coded domains from the circular that make rules objective. For **analytics**, the linear bank-size distribution, district-level geography (455 codes) and 2.5 years of daily FX data support the credit-risk and geographic dashboards. For **machine learning**, the 725 labelled anomalies provide supervised training data, with the known caveat that 725 positives across 732,000 records is a heavily imbalanced problem — precision/recall, not accuracy, is the correct evaluation measure, and the modest label count carries overfitting risk that must be managed with cross-validation.

---

## 8. Data Location in This Repository

```text
data/
├── poc_bm_dados_sinteticos_csv/
│   ├── BCO01/ … BCO10/                    # 7 submission files per bank
│   ├── *_referencia*.csv, manifesto_ficheiros.csv,
│   │   anomalias_esperadas_para_validacao.csv, resumo_taxas_juros_v2.csv
│   ├── README_PoC_dados_sinteticos.txt    # original dataset notes
│   └── referencias_originais/             # original CAE and INE census workbooks
└── Exchange_rates_csv.sql                 # daily MZN FX series (semicolon CSV)
docs/
├── Credito_e_Deposito_para_o_PoC_BM.pdf   # regulatory circular
└── banking-data-profile-report.md         # this report
```

The `poc_bm_dados_sinteticos_csv/` layout is preserved exactly as delivered
because `01_ingest_banking_data.py` reads it directly
(`DATA_ROOT/{bank_id}/{bank_id}_{dataset}.csv`), so the repository doubles as
a runnable data root for the Bronze ingestion.

All figures in Sections 3–5 were measured from the delivered files; Section 6
findings come from executed pipeline runs recorded in `mzbq_catalog.quality.*`.
