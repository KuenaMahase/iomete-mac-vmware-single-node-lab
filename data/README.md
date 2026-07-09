# PoC Data

Synthetic Banco de Moçambique supervisory banking data for the IOMETE PoC.

- `poc_bm_dados_sinteticos_csv/` — the dataset in its original delivery
  layout, which is also the layout `01_ingest_banking_data.py` reads
  (`DATA_ROOT/{bank_id}/{bank_id}_{dataset}.csv`):
  - `BCO01/` … `BCO10/` — 7 submission files per bank (mapa_1c, mapa_4a,
    mapa_4b, mapa_5a, quadro_1, quadro_2, quadro_9)
  - reference CSVs at the folder root (banks, MCC, districts, CAE,
    interest-rate ranges, file manifest, seeded-anomaly answer key)
  - `README_PoC_dados_sinteticos.txt` — original dataset notes
  - `referencias_originais/` — original CAE and INE census source workbooks
- `Exchange_rates_csv.sql` — daily MZN exchange-rate series 2024-01-02 →
  2026-06-19 (semicolon-delimited CSV despite the extension)

Files are semicolon-delimited, UTF-8, with Portuguese-locale numerics
(`1.234,56`) and dd-MM-yyyy dates.

See `docs/banking-data-profile-report.md` for the full inventory and profile,
and `docs/Credito_e_Deposito_para_o_PoC_BM.pdf` for the regulatory circular
defining every field.
