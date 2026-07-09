-- ============================================================
-- BRONZE-ONLY DATA QUALITY REPORTING FRAMEWORK  (v2 - cleaned)
-- Catalog: mzbq_catalog
-- Source:  mzbq_catalog.bronze.*   (read-only, never modified)
-- Output:  mzbq_catalog.quality.*
--
-- Fixes vs v1:
--   * Correct execution order (pipeline_runs now AFTER summary)
--   * ROW001 can actually fail (expected bank x dataset matrix)
--   * Whole-row duplicate hash excludes lineage columns
--   * Whole-row duplicate check restored for ALL 7 datasets
--   * All dead / broken / duplicated statements removed
--   * rule_catalog aligned with the rules actually implemented
--   * Reference batch now flows into rule_results, summary,
--     scorecard and pipeline_runs (not just failed_records)
--
-- NOTE ON LINEAGE COLUMNS:
--   This script assumes bronze tables carry `_source_file` and
--   `_ingested_at` (exchange_rates uses `source_file`/`ingested_at`).
--   If your bronze load stamped `_ingestion_ts` instead (as in
--   01_ingest_banking_data.py), rename accordingly. Verify first:
--     DESCRIBE mzbq_catalog.bronze.mapa_5a_contas_bancarias;
-- ============================================================

CREATE SCHEMA IF NOT EXISTS mzbq_catalog.quality;

-- ============================================================
-- STEP 0: Reset quality layer (Bronze untouched)
-- ============================================================

DROP VIEW IF EXISTS mzbq_catalog.quality.vw_quality_executive_summary;
DROP VIEW IF EXISTS mzbq_catalog.quality.vw_scorecard_by_bank;
DROP VIEW IF EXISTS mzbq_catalog.quality.vw_rule_performance;
DROP VIEW IF EXISTS mzbq_catalog.quality.vw_failed_records_report;
DROP VIEW IF EXISTS mzbq_catalog.quality.vw_duplicate_report;
DROP VIEW IF EXISTS mzbq_catalog.quality.vw_bronze_dataset_totals;
DROP VIEW IF EXISTS mzbq_catalog.quality.vw_bronze_reference_dataset_totals;
DROP VIEW IF EXISTS mzbq_catalog.quality.vw_expected_datasets;

DROP TABLE IF EXISTS mzbq_catalog.quality.pipeline_runs;
DROP TABLE IF EXISTS mzbq_catalog.quality.scorecard;
DROP TABLE IF EXISTS mzbq_catalog.quality.summary;
DROP TABLE IF EXISTS mzbq_catalog.quality.duplicate_records;
DROP TABLE IF EXISTS mzbq_catalog.quality.failed_records;
DROP TABLE IF EXISTS mzbq_catalog.quality.rule_results;
DROP TABLE IF EXISTS mzbq_catalog.quality.rule_catalog;

-- ============================================================
-- STEP 1: Rule catalogue (aligned with implemented rules)
-- ============================================================

CREATE TABLE mzbq_catalog.quality.rule_catalog (
  rule_id STRING,
  rule_name STRING,
  rule_type STRING,
  dataset STRING,
  severity STRING,
  business_question STRING
)
USING iceberg;

INSERT INTO mzbq_catalog.quality.rule_catalog VALUES
-- Cross-dataset rules
('ROW001',     'Dataset must contain records',                    'PRESENCE',     'ALL',                'CRITICAL', 'Did we receive data from every bank for every dataset?'),
('LIN001',     'Source file must be present',                     'LINEAGE',      'ALL',                'HIGH',     'Can we trace records back to source files?'),
('DUP001',     'Whole-row duplicate records detected',            'DUPLICATE',    'ALL',                'HIGH',     'Are there exact duplicate raw records?'),

-- bank_accounts
('ACC001',     'IBAN must not be empty',                          'COMPLETENESS', 'bank_accounts',      'CRITICAL', 'Are account records usable?'),
('ACC002',     'NIB must not be empty',                           'COMPLETENESS', 'bank_accounts',      'CRITICAL', 'Are account records traceable to a bank account identifier?'),

-- pos_list
('POS001',     'POS ID must not be empty',                        'COMPLETENESS', 'pos_list',           'CRITICAL', 'Can each POS device be identified?'),
('POS002',     'Merchant ID must not be empty',                   'COMPLETENESS', 'pos_list',           'HIGH',     'Can each POS device be linked to a merchant?'),
('POS003',     'District code must not be empty',                 'COMPLETENESS', 'pos_list',           'MEDIUM',   'Can each POS device be located geographically?'),
('POS004',     'Latitude must be valid',                          'VALIDITY',     'pos_list',           'MEDIUM',   'Is POS location data sensible?'),
('POS005',     'Longitude must be valid',                         'VALIDITY',     'pos_list',           'MEDIUM',   'Is POS location data sensible?'),

-- pos_transactions
('POSTXN001',  'POS transaction ID must not be empty',            'COMPLETENESS', 'pos_transactions',   'CRITICAL', 'Can POS transactions be identified?'),
('POSTXN002',  'POS transaction value must not be negative',      'VALIDITY',     'pos_transactions',   'HIGH',     'Are POS transaction values sensible?'),
('POSTXN003',  'POS commission must not be negative',             'VALIDITY',     'pos_transactions',   'MEDIUM',   'Are POS commissions sensible?'),

-- branch_transactions
('BRANCH001',  'Branch transaction NUIB must not be empty',       'COMPLETENESS', 'branch_transactions','CRITICAL', 'Can branch transaction customers be identified?'),
('BRANCH003',  'Branch transaction value must not be negative',   'VALIDITY',     'branch_transactions','HIGH',     'Are branch transaction values sensible?'),
('BRANCH004',  'Branch commission must not be negative',          'VALIDITY',     'branch_transactions','MEDIUM',   'Are branch commissions sensible?'),

-- credit_master_data
('CREDITM001', 'Credit master NUIB must not be empty',            'COMPLETENESS', 'credit_master_data', 'CRITICAL', 'Can credit records be identified?'),
('CREDITM002', 'Credit customer number must not be empty',        'COMPLETENESS', 'credit_master_data', 'CRITICAL', 'Can credit records be linked to customers?'),
('CREDITM003', 'Credit type must not be empty',                   'COMPLETENESS', 'credit_master_data', 'HIGH',     'Can credit records be classified?'),
('CREDITM004', 'Credit latitude must be valid',                   'VALIDITY',     'credit_master_data', 'MEDIUM',   'Is credit location data sensible?'),
('CREDITM005', 'Credit longitude must be valid',                  'VALIDITY',     'credit_master_data', 'MEDIUM',   'Is credit location data sensible?'),

-- credit_operations
('CREDITO001', 'Credit operation NUIB must not be empty',         'COMPLETENESS', 'credit_operations',  'CRITICAL', 'Can credit operation records be identified?'),
('CREDITO002', 'Overdue interest must not be negative',           'VALIDITY',     'credit_operations',  'HIGH',     'Are arrears balances sensible?'),
('CREDITO003', 'Accruing interest must not be negative',          'VALIDITY',     'credit_operations',  'HIGH',     'Are interest balances sensible?'),
('CREDITO004', 'Instalment value must not be negative',           'VALIDITY',     'credit_operations',  'HIGH',     'Are instalment values sensible?'),
('CREDITO005', 'Amount collected must not be negative',           'VALIDITY',     'credit_operations',  'HIGH',     'Are collection amounts sensible?'),

