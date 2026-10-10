-- FuturePath 001: data provenance and geography reference tables

CREATE TABLE IF NOT EXISTS data_sources (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    source_key VARCHAR(60) NOT NULL,
    name VARCHAR(200) NOT NULL,
    agency VARCHAR(200) NOT NULL,
    source_url VARCHAR(500) NOT NULL,
    license_notes TEXT NULL,
    refresh_cadence VARCHAR(100) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_data_sources_key (source_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS data_import_runs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    source_id INT UNSIGNED NOT NULL,
    dataset_key VARCHAR(60) NOT NULL,
    vintage_year SMALLINT NULL,
    vintage_label VARCHAR(80) NULL,
    file_name VARCHAR(255) NULL,
    source_url VARCHAR(500) NULL,
    started_at DATETIME NOT NULL,
    ended_at DATETIME NULL,
    result_status VARCHAR(20) NOT NULL DEFAULT 'running',
    rows_seen INT UNSIGNED NOT NULL DEFAULT 0,
    rows_inserted INT UNSIGNED NOT NULL DEFAULT 0,
    rows_updated INT UNSIGNED NOT NULL DEFAULT 0,
    rows_skipped INT UNSIGNED NOT NULL DEFAULT 0,
    progress_note VARCHAR(255) NULL,
    warnings TEXT NULL,
    error_summary TEXT NULL,
    checksum CHAR(64) NULL,
    triggered_by VARCHAR(120) NULL,
    KEY ix_import_runs_dataset (dataset_key, started_at),
    CONSTRAINT fk_import_runs_source FOREIGN KEY (source_id) REFERENCES data_sources (id),
    CONSTRAINT ck_import_runs_status CHECK (result_status IN ('running','success','partial','failed'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS states (
    state_fips CHAR(2) NOT NULL PRIMARY KEY,
    state_code CHAR(2) NOT NULL,
    name VARCHAR(80) NOT NULL,
    UNIQUE KEY uq_states_code (state_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS metro_areas (
    cbsa_code CHAR(5) NOT NULL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    geographic_type VARCHAR(20) NOT NULL DEFAULT 'MSA',
    primary_state_code CHAR(2) NULL,
    source_year SMALLINT NULL,
    active_flag TINYINT(1) NOT NULL DEFAULT 1,
    KEY ix_metro_areas_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS metro_state_map (
    cbsa_code CHAR(5) NOT NULL,
    state_fips CHAR(2) NOT NULL,
    PRIMARY KEY (cbsa_code, state_fips),
    CONSTRAINT fk_metro_state_metro FOREIGN KEY (cbsa_code) REFERENCES metro_areas (cbsa_code) ON DELETE CASCADE,
    CONSTRAINT fk_metro_state_state FOREIGN KEY (state_fips) REFERENCES states (state_fips)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Explicit links between external geographies (HUD FMR areas, ACS GEO_IDs, ...) and CBSAs.
-- mapping_quality: exact | partial (external area covers part of the CBSA) | none (no valid CBSA)
CREATE TABLE IF NOT EXISTS geo_source_mappings (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    geo_system VARCHAR(30) NOT NULL,
    external_geo_code VARCHAR(40) NOT NULL,
    external_name VARCHAR(255) NULL,
    cbsa_code CHAR(5) NULL,
    mapping_quality VARCHAR(20) NOT NULL,
    population INT UNSIGNED NULL,
    notes VARCHAR(500) NULL,
    UNIQUE KEY uq_geo_map (geo_system, external_geo_code),
    KEY ix_geo_map_cbsa (cbsa_code),
    CONSTRAINT fk_geo_map_metro FOREIGN KEY (cbsa_code) REFERENCES metro_areas (cbsa_code) ON DELETE SET NULL,
    CONSTRAINT ck_geo_map_quality CHECK (mapping_quality IN ('exact','partial','none'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
