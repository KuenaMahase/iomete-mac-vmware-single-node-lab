# Data Quality Reporting Framework

## Purpose

This document defines the Data Quality Assessment and Reporting Framework for the Banco de Moçambique synthetic banking data PoC on IOMETE.

This workstream focuses only on reporting data quality. It does not own the full analytics use cases, Gold business model, or data correction process.

The objective is to show stakeholders that IOMETE can assess incoming banking data, identify inconsistencies, detect duplicates, record failed records, generate scorecards, and expose the results for reporting.

---

## Stakeholder Questions Addressed

| Stakeholder question | Framework answer |
|---|---|
| Statistics in terms of data quality? | Report quality metrics through `quality.rule_results`, `quality.summary`, and `quality.scorecard` |
| Report on that? | Build Tableau dashboards from the `quality` schema |
| Where are records left behind? | Store failed records in `quality.failed_records` |
| Where is the table? | All quality evidence is stored in the `mzbq_catalog.quality` schema |
| Did you sort them out? | No. This framework reports issues without modifying the source data |
| Duplication check? | Detect duplicates using `quality.duplicate_records` and `quality.duplicate_details` |
| Where are scorecards from? | Scorecards are calculated from rule execution results |
| Sensible data? | Apply business reasonableness rules such as invalid amounts, dates, rates, references, and negative values |

---

## Scope

This workstream delivers a Data Quality Reporting capability.

It focuses on:

- Measuring data quality across banking datasets
- Identifying failed validation rules
- Detecting duplicate records and duplicate business keys
- Showing where failed records are stored
- Producing quality scorecards by dataset, bank, rule, severity, and run
- Providing Tableau-ready data quality reporting tables
- Preserving bad data as evidence instead of hiding it

It does not focus on:

- Automatically fixing records
- Deleting duplicates
- Replacing the other business use cases
- Building the complete Gold analytics layer
- Making final business decisions for the data owner

---

## Core Principle

Data quality assessment must be separate from data cleaning.

```text
Bronze
  ↓
Silver
  ↓
Data Quality Assessment
  ↓
Quality Reporting Tables
  ↓
Tableau Dashboards
```

Bronze preserves the raw data received.
Silver makes the data technically usable by standardising types, formats, and column names.
The Data Quality layer observes the data and records quality evidence.
It does not change, hide, or remove bad records.

### Why Validation Does Not Clean Data

The goal is to show that the platform can detect inconsistencies in the raw and conformed banking data.

Example: `Loan amount = -5000`

The framework should not change this value to zero. Instead, it records:

- **Rule:** Loan amount must be non-negative
- **Dataset:** Credit operations
- **Status:** Failed
- **Reason:** Negative loan amount
- **Record location:** `quality.failed_records`

This supports auditability, transparency, and investigation.

---

## Quality Schema

All quality reporting outputs are stored in:

```sql
CREATE SCHEMA IF NOT EXISTS mzbq_catalog.quality;
```

Recommended tables:

- `mzbq_catalog.quality.rule_catalog`
- `mzbq_catalog.quality.pipeline_runs`
- `mzbq_catalog.quality.rule_results`
- `mzbq_catalog.quality.failed_records`
- `mzbq_catalog.quality.duplicate_records`
- `mzbq_catalog.quality.duplicate_details`
- `mzbq_catalog.quality.summary`
- `mzbq_catalog.quality.scorecard`

---

## Quality Tables

### 1. quality.rule_catalog

Stores the list of rules used to assess data quality. This table explains where the scorecards come from.

Example columns:

| Column | Purpose |
|---|---|
| rule_id | Unique rule identifier |
| rule_name | Human-readable rule name |
| rule_type | Completeness, validity, consistency, duplicate, reference, or business |
| dataset | Dataset being checked |
| severity | Critical, high, medium, or warning |
| description | What the rule checks |
| business_reason | Why the rule matters |
| is_active | Whether the rule is currently active |

Example rules:

| Rule ID | Rule name | Type | Severity |
|---|---|---|---|
| DQ001 | Customer identifier must not be null | Completeness | Critical |
| DQ002 | Account number must not be null | Completeness | Critical |
| DQ003 | Loan amount must be non-negative | Business | Critical |
| DQ004 | Deposit amount must be non-negative | Business | Critical |
| DQ005 | Duplicate account number check | Duplicate | High |
| DQ006 | Duplicate customer identifier check | Duplicate | High |
| DQ007 | Branch must exist in reference data | Reference | High |
| DQ008 | District must exist in reference data | Reference | Medium |
| DQ009 | Interest rate must be within sensible limits | Business | High |
| DQ010 | Loan maturity date must be after start date | Business | High |

### 2. quality.pipeline_runs

Stores each execution of the data quality process.

Example columns:

| Column | Purpose |
|---|---|
| run_id | Unique execution ID |
| run_started_at | Start timestamp |
| run_completed_at | End timestamp |
| status | Success, failed, or partial |
| source_layer | Bronze or Silver |
| notes | Optional execution notes |

This table allows the framework to show quality trends across multiple runs.

### 3. quality.rule_results