-- deposits
('DEP001',     'Deposit NUIB must not be empty',                  'COMPLETENESS', 'deposits',           'CRITICAL', 'Can deposit records be identified?'),
('DEP002',     'Deposit currency must not be empty',              'COMPLETENESS', 'deposits',           'HIGH',     'Can deposit values be interpreted?'),
('DEP003',     'Deposit date must not be empty',                  'COMPLETENESS', 'deposits',           'HIGH',     'Can deposits be placed in time?'),
('DEP004',     'Deposit latitude must be valid',                  'VALIDITY',     'deposits',           'MEDIUM',   'Is deposit location data sensible?'),
('DEP005',     'Deposit longitude must be valid',                 'VALIDITY',     'deposits',           'MEDIUM',   'Is deposit location data sensible?'),

-- Reference tables
('REFBANK001', 'Reference bank ID must not be empty',             'COMPLETENESS', 'ref_bancos',              'CRITICAL', 'Can each reference bank be uniquely identified?'),
('REFBANK002', 'Reference bank name must not be empty',           'COMPLETENESS', 'ref_bancos',              'HIGH',     'Does each reference bank have a readable name?'),
('CAE001',     'CAE code must not be empty',                      'COMPLETENESS', 'ref_cae',                 'CRITICAL', 'Can each economic activity category be identified?'),
('CAE002',     'CAE description must not be empty',               'COMPLETENESS', 'ref_cae',                 'HIGH',     'Does each CAE code have a meaningful description?'),
('MCC001',     'MCC code must not be empty',                      'COMPLETENESS', 'ref_mcc',                 'CRITICAL', 'Can each merchant category be identified?'),
('MCC002',     'MCC description must not be empty',               'COMPLETENESS', 'ref_mcc',                 'HIGH',     'Does each MCC code have a meaningful description?'),
('MCC003',     'MCC base average ticket must not be negative',    'VALIDITY',     'ref_mcc',                 'HIGH',     'Is the expected base ticket amount sensible?'),
('DIST001',    'District code must not be empty',                 'COMPLETENESS', 'ref_distritos',           'CRITICAL', 'Can each district be identified?'),
('DIST002',    'District name must not be empty',                 'COMPLETENESS', 'ref_distritos',           'HIGH',     'Does each district code have a district name?'),
('DIST003',    'Province must not be empty',                      'COMPLETENESS', 'ref_distritos',           'HIGH',     'Can each district be linked to a province?'),
('DIST004',    'Administrative post code must not be empty',      'COMPLETENESS', 'ref_distritos',           'MEDIUM',   'Can each administrative post be identified?'),
('ANOM001',    'Expected anomaly bank ID must not be empty',      'COMPLETENESS', 'ref_anomalias_esperadas', 'CRITICAL', 'Can expected anomalies be linked to a reporting bank?'),
('ANOM002',    'Expected anomaly type must not be empty',         'COMPLETENESS', 'ref_anomalias_esperadas', 'CRITICAL', 'Can expected anomalies be classified?'),
('ANOM003',    'Expected anomaly record ID must not be empty',    'COMPLETENESS', 'ref_anomalias_esperadas', 'HIGH',     'Can each expected anomaly record be traced?'),
('ANOM004',    'Expected anomaly description must not be empty',  'COMPLETENESS', 'ref_anomalias_esperadas', 'MEDIUM',   'Does each expected anomaly have explanatory text?'),
('EXR001',     'USD exchange rate must be greater than zero',     'VALIDITY',     'exchange_rates',          'CRITICAL', 'Is the USD exchange rate positive and economically sensible?'),
('EXR002',     'EUR exchange rate must be greater than zero',     'VALIDITY',     'exchange_rates',          'CRITICAL', 'Is the EUR exchange rate positive and economically sensible?'),
('EXR003',     'ZAR exchange rate must be greater than zero',     'VALIDITY',     'exchange_rates',          'CRITICAL', 'Is the ZAR exchange rate positive and economically sensible?'),
('EXR004',     'Exchange-rate period must not be empty',          'COMPLETENESS', 'exchange_rates',          'CRITICAL', 'Can each exchange-rate record be linked to a reporting period?');

-- ============================================================
-- STEP 2: Quality reporting tables
-- ============================================================

CREATE TABLE mzbq_catalog.quality.rule_results (
  batch_id STRING,
  rule_id STRING,
  rule_name STRING,
  rule_type STRING,
  dataset STRING,
  banco_id STRING,
  severity STRING,
  total_records BIGINT,
  passed_records BIGINT,
  failed_records BIGINT,
  pass_rate DOUBLE,
  run_timestamp TIMESTAMP
)
USING iceberg;

CREATE TABLE mzbq_catalog.quality.failed_records (
  batch_id STRING,
  rule_id STRING,
  rule_name STRING,
  rule_type STRING,
  dataset STRING,
  banco_id STRING,
  severity STRING,
  record_key STRING,
  failed_column STRING,
  failed_value STRING,
  expected_condition STRING,
  source_file STRING,
  ingested_at TIMESTAMP,
  run_timestamp TIMESTAMP
)
USING iceberg;

CREATE TABLE mzbq_catalog.quality.duplicate_records (
  batch_id STRING,
  dataset STRING,
  banco_id STRING,
  duplicate_type STRING,
  duplicate_key STRING,
  duplicate_count BIGINT,
  example_source_file STRING,
  run_timestamp TIMESTAMP
)
USING iceberg;

CREATE TABLE mzbq_catalog.quality.summary (
  batch_id STRING,
  dataset STRING,
  banco_id STRING,
  total_records BIGINT,
  total_failed_records BIGINT,
  duplicate_groups BIGINT,
  critical_failures BIGINT,
  high_failures BIGINT,
  medium_failures BIGINT,
  quality_score DOUBLE,
  run_timestamp TIMESTAMP
)
USING iceberg;

CREATE TABLE mzbq_catalog.quality.scorecard (
  batch_id STRING,
  banco_id STRING,
  dataset STRING,
  total_rules BIGINT,
  rules_with_failures BIGINT,
  total_records_checked BIGINT,
  total_failed_records BIGINT,
  overall_score DOUBLE,
  run_timestamp TIMESTAMP
)
USING iceberg;

CREATE TABLE mzbq_catalog.quality.pipeline_runs (
  batch_id STRING,
  source_layer STRING,
  assessment_scope STRING,
  status STRING,
  datasets_checked BIGINT,
  banks_checked BIGINT,
  total_records_assessed BIGINT,
  total_failed_records BIGINT,
  duplicate_groups BIGINT,
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  run_notes STRING
)
USING iceberg;

-- ============================================================
-- STEP 3: Dataset totals views (persistent, reused throughout)
-- ============================================================

CREATE OR REPLACE VIEW mzbq_catalog.quality.vw_bronze_dataset_totals AS
SELECT 'bank_accounts' AS dataset, banco_id, COUNT(*) AS total_records
FROM mzbq_catalog.bronze.mapa_5a_contas_bancarias GROUP BY banco_id
UNION ALL
SELECT 'pos_list', banco_id, COUNT(*)
FROM mzbq_catalog.bronze.mapa_4a_listagem_pos GROUP BY banco_id
UNION ALL
SELECT 'pos_transactions', banco_id, COUNT(*)
FROM mzbq_catalog.bronze.mapa_4b_transacoes_pos GROUP BY banco_id
UNION ALL
SELECT 'branch_transactions', banco_id, COUNT(*)
FROM mzbq_catalog.bronze.mapa_1c_transacoes_balcao GROUP BY banco_id
UNION ALL
SELECT 'credit_master_data', banco_id, COUNT(*)
FROM mzbq_catalog.bronze.quadro_1_dados_mestres_credito GROUP BY banco_id
UNION ALL
SELECT 'credit_operations', banco_id, COUNT(*)
FROM mzbq_catalog.bronze.quadro_2_operacoes_credito GROUP BY banco_id
UNION ALL
SELECT 'deposits', banco_id, COUNT(*)
FROM mzbq_catalog.bronze.quadro_9_depositos GROUP BY banco_id;

