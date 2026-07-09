# Credit Risk & Anomaly Detection Analytics Solution
## Solution Demonstration Report and Proposed Architecture

*Prepared for decision review — July 2026*

---

## 1. Executive Summary

This report consolidates the outcomes of the solution demonstration covering an end-to-end analytics platform for credit risk monitoring and transaction anomaly detection. The proposed solution combines three layers: an **IOMETE lakehouse** (Apache Spark and Apache Iceberg) as the data foundation, **Tableau** (Desktop, Prep, and Server) as the analytics and reporting layer, and **Python-based machine learning** (Jupyter, pandas, scikit-learn) for anomaly detection and credit scoring.

The demonstration showed that an analyst can move fluidly between the data tool and the reporting tool, that data quality can be validated systematically before it reaches dashboards or models, and that AI assistance in Tableau reduces the effort of building calculations and answering ad-hoc questions. The remaining decisions relate to Tableau Server sizing, licensing, and implementation cost, which are summarised in Section 7.

---

## 2. Business Context and Objectives

The solution targets two connected use cases for the bank:

**Credit risk oversight.** A Credit Risk Overview dashboard tracks key performance indicators — most importantly the NPL (non-performing loan) rate — and how they evolve over time, broken down geographically by country, province, and district. Portfolio KPIs are enriched with macro- and micro-economic context such as inflation and GDP, so that risk trends can be interpreted against the wider economy rather than in isolation.

**Transaction anomaly detection.** A machine learning workstream detects anomalies in PoS (point-of-sale) transactions. The model is trained on historical anomalies that have already been identified and shared, so it learns from known, expected anomaly patterns and can then flag similar behaviour in new data. The same modelling foundation extends naturally to credit scoring.

The end goal is a decision-ready platform: a data warehouse feeding Tableau for decision-making, with ML models surfacing risks that manual review would miss.

---

## 3. Proposed Architecture

The architecture demonstrated has three layers connected in a straightforward pipeline:

**Data layer — IOMETE lakehouse.** A connection to IOMETE is established using Spark, connecting to the IOMETE catalog. Apache Iceberg underpins the data lake and supports normalisation of source data into consistent, queryable tables. This layer acts as the single source of truth: curated views are exposed downstream rather than raw tables.

**Analytics layer — Tableau.** Tableau connects to the lakehouse via JDBC. Both connection modes are possible: a **live connection** directly to the data, or an **extract**. The demonstration concluded that extracts are the better default for this workload — performance is more predictable, and it works within the row limits imposed on the server. Dashboards are authored in Tableau Desktop and published to Tableau Server; Tableau Prep is available for data preparation, and Tableau Public was shown as a reference for published dashboard examples.

**ML layer — Python.** Data scientists work in Jupyter notebooks (Python ipykernel) using pandas, which handles large volumes of data well. Notebooks read from curated **views** rather than base tables — an important detail, because the views also carry the correct data types into the analysis. Models are built with standard Python ML libraries; the demonstration used a Random Forest classifier.

A practical operational note from the session: session memory allocation should be **parameterised** rather than fixed, so notebook and query sessions can be tuned to the workload instead of being over- or under-provisioned.

---

## 4. Data Quality and Statistics

A recurring theme of the session was that data quality must be evidenced, not assumed. The quality assessment covered the following questions:

**Completeness — where are records left behind?** The pipeline must account for every record: which table each record lands in, whether records are dropped between stages, and whether the counts reconcile. Null checks are run explicitly as part of the workflow.

**Duplication.** Duplicate checks are performed before data is used for reporting or modelling, and duplicates are sorted out at the preparation stage rather than being handled downstream in each dashboard or notebook.

**Provenance of scorecards.** The origin of the credit scorecards must be documented — where the scores come from, how they were derived, and whether they remain valid for the current portfolio.

**Sensibility of the data.** Values are sanity-checked against domain expectations (for example, NPL rates, inflation, and GDP figures falling within plausible ranges) before they are trusted in any KPI.

**Outlier detection.** Outliers are detected both statistically during exploratory analysis and visually in Tableau, where outlier detection can be applied per view.