Stores pass and fail statistics per rule. This answers: *Statistics in terms of data quality?*

Example columns:

| Column | Purpose |
|---|---|
| run_id | Pipeline execution ID |
| rule_id | Rule executed |
| dataset | Dataset checked |
| records_checked | Number of records evaluated |
| records_passed | Number of records that passed |
| records_failed | Number of records that failed |
| pass_percentage | Pass percentage |
| fail_percentage | Fail percentage |
| severity | Rule severity |
| executed_at | Execution timestamp |

Example output:

| Rule | Dataset | Checked | Failed | Pass % |
|---|---|---|---|---|
| Loan amount non-negative | Credit operations | 54,200 | 80 | 99.85 |
| Customer ID mandatory | Bank accounts | 9,000 | 35 | 99.61 |
| Branch exists | Deposits | 17,620 | 120 | 99.32 |

### 4. quality.failed_records

Stores actual records that failed validation. This answers: *Where are records left behind?*

Example columns:

| Column | Purpose |
|---|---|
| run_id | Pipeline execution ID |
| rule_id | Failed rule |
| dataset | Dataset where failure was found |
| table_name | Source table checked |
| record_key | Business or technical record identifier |
| bank_code | Reporting bank, where available |
| failed_column | Column that failed |
| failed_value | Value that caused the failure |
| failure_reason | Human-readable reason |
| severity | Critical, high, medium, or warning |
| source_file | Original source file, where available |
| ingested_at | Ingestion timestamp, where available |
| detected_at | Detection timestamp |

Example output:

| Rule | Dataset | Record key | Reason |
|---|---|---|---|
| DQ003 | Credit operations | LOAN00045 | Negative loan amount |
| DQ001 | Bank accounts | ACC88721 | Missing customer identifier |
| DQ008 | POS transactions | POS11892 | Invalid district code |

### 5. quality.duplicate_records

Stores duplicate groups by dataset and duplicate key. This answers: *Duplication check?*

Example columns:

| Column | Purpose |
|---|---|
| run_id | Pipeline execution ID |
| dataset | Dataset checked |
| table_name | Source table checked |
| duplicate_key_name | Name of key used for duplicate detection |
| duplicate_key_value | Duplicate key value |
| duplicate_count | Number of records sharing that key |
| bank_code | Reporting bank, where available |
| severity | Severity assigned to the duplicate |
| detected_at | Detection timestamp |

Example output:

| Dataset | Duplicate key | Count |
|---|---|---|
| Bank accounts | ACC001245 | 3 |
| Customers | NUIB445522 | 2 |
| POS transactions | POS8877 | 4 |

### 6. quality.duplicate_details

Stores the individual records inside each duplicate group. This supports drill-down from a duplicate summary into the actual records.

Example columns:

| Column | Purpose |
|---|---|
| run_id | Pipeline execution ID |
| duplicate_group_id | Unique duplicate group identifier |
| dataset | Dataset checked |
| record_key | Actual record identifier |
| duplicate_key_value | Duplicate value |
| source_file | Original source file, where available |
| ingested_at | Ingestion timestamp, where available |
| detected_at | Detection timestamp |

### 7. quality.summary

Stores executive-level quality metrics per run.

Example columns:

| Column | Purpose |
|---|---|
| run_id | Pipeline execution ID |
| total_records_checked | Total records evaluated |
| total_records_passed | Total passed records |
| total_records_failed | Total failed records |
| critical_failures | Number of critical issues |
| high_failures | Number of high-severity issues |
| medium_failures | Number of medium-severity issues |
| warning_failures | Number of warnings |
| duplicate_groups | Number of duplicate groups |
| overall_quality_score | Overall score |
| generated_at | Timestamp |

Example output:

| Metric | Value |
|---|---|
| Total records checked | 1,260,000 |
| Failed records | 12,020 |
| Duplicate groups | 142 |
| Critical failures | 38 |
| Overall quality score | 98.98% |

### 8. quality.scorecard

Stores quality scoring by bank and dataset. This answers: *Which bank has the worst quality?* and *Where are the scorecards from?*

Example columns:

| Column | Purpose |
|---|---|
| run_id | Pipeline execution ID |
| bank_code | Reporting bank |
| dataset | Dataset scored |
| records_checked | Number of records checked |
| failed_records | Number of failed records |
| duplicate_groups | Number of duplicate groups |
| critical_failures | Critical issue count |
| high_failures | High issue count |
| medium_failures | Medium issue count |
| warning_failures | Warning count |
| quality_score | Calculated score |
| generated_at | Timestamp |

Example output:

| Bank | Records | Failed | Duplicates | Score |
|---|---|---|---|---|
| BCO01 | 125,000 | 201 | 14 | 99.1 |
| BCO02 | 128,000 | 875 | 46 | 95.8 |
| BCO03 | 124,000 | 1,250 | 52 | 93.2 |

---

## Rule Categories

### Completeness

Completeness checks identify missing required values. Examples:

- Missing customer identifier
- Missing account number
- Missing loan reference
- Missing branch code
- Missing transaction date

### Validity

Validity checks identify invalid values. Examples:

- Invalid date format
- Invalid currency code
- Invalid status value
- Invalid numeric value
- Negative amount where negative values are not expected

### Consistency

Consistency checks compare values across related fields. Examples:

- Loan maturity date before loan start date
- Closed account with active loan
- Customer linked to missing account
- Transaction date before account opening date

### Reference Integrity

Reference checks validate values against reference datasets. Examples:

- Branch code must exist
- District code must exist
- Province code must exist
- MCC code must exist
- Bank code must exist

### Reasonableness / Sensible Data

Reasonableness checks ask whether the data makes business sense. Examples:

- Loan amount should be non-negative
- Deposit amount should be non-negative
- Interest rate should be within expected limits
- Customer age should be plausible
- Overdue days should be within a sensible range
- Exchange rate should not be negative

---

## Duplicate Detection Strategy

Duplicates should be reported, not silently removed.

Recommended duplicate checks:

| Dataset | Duplicate key example |
|---|---|
| Bank accounts | Account number |
| Customers | Customer identifier or NUIB |
| Credit operations | Loan reference or operation ID |
| Deposits | Deposit/account/date combination |
| POS terminals | POS terminal ID |
| POS transactions | Transaction ID or transaction business key |
| Branches | Branch code |

For each duplicate check, the framework should store:

- Dataset checked
- Duplicate key used
- Duplicate key value
- Duplicate count
- Bank code, where available
- Source file, where available
- Individual record identifiers for drill-down

---

## Suggested Quality Score Formula

A simple scoring approach for the PoC:

```text
quality_score = 100 - weighted_failure_rate
```

Suggested severity weights:

| Severity | Weight |
|---|---|
| Critical | 5 |
| High | 3 |
| Medium | 2 |
| Warning | 1 |

Formula:

```text
weighted_failures =
  critical_failures * 5 +
  high_failures * 3 +
  medium_failures * 2 +
  warning_failures * 1

weighted_failure_rate = weighted_failures / records_checked * 100

quality_score = greatest(0, 100 - weighted_failure_rate)
```

The score must always be explainable from the rule results and severity weights.

---

## Tableau Reporting Design

Tableau should read from the quality schema.

### Executive Data Quality Scorecard

Shows: overall quality score, total records checked, total failed records, total duplicate groups, critical issue count, quality score by bank, and quality score by dataset.

### Rule Performance Dashboard

Shows: rules executed, pass and fail counts, pass percentage by rule, failure percentage by rule, most failed rules, and severity breakdown.

### Duplicate Analysis Dashboard

Shows: duplicate groups by dataset, duplicate groups by bank, top duplicate keys, duplicate count trend by run, and drill-down into duplicate details.

### Failed Records Explorer

Shows: failed records by rule, by dataset, by severity, and by bank, with source file and ingestion timestamp.

### Bank Comparison Dashboard

Shows: quality score by bank, failed records by bank, duplicate groups by bank, the critical/high/medium/warning breakdown, and best and worst quality contributors.

---

## Demonstration Story

> We preserved the original data, standardised it for processing, and then measured its quality through a dedicated rule-based assessment layer.
>
> The framework identifies missing values, invalid values, duplicate records, reference mismatches, and business-rule violations.
>
> It does not hide bad data. It records the issue, stores the failed records, calculates scorecards, and exposes the results to Tableau for investigation and governance reporting.

---

## Minimum Build Order

1. Create the quality schema.
2. Create the quality reporting tables.
3. Populate `quality.rule_catalog` with the first set of rules.
4. Execute validation checks against Bronze or Silver tables.
5. Insert results into `quality.rule_results`.
6. Insert exceptions into `quality.failed_records`.
7. Run duplicate detection and populate `quality.duplicate_records` and `quality.duplicate_details`.
8. Generate `quality.summary`.
9. Generate `quality.scorecard`.
10. Connect Tableau to the quality schema.

---

## Success Criteria

This workstream is successful when stakeholders can answer:

- What is the overall quality score of the received data?
- Which datasets have the most issues?
- Which banks submitted the lowest-quality data?
- Which rules failed most often?
- Which records failed validation?
- Which records appear to be duplicated?
- Where are the failed records stored?
- How were the scorecards calculated?
- Which issues are critical, high, medium, or warning?
- Is the data sensible enough for downstream analytics?

---

## Final Positioning

This is not a data-cleaning workstream. This is a data quality reporting workstream. The value is visibility, auditability, and evidence.

The framework shows the customer that IOMETE can detect inconsistencies in received supervisory banking data and report them clearly without hiding or altering the original records.

---

## Implementation Reference

The concrete implementation of this framework for the Bronze layer is in [`scripts/03_bronze_quality_framework_v2.sql`](../scripts/03_bronze_quality_framework_v2.sql). Note that the implemented rule IDs (ROW001, LIN001, DUP001, ACC/POS/POSTXN/BRANCH/CREDITM/CREDITO/DEP series) differ from the illustrative DQ001–DQ010 examples above, and the implementation currently consolidates duplicate evidence into `quality.duplicate_records` without a separate `duplicate_details` table.