CREATE OR REPLACE VIEW mzbq_catalog.quality.vw_bronze_reference_dataset_totals AS
SELECT 'ref_bancos' AS dataset, 'REFERENCE' AS banco_id, COUNT(*) AS total_records
FROM mzbq_catalog.bronze.ref_bancos
UNION ALL
SELECT 'ref_cae', 'REFERENCE', COUNT(*) FROM mzbq_catalog.bronze.ref_cae
UNION ALL
SELECT 'ref_mcc', 'REFERENCE', COUNT(*) FROM mzbq_catalog.bronze.ref_mcc
UNION ALL
SELECT 'ref_distritos', 'REFERENCE', COUNT(*) FROM mzbq_catalog.bronze.ref_distritos
UNION ALL
SELECT 'ref_anomalias_esperadas',
       COALESCE(NULLIF(TRIM(CAST(banco_id AS STRING)), ''), 'UNKNOWN_BANK'),
       COUNT(*)
FROM mzbq_catalog.bronze.ref_anomalias_esperadas
GROUP BY COALESCE(NULLIF(TRIM(CAST(banco_id AS STRING)), ''), 'UNKNOWN_BANK')
UNION ALL
SELECT 'exchange_rates', 'REFERENCE', COUNT(*) FROM mzbq_catalog.bronze.exchange_rates;

-- Expected bank x dataset matrix, so ROW001 can detect MISSING data.
-- Every bank in ref_bancos is expected to submit every dataset.
CREATE OR REPLACE VIEW mzbq_catalog.quality.vw_expected_datasets AS
SELECT b.banco_id, d.dataset
FROM (SELECT DISTINCT CAST(banco_id AS STRING) AS banco_id
      FROM mzbq_catalog.bronze.ref_bancos) b
CROSS JOIN (
  SELECT 'bank_accounts'       AS dataset UNION ALL
  SELECT 'pos_list'                       UNION ALL
  SELECT 'pos_transactions'               UNION ALL
  SELECT 'branch_transactions'            UNION ALL
  SELECT 'credit_master_data'             UNION ALL
  SELECT 'credit_operations'              UNION ALL
  SELECT 'deposits'
) d;

-- ============================================================
-- STEP 4: ROW001 - dataset presence (can now actually fail)
-- A bank/dataset pair that submitted nothing appears with 0
-- total_records and 1 failed record.
-- ============================================================

DELETE FROM mzbq_catalog.quality.rule_results
WHERE batch_id = 'bronze_quality_001' AND rule_id = 'ROW001';

INSERT INTO mzbq_catalog.quality.rule_results
SELECT
  'bronze_quality_001',
  'ROW001',
  'Dataset must contain records',
  'PRESENCE',
  e.dataset,
  e.banco_id,
  'CRITICAL',
  COALESCE(t.total_records, 0),
  COALESCE(t.total_records, 0),
  CASE WHEN COALESCE(t.total_records, 0) > 0 THEN 0 ELSE 1 END,
  CASE WHEN COALESCE(t.total_records, 0) > 0 THEN 100.0 ELSE 0.0 END,
  current_timestamp()
FROM mzbq_catalog.quality.vw_expected_datasets e
LEFT JOIN mzbq_catalog.quality.vw_bronze_dataset_totals t
  ON e.dataset = t.dataset AND e.banco_id = t.banco_id;

-- ============================================================
-- STEP 5: LIN001 - lineage failed records (all 7 datasets)
-- ============================================================

DELETE FROM mzbq_catalog.quality.failed_records
WHERE batch_id = 'bronze_quality_001' AND rule_id = 'LIN001';

INSERT INTO mzbq_catalog.quality.failed_records
SELECT 'bronze_quality_001','LIN001','Source file must be present','LINEAGE',
       'bank_accounts',banco_id,'HIGH',
       COALESCE(CAST(nib AS STRING),'UNKNOWN'),'_source_file',
       CAST(_source_file AS STRING),'_source_file must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_5a_contas_bancarias
