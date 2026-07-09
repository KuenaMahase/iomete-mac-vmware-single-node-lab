# Data Quality Reporting Demo Guide

## Purpose

This guide explains how to demonstrate the Data Quality Reporting Framework to stakeholders.

The demo focuses on one message:

> We preserve the received data, assess its quality, detect inconsistencies, store the evidence, and expose the results through scorecards and dashboards.

## Demo Flow

### 1. Start with the problem

Reporting banks submit raw CSV files. The regulator needs to know whether the data is complete, valid, consistent, non-duplicated, and sensible before downstream analytics.

### 2. Show the architecture

Open:

```text
docs/data-quality-reporting-framework.md
Explain the flow:
Reporting Banks
  ↓
Raw CSV Submissions
  ↓
Bronze Evidence Store
  ↓
Silver Conformed Data
  ↓
Data Quality Assessment
  ↓
Quality Schema
  ↓
Tableau Dashboards
3. Show the quality schema
Explain that all evidence is stored in:
mzbq_catalog.quality
Key tables:
quality.rule_catalog
quality.pipeline_runs
quality.rule_results
quality.failed_records
quality.duplicate_records
quality.duplicate_details
quality.summary
quality.scorecard
4. Answer stakeholder questions
Question	Answer
Statistics in terms of data quality?	Use quality.summary and quality.rule_results
Where are records left behind?	Use quality.failed_records
Duplication check?	Use quality.duplicate_records and quality.duplicate_details
Where are scorecards from?	From rule results and severity weights
Did you sort them out?	No. Issues are reported, not hidden
Sensible data?	Business rules check invalid amounts, dates, rates, and references
5. Show example queries
SELECT *
FROM mzbq_catalog.quality.summary;
SELECT *
FROM mzbq_catalog.quality.rule_results
ORDER BY records_failed DESC;
SELECT *
FROM mzbq_catalog.quality.failed_records
ORDER BY detected_at DESC;
SELECT *
FROM mzbq_catalog.quality.duplicate_records
ORDER BY duplicate_count DESC;
SELECT *
FROM mzbq_catalog.quality.scorecard
ORDER BY quality_score ASC;
6. Close with the value
This framework gives the regulator transparency, auditability, and evidence.
It does not hide bad data.
It exposes issues clearly so data owners can investigate and improve submissions.
