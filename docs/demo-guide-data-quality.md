# Data Quality Reporting Demo Guide

## Purpose

This guide explains how to demonstrate the Data Quality Reporting Framework to stakeholders.

The demo focuses on one message:

> We preserve the received data, assess its quality, detect inconsistencies, store the evidence, and expose the results through scorecards and dashboards.

---

## Demo Flow

### 1. Start with the Problem

Reporting banks submit raw CSV files. The regulator needs to know whether the data is complete, valid, consistent, non-duplicated, and sensible before downstream analytics.

The key message is:

> Data quality must be measured and reported before the data is trusted for analytics.

---

### 2. Show the Architecture

Open the framework document:

```text
docs/data-quality-reporting-framework.md
>
Explain the end-to-end flow:
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
Key explanation:
Bronze preserves the raw evidence.
Silver standardises the data for processing.
The Data Quality Assessment layer observes and measures issues.
The Quality Schema stores all validation evidence.
Dashboards expose the findings to stakeholders.

3. Show the Quality Schema
Explain that all data quality evidence is stored in:
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
Explain the purpose of each table:
Table	Purpose
quality.rule_catalog	Defines the data quality rules
quality.pipeline_runs	Tracks each quality execution run
quality.rule_results	Stores pass/fail statistics per rule
quality.failed_records	Stores records that failed validation
quality.duplicate_records	Stores duplicate groups by key
quality.duplicate_details	Stores individual records inside duplicate groups
quality.summary	Stores executive-level quality metrics
quality.scorecard	Stores quality scores by bank, dataset, and run

4. Answer Stakeholder Questions
Stakeholder Question	Demo Answer
Statistics in terms of data quality?	Use quality.summary and quality.rule_results
Where are records left behind?	Use quality.failed_records
Duplication check?	Use quality.duplicate_records and quality.duplicate_details
Where are scorecards from?	From rule results and severity weights
Did you sort them out?	No. Issues are reported, not hidden
Sensible data?	Business rules check invalid amounts, dates, rates, and references
Main talking point:
This framework does not hide bad data. It exposes issues clearly so they can be investigated.
5. Show Example Queries
Executive Summary
SELECT *
FROM mzbq_catalog.quality.summary;
Use this to show:
Total records checked
Total failed records
Duplicate groups
Critical issues
Overall quality score
Rule Results
SELECT *
FROM mzbq_catalog.quality.rule_results
ORDER BY records_failed DESC;
Use this to show:
Which rules failed most often
Which datasets have the most issues
Pass and fail percentages
Failed Records
SELECT *
FROM mzbq_catalog.quality.failed_records
ORDER BY detected_at DESC;
Use this to show:
The actual records that failed validation
The reason each record failed
The source table, source file, and detected timestamp
Duplicate Records
SELECT *
FROM mzbq_catalog.quality.duplicate_records
ORDER BY duplicate_count DESC;
Use this to show:
Duplicate keys
Duplicate counts
Affected datasets
Affected banks, where available
Scorecard
SELECT *
FROM mzbq_catalog.quality.scorecard
ORDER BY quality_score ASC;
Use this to show:
Lowest quality banks first
Failed records by bank
Duplicate groups by bank
Quality score by dataset and run

6. Show the Dashboards
Recommended dashboard sequence:
Executive Data Quality Scorecard
Bank Comparison
Rule Performance
Duplicate Analysis
Failed Records Explorer
Demo message:
The dashboards are built from the quality schema, not from hidden logic inside Tableau. Every number can be traced back to a rule result or failed record.

7. Close with the Value
This framework gives the regulator:
Transparency
Auditability
Evidence
Accountability
Quality improvement visibility
Final closing statement:
We preserve the data, measure its quality, report the issues, and make the results traceable. We do not silently clean, delete, or hide problematic records.

Demo Success Criteria
The demo is successful when stakeholders can clearly answer:
What is the overall quality of the data?
Which datasets have the most issues?
Which banks submitted lower-quality data?
Which rules failed most often?
Which records failed validation?
Which duplicate records were detected?
Where are the failed records stored?
How were the scorecards calculated?
Which issues are critical, high, medium, or warning?
Is the data sensible enough for downstream analytics?
Final Message
This is a Data Quality Reporting workstream.
It does not replace the other analytics use cases.
Its value is to show that IOMETE can detect inconsistencies in supervisory banking data, store the evidence, and report the results clearly to regulators and data owners.