A data quality report summarising these statistics — completeness, duplication, nulls, outliers, and provenance — should accompany the platform so stakeholders can see the state of the data at a glance.

---

## 5. Analytics and Reporting in Tableau

**Geographic analysis.** Latitude and longitude fields are assigned a geographic role, enabling map visualisations at country, province, and district level (with district used as the reference geography). Fields are placed on Detail and Label to control what appears on the map, and Measure Names / Measure Values are used to display multiple KPIs together. The result is a dashboard map showing risk concentration by area.

**Calculated fields with AI assistance.** The NPL rate is built as a calculated field. Tableau's AI agent can be used to generate the right formula, so analysts do not need to recall syntax — they describe the calculation and refine the generated result. More broadly, dashboards can be built either by traditional drag-and-drop or with AI assistance, and users can ask questions of their data in natural language to get the information they want.

**Alerts and monitoring.** Alerts can be set on visualisations for trends, thresholds, and outliers, turning dashboards from passive reports into active monitoring. This is directly relevant to the credit risk KPIs: a breach of an NPL threshold can notify the responsible team automatically.

**Accelerators.** Tableau's banking accelerators (for example, banking loans) mean the team does not start from scratch — pre-built dashboard structures are adapted to the bank's data. A slicer for the bank allows filtering the same dashboards per institution or entity.

**AI provider.** AI features on Tableau Server use the organisation's own LLM provider (for example OpenAI or similar), so the choice of provider — and the associated data governance — remains under the bank's control.

---

## 6. Machine Learning Workstream

The modelling approach demonstrated follows a disciplined sequence:

**Exploratory data analysis.** The notebook begins by checking the data shape, nulls, and duplicates, then explores distributions. Data volume matters here: if the dataset is too small, the model could overfit, so the size and representativeness of the training data must be confirmed before results are trusted.

**Feature engineering.** Day-of-week and day-name features are derived from transaction timestamps, since the day can influence whether an anomaly occurs, and knowing *when* anomalies happen is analytically useful in itself. Each anomaly also carries a type, allowing analysis by anomaly category. Some fields are cast to float to make them usable as numeric features.

**Feature selection.** A correlation matrix, plotted as a heat map, guides feature selection — redundant or uninformative features are removed before training.

**Model and evaluation.** A Random Forest classifier is trained on the labelled anomalies. Because the data is **imbalanced** (anomalies are rare relative to normal transactions), overall accuracy is misleading; **precision and recall** are the correct measures of whether the model is performing well. Some machine learning models require balanced data, which may call for resampling techniques, while deep learning approaches can relearn missed patterns over time if extended in future phases.

**Outputs.** The immediate deliverable is a PoS transaction anomaly model producing expected-anomaly flags, with credit scoring as the follow-on application of the same pipeline.

---

## 7. Platform, Licensing, and Cost Considerations

The following commercial and operational items were raised and need confirmation before a final decision:

**Tableau Server costing and implementation.** Both the SaaS/subscription cost of Tableau Server and the one-off implementation cost need to be quantified. Licensing is **user-based**, so an accurate count of viewers, explorers, and creators drives the price.

**Sizing.** Server sizing must reflect the expected data volumes, extract refresh schedules, and concurrent users. Related to this, the row limit on the server constrains live-query patterns and reinforces the recommendation to use extracts.

**Session resources.** Memory assigned to analytical sessions (Jupyter and query sessions) should be parameterised so it can be tuned per workload.

**Connectivity.** JDBC is the standard connection path from Tableau to IOMETE; Spark provides the connection for the ML/notebook layer.

---

## 8. Recommendation and Next Steps

The demonstration validated the full path from lakehouse to dashboard to model. To reach a decision, the following steps are recommended: finalise the Tableau Server sizing and user-based licence count and obtain firm pricing including implementation; agree the data quality report format and thresholds (completeness, duplicates, nulls, outliers) as an acceptance criterion for go-live; confirm the training data volume for the anomaly model is sufficient to avoid overfitting, and agree precision/recall targets with the risk team; and present the final solution and final architecture, incorporating the costs above, to the decision-makers.

Once these items are confirmed, the platform is ready to move from demonstration to implementation.