WHERE _source_file IS NULL OR TRIM(CAST(_source_file AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','LIN001','Source file must be present','LINEAGE',
       'pos_list',banco_id,'HIGH',
       COALESCE(CAST(id_do_ponto AS STRING),'UNKNOWN'),'_source_file',
       CAST(_source_file AS STRING),'_source_file must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_4a_listagem_pos
WHERE _source_file IS NULL OR TRIM(CAST(_source_file AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','LIN001','Source file must be present','LINEAGE',
       'pos_transactions',banco_id,'HIGH',
       COALESCE(CAST(id_da_transaccao AS STRING),'UNKNOWN'),'_source_file',
       CAST(_source_file AS STRING),'_source_file must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_4b_transacoes_pos
WHERE _source_file IS NULL OR TRIM(CAST(_source_file AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','LIN001','Source file must be present','LINEAGE',
       'branch_transactions',banco_id,'HIGH',
       COALESCE(CAST(id_da_transaccao AS STRING),'UNKNOWN'),'_source_file',
       CAST(_source_file AS STRING),'_source_file must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_1c_transacoes_balcao
WHERE _source_file IS NULL OR TRIM(CAST(_source_file AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','LIN001','Source file must be present','LINEAGE',
       'credit_master_data',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'_source_file',
       CAST(_source_file AS STRING),'_source_file must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_1_dados_mestres_credito
WHERE _source_file IS NULL OR TRIM(CAST(_source_file AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','LIN001','Source file must be present','LINEAGE',
       'credit_operations',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'_source_file',
       CAST(_source_file AS STRING),'_source_file must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_2_operacoes_credito
WHERE _source_file IS NULL OR TRIM(CAST(_source_file AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','LIN001','Source file must be present','LINEAGE',
       'deposits',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'_source_file',
       CAST(_source_file AS STRING),'_source_file must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_9_depositos
WHERE _source_file IS NULL OR TRIM(CAST(_source_file AS STRING)) = '';

-- ============================================================
-- STEP 6: Business-rule failed records (bank datasets)
-- ============================================================

DELETE FROM mzbq_catalog.quality.failed_records
WHERE batch_id = 'bronze_quality_001'
  AND rule_id IN (
    'ACC001','ACC002',
    'POS001','POS002','POS003','POS004','POS005',
    'POSTXN001','POSTXN002','POSTXN003',
    'BRANCH001','BRANCH003','BRANCH004',
    'CREDITM001','CREDITM002','CREDITM003','CREDITM004','CREDITM005',
    'CREDITO001','CREDITO002','CREDITO003','CREDITO004','CREDITO005',
    'DEP001','DEP002','DEP003','DEP004','DEP005'
  );

-- 6A: bank_accounts -------------------------------------------------
INSERT INTO mzbq_catalog.quality.failed_records
SELECT 'bronze_quality_001','ACC001','IBAN must not be empty','COMPLETENESS',
       'bank_accounts',banco_id,'CRITICAL',
       COALESCE(CAST(nib AS STRING),'UNKNOWN'),'iban',CAST(iban AS STRING),
       'IBAN must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_5a_contas_bancarias
WHERE iban IS NULL OR TRIM(CAST(iban AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','ACC002','NIB must not be empty','COMPLETENESS',
       'bank_accounts',banco_id,'CRITICAL',
       COALESCE(CAST(iban AS STRING),'UNKNOWN'),'nib',CAST(nib AS STRING),
       'NIB must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_5a_contas_bancarias
WHERE nib IS NULL OR TRIM(CAST(nib AS STRING)) = '';

-- 6B: pos_list ------------------------------------------------------
INSERT INTO mzbq_catalog.quality.failed_records
SELECT 'bronze_quality_001','POS001','POS ID must not be empty','COMPLETENESS',
       'pos_list',banco_id,'CRITICAL',
       COALESCE(CAST(id_do_merchant AS STRING),'UNKNOWN'),'id_do_ponto',
       CAST(id_do_ponto AS STRING),'POS point ID must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_4a_listagem_pos
WHERE id_do_ponto IS NULL OR TRIM(CAST(id_do_ponto AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','POS002','Merchant ID must not be empty','COMPLETENESS',
       'pos_list',banco_id,'HIGH',
       COALESCE(CAST(id_do_ponto AS STRING),'UNKNOWN'),'id_do_merchant',
       CAST(id_do_merchant AS STRING),'Merchant ID must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_4a_listagem_pos
WHERE id_do_merchant IS NULL OR TRIM(CAST(id_do_merchant AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','POS003','District code must not be empty','COMPLETENESS',
       'pos_list',banco_id,'MEDIUM',
       COALESCE(CAST(id_do_ponto AS STRING),'UNKNOWN'),'codigo_do_distrito',
       CAST(codigo_do_distrito AS STRING),'District code must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_4a_listagem_pos
WHERE codigo_do_distrito IS NULL OR TRIM(CAST(codigo_do_distrito AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','POS004','Latitude must be valid','VALIDITY',
       'pos_list',banco_id,'MEDIUM',
       COALESCE(CAST(id_do_ponto AS STRING),'UNKNOWN'),'latitude',
       CAST(latitude AS STRING),'Latitude must be between -90 and 90',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_4a_listagem_pos
WHERE latitude IS NULL OR TRIM(CAST(latitude AS STRING)) = ''
   OR TRY_CAST(latitude AS DOUBLE) IS NULL
   OR TRY_CAST(latitude AS DOUBLE) NOT BETWEEN -90 AND 90
UNION ALL
SELECT 'bronze_quality_001','POS005','Longitude must be valid','VALIDITY',
       'pos_list',banco_id,'MEDIUM',
       COALESCE(CAST(id_do_ponto AS STRING),'UNKNOWN'),'longitude',
       CAST(longitude AS STRING),'Longitude must be between -180 and 180',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_4a_listagem_pos
WHERE longitude IS NULL OR TRIM(CAST(longitude AS STRING)) = ''
   OR TRY_CAST(longitude AS DOUBLE) IS NULL
   OR TRY_CAST(longitude AS DOUBLE) NOT BETWEEN -180 AND 180;

-- 6C: pos_transactions ----------------------------------------------
INSERT INTO mzbq_catalog.quality.failed_records
SELECT 'bronze_quality_001','POSTXN001','POS transaction ID must not be empty','COMPLETENESS',
       'pos_transactions',banco_id,'CRITICAL',
       COALESCE(CAST(pan AS STRING),'UNKNOWN'),'id_da_transaccao',
       CAST(id_da_transaccao AS STRING),'Transaction ID must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_4b_transacoes_pos
WHERE id_da_transaccao IS NULL OR TRIM(CAST(id_da_transaccao AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','POSTXN002','POS transaction value must not be negative','VALIDITY',
       'pos_transactions',banco_id,'HIGH',
       COALESCE(CAST(id_da_transaccao AS STRING),CAST(pan AS STRING),'UNKNOWN'),'valor_mt',
       CAST(valor_mt AS STRING),'Transaction value must be greater than or equal to zero',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_4b_transacoes_pos
WHERE TRIM(CAST(valor_mt AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(valor_mt AS STRING), ',', '.') AS DOUBLE) < 0
UNION ALL
SELECT 'bronze_quality_001','POSTXN003','POS commission must not be negative','VALIDITY',
       'pos_transactions',banco_id,'MEDIUM',
       COALESCE(CAST(id_da_transaccao AS STRING),CAST(pan AS STRING),'UNKNOWN'),'comissao_mt',
       CAST(comissao_mt AS STRING),'Commission must be greater than or equal to zero',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_4b_transacoes_pos
WHERE TRIM(CAST(comissao_mt AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(comissao_mt AS STRING), ',', '.') AS DOUBLE) < 0;

-- 6D: branch_transactions -------------------------------------------
INSERT INTO mzbq_catalog.quality.failed_records
SELECT 'bronze_quality_001','BRANCH001','Branch transaction NUIB must not be empty','COMPLETENESS',
       'branch_transactions',banco_id,'CRITICAL',
       COALESCE(CAST(id_da_transaccao AS STRING),'UNKNOWN'),'nuib',
       CAST(nuib AS STRING),'NUIB must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_1c_transacoes_balcao
WHERE nuib IS NULL OR TRIM(CAST(nuib AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','BRANCH003','Branch transaction value must not be negative','VALIDITY',
       'branch_transactions',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'valor',
       CAST(valor AS STRING),'Branch transaction value must be greater than or equal to zero',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_1c_transacoes_balcao
WHERE TRIM(CAST(valor AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(valor AS STRING), ',', '.') AS DOUBLE) < 0
UNION ALL
SELECT 'bronze_quality_001','BRANCH004','Branch commission must not be negative','VALIDITY',
       'branch_transactions',banco_id,'MEDIUM',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'comissao',
       CAST(comissao AS STRING),'Branch commission must be greater than or equal to zero',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.mapa_1c_transacoes_balcao
WHERE TRIM(CAST(comissao AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(comissao AS STRING), ',', '.') AS DOUBLE) < 0;

-- 6E: credit_master_data --------------------------------------------
INSERT INTO mzbq_catalog.quality.failed_records
SELECT 'bronze_quality_001','CREDITM001','Credit master NUIB must not be empty','COMPLETENESS',
       'credit_master_data',banco_id,'CRITICAL',
       COALESCE(CAST(numero_do_cliente AS STRING),'UNKNOWN'),'nuib',
       CAST(nuib AS STRING),'NUIB must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_1_dados_mestres_credito
WHERE nuib IS NULL OR TRIM(CAST(nuib AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','CREDITM002','Credit customer number must not be empty','COMPLETENESS',
       'credit_master_data',banco_id,'CRITICAL',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'numero_do_cliente',
       CAST(numero_do_cliente AS STRING),'Customer number must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_1_dados_mestres_credito
WHERE numero_do_cliente IS NULL OR TRIM(CAST(numero_do_cliente AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','CREDITM003','Credit type must not be empty','COMPLETENESS',
       'credit_master_data',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),CAST(numero_do_cliente AS STRING),'UNKNOWN'),'tipo_de_credito',
       CAST(tipo_de_credito AS STRING),'Credit type must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_1_dados_mestres_credito
WHERE tipo_de_credito IS NULL OR TRIM(CAST(tipo_de_credito AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','CREDITM004','Credit latitude must be valid','VALIDITY',
       'credit_master_data',banco_id,'MEDIUM',
       COALESCE(CAST(nuib AS STRING),CAST(numero_do_cliente AS STRING),'UNKNOWN'),'latitude',
       CAST(latitude AS STRING),'Latitude must be between -90 and 90',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_1_dados_mestres_credito
WHERE latitude IS NULL OR TRIM(CAST(latitude AS STRING)) = ''
   OR TRY_CAST(latitude AS DOUBLE) IS NULL
   OR TRY_CAST(latitude AS DOUBLE) NOT BETWEEN -90 AND 90
UNION ALL
SELECT 'bronze_quality_001','CREDITM005','Credit longitude must be valid','VALIDITY',
       'credit_master_data',banco_id,'MEDIUM',
       COALESCE(CAST(nuib AS STRING),CAST(numero_do_cliente AS STRING),'UNKNOWN'),'longitude',
       CAST(longitude AS STRING),'Longitude must be between -180 and 180',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_1_dados_mestres_credito
WHERE longitude IS NULL OR TRIM(CAST(longitude AS STRING)) = ''
   OR TRY_CAST(longitude AS DOUBLE) IS NULL
   OR TRY_CAST(longitude AS DOUBLE) NOT BETWEEN -180 AND 180;

-- 6F: credit_operations ---------------------------------------------
INSERT INTO mzbq_catalog.quality.failed_records
SELECT 'bronze_quality_001','CREDITO001','Credit operation NUIB must not be empty','COMPLETENESS',
       'credit_operations',banco_id,'CRITICAL',
       COALESCE(CAST(referencia_do_credito AS STRING),'UNKNOWN'),'nuib',
       CAST(nuib AS STRING),'NUIB must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_2_operacoes_credito
WHERE nuib IS NULL OR TRIM(CAST(nuib AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','CREDITO002','Overdue interest must not be negative','VALIDITY',
       'credit_operations',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'juros_vencidos',
       CAST(juros_vencidos AS STRING),'Overdue interest must be greater than or equal to zero',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_2_operacoes_credito
WHERE TRIM(CAST(juros_vencidos AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(juros_vencidos AS STRING), ',', '.') AS DOUBLE) < 0
UNION ALL
SELECT 'bronze_quality_001','CREDITO003','Accruing interest must not be negative','VALIDITY',
       'credit_operations',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'juros_vincendos',
       CAST(juros_vincendos AS STRING),'Accruing interest must be greater than or equal to zero',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_2_operacoes_credito
WHERE TRIM(CAST(juros_vincendos AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(juros_vincendos AS STRING), ',', '.') AS DOUBLE) < 0
UNION ALL
SELECT 'bronze_quality_001','CREDITO004','Instalment value must not be negative','VALIDITY',
       'credit_operations',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'valor_da_prestacao',
       CAST(valor_da_prestacao AS STRING),'Instalment value must be greater than or equal to zero',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_2_operacoes_credito
WHERE TRIM(CAST(valor_da_prestacao AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(valor_da_prestacao AS STRING), ',', '.') AS DOUBLE) < 0
UNION ALL
SELECT 'bronze_quality_001','CREDITO005','Amount collected must not be negative','VALIDITY',
       'credit_operations',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'montante_cobrado',
       CAST(montante_cobrado AS STRING),'Amount collected must be greater than or equal to zero',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_2_operacoes_credito
WHERE TRIM(CAST(montante_cobrado AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(montante_cobrado AS STRING), ',', '.') AS DOUBLE) < 0;

-- 6G: deposits -------------------------------------------------------
INSERT INTO mzbq_catalog.quality.failed_records
SELECT 'bronze_quality_001','DEP001','Deposit NUIB must not be empty','COMPLETENESS',
       'deposits',banco_id,'CRITICAL',
       COALESCE(CAST(referencia_do_deposito AS STRING),'UNKNOWN'),'nuib',
       CAST(nuib AS STRING),'NUIB must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_9_depositos
WHERE nuib IS NULL OR TRIM(CAST(nuib AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','DEP002','Deposit currency must not be empty','COMPLETENESS',
       'deposits',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'moeda',
       CAST(moeda AS STRING),'Currency must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_9_depositos
WHERE moeda IS NULL OR TRIM(CAST(moeda AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','DEP003','Deposit date must not be empty','COMPLETENESS',
       'deposits',banco_id,'HIGH',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'data_de_deposito',
       CAST(data_de_deposito AS STRING),'Deposit date must not be null or empty',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_9_depositos
WHERE data_de_deposito IS NULL OR TRIM(CAST(data_de_deposito AS STRING)) = ''
UNION ALL
SELECT 'bronze_quality_001','DEP004','Deposit latitude must be valid','VALIDITY',
       'deposits',banco_id,'MEDIUM',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'latitude',
       CAST(latitude AS STRING),'Latitude must be between -90 and 90',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_9_depositos
WHERE latitude IS NULL OR TRIM(CAST(latitude AS STRING)) = ''
   OR TRY_CAST(latitude AS DOUBLE) IS NULL
   OR TRY_CAST(latitude AS DOUBLE) NOT BETWEEN -90 AND 90
UNION ALL
SELECT 'bronze_quality_001','DEP005','Deposit longitude must be valid','VALIDITY',
       'deposits',banco_id,'MEDIUM',
       COALESCE(CAST(nuib AS STRING),'UNKNOWN'),'longitude',
       CAST(longitude AS STRING),'Longitude must be between -180 and 180',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.quadro_9_depositos
WHERE longitude IS NULL OR TRIM(CAST(longitude AS STRING)) = ''
   OR TRY_CAST(longitude AS DOUBLE) IS NULL
   OR TRY_CAST(longitude AS DOUBLE) NOT BETWEEN -180 AND 180;

-- ============================================================
-- STEP 7: Duplicate detection (all 7 datasets)
--
-- The whole-row hash EXCLUDES lineage columns so that two
-- identical business records loaded from different files or at
-- different times are still detected as duplicates.
--
-- `SELECT * EXCEPT(...)` requires Spark 3.4+ / IOMETE-supported
-- syntax. If unsupported, replace the inner SELECT with an
-- explicit business-column list per table.
-- Adjust the EXCEPT list to your actual lineage columns
-- (e.g. add _source_bank, _batch_id, _record_num if present).
-- ============================================================

DELETE FROM mzbq_catalog.quality.duplicate_records
WHERE batch_id = 'bronze_quality_001';

-- 7A: whole-row duplicates ------------------------------------------
INSERT INTO mzbq_catalog.quality.duplicate_records
SELECT 'bronze_quality_001','bank_accounts',banco_id,'WHOLE_ROW',
       duplicate_key,COUNT(*),MIN(_source_file),current_timestamp()
FROM (SELECT banco_id,_source_file,
             sha2(to_json(struct(* EXCEPT(_source_file,_ingested_at))),256) AS duplicate_key
      FROM mzbq_catalog.bronze.mapa_5a_contas_bancarias) x
GROUP BY banco_id,duplicate_key HAVING COUNT(*) > 1;

INSERT INTO mzbq_catalog.quality.duplicate_records
SELECT 'bronze_quality_001','pos_list',banco_id,'WHOLE_ROW',
       duplicate_key,COUNT(*),MIN(_source_file),current_timestamp()
FROM (SELECT banco_id,_source_file,
             sha2(to_json(struct(* EXCEPT(_source_file,_ingested_at))),256) AS duplicate_key
      FROM mzbq_catalog.bronze.mapa_4a_listagem_pos) x
GROUP BY banco_id,duplicate_key HAVING COUNT(*) > 1;

INSERT INTO mzbq_catalog.quality.duplicate_records
SELECT 'bronze_quality_001','pos_transactions',banco_id,'WHOLE_ROW',
       duplicate_key,COUNT(*),MIN(_source_file),current_timestamp()
FROM (SELECT banco_id,_source_file,
             sha2(to_json(struct(* EXCEPT(_source_file,_ingested_at))),256) AS duplicate_key
      FROM mzbq_catalog.bronze.mapa_4b_transacoes_pos) x
GROUP BY banco_id,duplicate_key HAVING COUNT(*) > 1;

INSERT INTO mzbq_catalog.quality.duplicate_records
SELECT 'bronze_quality_001','branch_transactions',banco_id,'WHOLE_ROW',
       duplicate_key,COUNT(*),MIN(_source_file),current_timestamp()
FROM (SELECT banco_id,_source_file,
             sha2(to_json(struct(* EXCEPT(_source_file,_ingested_at))),256) AS duplicate_key
      FROM mzbq_catalog.bronze.mapa_1c_transacoes_balcao) x
GROUP BY banco_id,duplicate_key HAVING COUNT(*) > 1;

INSERT INTO mzbq_catalog.quality.duplicate_records
SELECT 'bronze_quality_001','credit_master_data',banco_id,'WHOLE_ROW',
       duplicate_key,COUNT(*),MIN(_source_file),current_timestamp()
FROM (SELECT banco_id,_source_file,
             sha2(to_json(struct(* EXCEPT(_source_file,_ingested_at))),256) AS duplicate_key
      FROM mzbq_catalog.bronze.quadro_1_dados_mestres_credito) x
GROUP BY banco_id,duplicate_key HAVING COUNT(*) > 1;

INSERT INTO mzbq_catalog.quality.duplicate_records
SELECT 'bronze_quality_001','credit_operations',banco_id,'WHOLE_ROW',
       duplicate_key,COUNT(*),MIN(_source_file),current_timestamp()
FROM (SELECT banco_id,_source_file,
             sha2(to_json(struct(* EXCEPT(_source_file,_ingested_at))),256) AS duplicate_key
      FROM mzbq_catalog.bronze.quadro_2_operacoes_credito) x
GROUP BY banco_id,duplicate_key HAVING COUNT(*) > 1;

INSERT INTO mzbq_catalog.quality.duplicate_records
SELECT 'bronze_quality_001','deposits',banco_id,'WHOLE_ROW',
       duplicate_key,COUNT(*),MIN(_source_file),current_timestamp()
FROM (SELECT banco_id,_source_file,
             sha2(to_json(struct(* EXCEPT(_source_file,_ingested_at))),256) AS duplicate_key
      FROM mzbq_catalog.bronze.quadro_9_depositos) x
GROUP BY banco_id,duplicate_key HAVING COUNT(*) > 1;

-- 7B: business-key duplicates (bank accounts) ------------------------
INSERT INTO mzbq_catalog.quality.duplicate_records
SELECT 'bronze_quality_001','bank_accounts',banco_id,'BUSINESS_KEY_IBAN',
       CAST(iban AS STRING),COUNT(*),MIN(_source_file),current_timestamp()
FROM mzbq_catalog.bronze.mapa_5a_contas_bancarias
WHERE iban IS NOT NULL AND TRIM(CAST(iban AS STRING)) <> ''
GROUP BY banco_id,iban HAVING COUNT(*) > 1;

INSERT INTO mzbq_catalog.quality.duplicate_records
SELECT 'bronze_quality_001','bank_accounts',banco_id,'BUSINESS_KEY_NIB',
       CAST(nib AS STRING),COUNT(*),MIN(_source_file),current_timestamp()
FROM mzbq_catalog.bronze.mapa_5a_contas_bancarias
WHERE nib IS NOT NULL AND TRIM(CAST(nib AS STRING)) <> ''
GROUP BY banco_id,nib HAVING COUNT(*) > 1;

-- ============================================================
-- STEP 8: Reference-data failed records
-- Batch: bronze_reference_quality_001
-- ============================================================

DELETE FROM mzbq_catalog.quality.failed_records
WHERE batch_id = 'bronze_reference_quality_001';

INSERT INTO mzbq_catalog.quality.failed_records
SELECT 'bronze_reference_quality_001','REFBANK001','Reference bank ID must not be empty','COMPLETENESS',
       'ref_bancos','REFERENCE','CRITICAL',
       COALESCE(CAST(banco_id AS STRING),'UNKNOWN'),'banco_id',CAST(banco_id AS STRING),
       'Bank ID must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_bancos
WHERE banco_id IS NULL OR TRIM(CAST(banco_id AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','REFBANK002','Reference bank name must not be empty','COMPLETENESS',
       'ref_bancos','REFERENCE','HIGH',
       COALESCE(CAST(banco_id AS STRING),'UNKNOWN'),'nome_banco',CAST(nome_banco AS STRING),
       'Bank name must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_bancos
WHERE nome_banco IS NULL OR TRIM(CAST(nome_banco AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','CAE001','CAE code must not be empty','COMPLETENESS',
       'ref_cae','REFERENCE','CRITICAL',
       COALESCE(CAST(codigo_cae AS STRING),'UNKNOWN'),'codigo_cae',CAST(codigo_cae AS STRING),
       'CAE code must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_cae
WHERE codigo_cae IS NULL OR TRIM(CAST(codigo_cae AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','CAE002','CAE description must not be empty','COMPLETENESS',
       'ref_cae','REFERENCE','HIGH',
       COALESCE(CAST(codigo_cae AS STRING),'UNKNOWN'),'descricao',CAST(descricao AS STRING),
       'CAE description must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_cae
WHERE descricao IS NULL OR TRIM(CAST(descricao AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','MCC001','MCC code must not be empty','COMPLETENESS',
       'ref_mcc','REFERENCE','CRITICAL',
       COALESCE(CAST(mcc AS STRING),'UNKNOWN'),'mcc',CAST(mcc AS STRING),
       'MCC code must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_mcc
WHERE mcc IS NULL OR TRIM(CAST(mcc AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','MCC002','MCC description must not be empty','COMPLETENESS',
       'ref_mcc','REFERENCE','HIGH',
       COALESCE(CAST(mcc AS STRING),'UNKNOWN'),'descricao',CAST(descricao AS STRING),
       'MCC description must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_mcc
WHERE descricao IS NULL OR TRIM(CAST(descricao AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','MCC003','MCC base average ticket must not be negative','VALIDITY',
       'ref_mcc','REFERENCE','HIGH',
       COALESCE(CAST(mcc AS STRING),'UNKNOWN'),'ticket_medio_base',CAST(ticket_medio_base AS STRING),
       'MCC base average ticket must be greater than or equal to zero',
       _source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_mcc
WHERE TRIM(CAST(ticket_medio_base AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(ticket_medio_base AS STRING), ',', '.') AS DOUBLE) < 0
UNION ALL
SELECT 'bronze_reference_quality_001','DIST001','District code must not be empty','COMPLETENESS',
       'ref_distritos','REFERENCE','CRITICAL',
       COALESCE(CAST(cod_distrito AS STRING),'UNKNOWN'),'cod_distrito',CAST(cod_distrito AS STRING),
       'District code must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_distritos
WHERE cod_distrito IS NULL OR TRIM(CAST(cod_distrito AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','DIST002','District name must not be empty','COMPLETENESS',
       'ref_distritos','REFERENCE','HIGH',
       COALESCE(CAST(cod_distrito AS STRING),'UNKNOWN'),'distrito',CAST(distrito AS STRING),
       'District name must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_distritos
WHERE distrito IS NULL OR TRIM(CAST(distrito AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','DIST003','Province must not be empty','COMPLETENESS',
       'ref_distritos','REFERENCE','HIGH',
       COALESCE(CAST(cod_distrito AS STRING),'UNKNOWN'),'provincia',CAST(provincia AS STRING),
       'Province must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_distritos
WHERE provincia IS NULL OR TRIM(CAST(provincia AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','DIST004','Administrative post code must not be empty','COMPLETENESS',
       'ref_distritos','REFERENCE','MEDIUM',
       COALESCE(CAST(cod_distrito AS STRING),'UNKNOWN'),'cod_posto',CAST(cod_posto AS STRING),
       'Administrative post code must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_distritos
WHERE cod_posto IS NULL OR TRIM(CAST(cod_posto AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','ANOM001','Expected anomaly bank ID must not be empty','COMPLETENESS',
       'ref_anomalias_esperadas',
       COALESCE(NULLIF(TRIM(CAST(banco_id AS STRING)),''),'UNKNOWN_BANK'),'CRITICAL',
       COALESCE(CAST(id_registo AS STRING),'UNKNOWN'),'banco_id',CAST(banco_id AS STRING),
       'Expected anomaly bank ID must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_anomalias_esperadas
WHERE banco_id IS NULL OR TRIM(CAST(banco_id AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','ANOM002','Expected anomaly type must not be empty','COMPLETENESS',
       'ref_anomalias_esperadas',
       COALESCE(NULLIF(TRIM(CAST(banco_id AS STRING)),''),'UNKNOWN_BANK'),'CRITICAL',
       COALESCE(CAST(id_registo AS STRING),'UNKNOWN'),'tipo_anomalia',CAST(tipo_anomalia AS STRING),
       'Expected anomaly type must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_anomalias_esperadas
WHERE tipo_anomalia IS NULL OR TRIM(CAST(tipo_anomalia AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','ANOM003','Expected anomaly record ID must not be empty','COMPLETENESS',
       'ref_anomalias_esperadas',
       COALESCE(NULLIF(TRIM(CAST(banco_id AS STRING)),''),'UNKNOWN_BANK'),'HIGH',
       COALESCE(CAST(id_registo AS STRING),'UNKNOWN'),'id_registo',CAST(id_registo AS STRING),
       'Expected anomaly record ID must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_anomalias_esperadas
WHERE id_registo IS NULL OR TRIM(CAST(id_registo AS STRING)) = ''
UNION ALL
SELECT 'bronze_reference_quality_001','ANOM004','Expected anomaly description must not be empty','COMPLETENESS',
       'ref_anomalias_esperadas',
       COALESCE(NULLIF(TRIM(CAST(banco_id AS STRING)),''),'UNKNOWN_BANK'),'MEDIUM',
       COALESCE(CAST(id_registo AS STRING),'UNKNOWN'),'descricao',CAST(descricao AS STRING),
       'Expected anomaly description must not be null or empty',_source_file,_ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.ref_anomalias_esperadas
WHERE descricao IS NULL OR TRIM(CAST(descricao AS STRING)) = ''
-- exchange_rates uses source_file / ingested_at (no underscore prefix)
UNION ALL
SELECT 'bronze_reference_quality_001','EXR001','USD exchange rate must be greater than zero','VALIDITY',
       'exchange_rates','REFERENCE','CRITICAL',
       COALESCE(CAST(`Period` AS STRING),'UNKNOWN_PERIOD'),'USD',CAST(USD AS STRING),
       'USD exchange rate must be greater than zero',source_file,ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.exchange_rates
WHERE USD IS NULL OR TRIM(CAST(USD AS STRING)) = ''
   OR TRIM(CAST(USD AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(USD AS STRING), ',', '.') AS DOUBLE) <= 0
UNION ALL
SELECT 'bronze_reference_quality_001','EXR002','EUR exchange rate must be greater than zero','VALIDITY',
       'exchange_rates','REFERENCE','CRITICAL',
       COALESCE(CAST(`Period` AS STRING),'UNKNOWN_PERIOD'),'EUR',CAST(EUR AS STRING),
       'EUR exchange rate must be greater than zero',source_file,ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.exchange_rates
WHERE EUR IS NULL OR TRIM(CAST(EUR AS STRING)) = ''
   OR TRIM(CAST(EUR AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(EUR AS STRING), ',', '.') AS DOUBLE) <= 0
UNION ALL
SELECT 'bronze_reference_quality_001','EXR003','ZAR exchange rate must be greater than zero','VALIDITY',
       'exchange_rates','REFERENCE','CRITICAL',
       COALESCE(CAST(`Period` AS STRING),'UNKNOWN_PERIOD'),'ZAR',CAST(ZAR AS STRING),
       'ZAR exchange rate must be greater than zero',source_file,ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.exchange_rates
WHERE ZAR IS NULL OR TRIM(CAST(ZAR AS STRING)) = ''
   OR TRIM(CAST(ZAR AS STRING)) LIKE '-%'
   OR TRY_CAST(REPLACE(CAST(ZAR AS STRING), ',', '.') AS DOUBLE) <= 0
UNION ALL
SELECT 'bronze_reference_quality_001','EXR004','Exchange-rate period must not be empty','COMPLETENESS',
       'exchange_rates','REFERENCE','CRITICAL',
       COALESCE(CAST(`Period` AS STRING),'UNKNOWN_PERIOD'),'Period',CAST(`Period` AS STRING),
       'Exchange-rate period must not be null or empty',source_file,ingested_at,current_timestamp()
FROM mzbq_catalog.bronze.exchange_rates
WHERE `Period` IS NULL OR TRIM(CAST(`Period` AS STRING)) = '';

-- ============================================================
-- STEP 9: Rule results from failed-record evidence
-- One generic pattern for both batches:
-- rule_catalog x dataset totals LEFT JOIN failed counts.
-- ============================================================

-- 9A: LIN001 + business rules (bank datasets)
DELETE FROM mzbq_catalog.quality.rule_results
WHERE batch_id = 'bronze_quality_001' AND rule_id <> 'ROW001';

INSERT INTO mzbq_catalog.quality.rule_results
SELECT
  'bronze_quality_001',
  rc.rule_id, rc.rule_name, rc.rule_type,
  dt.dataset, dt.banco_id, rc.severity,
  dt.total_records,
  dt.total_records - COALESCE(fr.failed_records, 0),
  COALESCE(fr.failed_records, 0),
  ROUND(CASE WHEN dt.total_records = 0 THEN 0
             ELSE (dt.total_records - COALESCE(fr.failed_records, 0)) * 100.0 / dt.total_records
        END, 2),
  current_timestamp()
FROM mzbq_catalog.quality.rule_catalog rc
JOIN mzbq_catalog.quality.vw_bronze_dataset_totals dt
  ON rc.dataset = dt.dataset OR (rc.rule_id = 'LIN001' AND rc.dataset = 'ALL')
LEFT JOIN (
  SELECT rule_id, dataset, banco_id, COUNT(*) AS failed_records
  FROM mzbq_catalog.quality.failed_records
  WHERE batch_id = 'bronze_quality_001'
  GROUP BY rule_id, dataset, banco_id
) fr
  ON rc.rule_id = fr.rule_id AND dt.dataset = fr.dataset AND dt.banco_id = fr.banco_id
WHERE rc.rule_id NOT IN ('ROW001', 'DUP001')
  AND rc.dataset IN ('ALL',
    'bank_accounts','pos_list','pos_transactions','branch_transactions',
    'credit_master_data','credit_operations','deposits');

-- 9B: DUP001 from duplicate_records
INSERT INTO mzbq_catalog.quality.rule_results
SELECT
  'bronze_quality_001','DUP001','Whole-row duplicate records detected','DUPLICATE',
  dt.dataset, dt.banco_id, 'HIGH',
  dt.total_records,
  dt.total_records - COALESCE(d.records_in_duplicate_groups, 0),
  COALESCE(d.records_in_duplicate_groups, 0),
  ROUND(CASE WHEN dt.total_records = 0 THEN 0
             ELSE (dt.total_records - COALESCE(d.records_in_duplicate_groups, 0)) * 100.0 / dt.total_records
        END, 2),
  current_timestamp()
FROM mzbq_catalog.quality.vw_bronze_dataset_totals dt
LEFT JOIN (
  SELECT dataset, banco_id, SUM(duplicate_count) AS records_in_duplicate_groups
  FROM mzbq_catalog.quality.duplicate_records
  WHERE batch_id = 'bronze_quality_001' AND duplicate_type = 'WHOLE_ROW'
  GROUP BY dataset, banco_id
) d
  ON dt.dataset = d.dataset AND dt.banco_id = d.banco_id;

-- 9C: reference rules
DELETE FROM mzbq_catalog.quality.rule_results
WHERE batch_id = 'bronze_reference_quality_001';

INSERT INTO mzbq_catalog.quality.rule_results
SELECT
  'bronze_reference_quality_001',
  rc.rule_id, rc.rule_name, rc.rule_type,
  dt.dataset, dt.banco_id, rc.severity,
  dt.total_records,
  dt.total_records - COALESCE(fr.failed_records, 0),
  COALESCE(fr.failed_records, 0),
  ROUND(CASE WHEN dt.total_records = 0 THEN 0
             ELSE (dt.total_records - COALESCE(fr.failed_records, 0)) * 100.0 / dt.total_records
        END, 2),
  current_timestamp()
FROM mzbq_catalog.quality.rule_catalog rc
JOIN mzbq_catalog.quality.vw_bronze_reference_dataset_totals dt
  ON rc.dataset = dt.dataset
LEFT JOIN (
  SELECT rule_id, dataset, banco_id, COUNT(*) AS failed_records
  FROM mzbq_catalog.quality.failed_records
  WHERE batch_id = 'bronze_reference_quality_001'
  GROUP BY rule_id, dataset, banco_id
) fr
  ON rc.rule_id = fr.rule_id AND dt.dataset = fr.dataset AND dt.banco_id = fr.banco_id;

-- ============================================================
-- STEP 10: Summary (both batches, one statement)
-- ============================================================

DELETE FROM mzbq_catalog.quality.summary
WHERE batch_id IN ('bronze_quality_001','bronze_reference_quality_001');

INSERT INTO mzbq_catalog.quality.summary
SELECT
  rr.batch_id, rr.dataset, rr.banco_id,
  MAX(rr.total_records),
  SUM(rr.failed_records),
  COALESCE(MAX(dup.duplicate_groups), 0),
  SUM(CASE WHEN rr.severity = 'CRITICAL' THEN rr.failed_records ELSE 0 END),
  SUM(CASE WHEN rr.severity = 'HIGH'     THEN rr.failed_records ELSE 0 END),
  SUM(CASE WHEN rr.severity = 'MEDIUM'   THEN rr.failed_records ELSE 0 END),
  ROUND(AVG(rr.pass_rate), 2),
  current_timestamp()
FROM mzbq_catalog.quality.rule_results rr
LEFT JOIN (
  SELECT batch_id, dataset, banco_id, COUNT(*) AS duplicate_groups
  FROM mzbq_catalog.quality.duplicate_records
  GROUP BY batch_id, dataset, banco_id
) dup
  ON rr.batch_id = dup.batch_id AND rr.dataset = dup.dataset AND rr.banco_id = dup.banco_id
WHERE rr.batch_id IN ('bronze_quality_001','bronze_reference_quality_001')
GROUP BY rr.batch_id, rr.dataset, rr.banco_id;

-- ============================================================
-- STEP 11: Scorecard (both batches)
-- ============================================================

DELETE FROM mzbq_catalog.quality.scorecard
WHERE batch_id IN ('bronze_quality_001','bronze_reference_quality_001');

INSERT INTO mzbq_catalog.quality.scorecard
SELECT
  batch_id, banco_id, dataset,
  COUNT(*),
  SUM(CASE WHEN failed_records > 0 THEN 1 ELSE 0 END),
  MAX(total_records),                 -- records in dataset, not summed over rules
  SUM(failed_records),
  ROUND(AVG(pass_rate), 2),
  current_timestamp()
FROM mzbq_catalog.quality.rule_results
WHERE batch_id IN ('bronze_quality_001','bronze_reference_quality_001')
GROUP BY batch_id, banco_id, dataset;

-- ============================================================
-- STEP 12: Pipeline run log (AFTER summary is populated)
-- ============================================================

DELETE FROM mzbq_catalog.quality.pipeline_runs
WHERE batch_id IN ('bronze_quality_001','bronze_reference_quality_001');

INSERT INTO mzbq_catalog.quality.pipeline_runs
SELECT
  batch_id,
  'BRONZE',
  CASE batch_id
    WHEN 'bronze_quality_001'
      THEN 'Independent supervisory data-quality assessment of raw bank submissions'
    ELSE 'Data-quality assessment of Bronze reference tables'
  END,
  'SUCCESS',
  COUNT(DISTINCT dataset),
  COUNT(DISTINCT banco_id),
  SUM(total_records),
  SUM(total_failed_records),
  SUM(duplicate_groups),
  current_timestamp(),
  current_timestamp(),
  'Assessment performed before Silver cleaning or transformation. Bronze records were not modified.'
FROM mzbq_catalog.quality.summary
WHERE batch_id IN ('bronze_quality_001','bronze_reference_quality_001')
GROUP BY batch_id;

-- ============================================================
-- STEP 13: Reporting views
-- ============================================================

CREATE OR REPLACE VIEW mzbq_catalog.quality.vw_quality_executive_summary AS
SELECT
  batch_id,
  COUNT(DISTINCT dataset)   AS datasets_checked,
  COUNT(DISTINCT banco_id)  AS banks_checked,
  SUM(total_records)        AS total_records,
  SUM(total_failed_records) AS total_failed_records,
  SUM(duplicate_groups)     AS duplicate_groups,
  SUM(critical_failures)    AS critical_failures,
  SUM(high_failures)        AS high_failures,
  SUM(medium_failures)      AS medium_failures,
  ROUND(AVG(quality_score), 2) AS average_quality_score
FROM mzbq_catalog.quality.summary
GROUP BY batch_id;

CREATE OR REPLACE VIEW mzbq_catalog.quality.vw_scorecard_by_bank AS
SELECT
  batch_id, banco_id,
  COUNT(DISTINCT dataset)      AS datasets_checked,
  ROUND(AVG(overall_score), 2) AS overall_score,
  SUM(total_failed_records)    AS total_failed_records,
  SUM(rules_with_failures)     AS rules_with_failures,
  SUM(total_records_checked)   AS total_records_checked
FROM mzbq_catalog.quality.scorecard
GROUP BY batch_id, banco_id;

CREATE OR REPLACE VIEW mzbq_catalog.quality.vw_rule_performance AS
SELECT
  batch_id, rule_id, rule_name, rule_type, dataset, severity,
  SUM(total_records)  AS total_records,
  SUM(passed_records) AS passed_records,
  SUM(failed_records) AS failed_records,
  ROUND(AVG(pass_rate), 2) AS average_pass_rate
FROM mzbq_catalog.quality.rule_results
GROUP BY batch_id, rule_id, rule_name, rule_type, dataset, severity;

CREATE OR REPLACE VIEW mzbq_catalog.quality.vw_failed_records_report AS
SELECT * FROM mzbq_catalog.quality.failed_records;

CREATE OR REPLACE VIEW mzbq_catalog.quality.vw_duplicate_report AS
SELECT * FROM mzbq_catalog.quality.duplicate_records;

-- ============================================================
-- STEP 14: Report queries
-- ============================================================

-- 14.1 Executive summary (both batches side by side)
SELECT * FROM mzbq_catalog.quality.vw_quality_executive_summary
ORDER BY batch_id;

-- 14.2 Scorecard by bank (worst first)
SELECT * FROM mzbq_catalog.quality.vw_scorecard_by_bank
WHERE batch_id = 'bronze_quality_001'
ORDER BY overall_score ASC, total_failed_records DESC;

-- 14.3 Rules that actually failed
SELECT rule_id, rule_name, rule_type, dataset, severity,
       failed_records, average_pass_rate
FROM mzbq_catalog.quality.vw_rule_performance
WHERE failed_records > 0
ORDER BY batch_id, failed_records DESC, average_pass_rate ASC;

-- 14.4 Failed rules by bank
SELECT banco_id, dataset, rule_id, rule_name, failed_records, pass_rate
FROM mzbq_catalog.quality.rule_results
WHERE batch_id = 'bronze_quality_001' AND failed_records > 0
ORDER BY banco_id, dataset, rule_id;

-- 14.5 Failed-record evidence sample
SELECT * FROM mzbq_catalog.quality.vw_failed_records_report
ORDER BY severity, dataset, rule_id, banco_id
LIMIT 100;

-- 14.6 Duplicate groups (largest first)
SELECT * FROM mzbq_catalog.quality.vw_duplicate_report
ORDER BY duplicate_count DESC;

-- 14.7 Missing submissions (ROW001 failures = bank sent nothing)
SELECT banco_id, dataset
FROM mzbq_catalog.quality.rule_results
WHERE batch_id = 'bronze_quality_001'
  AND rule_id = 'ROW001' AND failed_records > 0
ORDER BY banco_id, dataset;

-- 14.8 Pipeline run log
SELECT * FROM mzbq_catalog.quality.pipeline_runs
ORDER BY batch_id;
