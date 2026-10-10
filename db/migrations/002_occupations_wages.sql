-- FuturePath 002: occupations (SOC 2018), wages (BLS OEWS), profiles (BLS EP), CIP taxonomy and CIP-SOC crosswalk

CREATE TABLE IF NOT EXISTS occupations (
    soc_code VARCHAR(7) NOT NULL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT NULL,
    occupation_group VARCHAR(12) NOT NULL DEFAULT 'detailed',
    education_category VARCHAR(80) NULL,
    source_year SMALLINT NULL,
    active_flag TINYINT(1) NOT NULL DEFAULT 1,
    KEY ix_occupations_title (title),
    KEY ix_occupations_group (occupation_group),
    CONSTRAINT ck_occupations_soc CHECK (soc_code REGEXP '^[0-9]{2}-[0-9]{4}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per SOC + area + reference year. NULL = not published (see suppression_code); never 0.
CREATE TABLE IF NOT EXISTS occupational_wages (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    soc_code VARCHAR(7) NOT NULL,
    area_level VARCHAR(10) NOT NULL,
    area_code VARCHAR(10) NOT NULL,
    cbsa_code CHAR(5) NULL,
    state_fips CHAR(2) NULL,
    wage_year SMALLINT NOT NULL,
    employment_count INT UNSIGNED NULL,
    employment_prse DECIMAL(6,1) NULL,
    hourly_mean DECIMAL(8,2) NULL,
    annual_mean DECIMAL(12,2) NULL,
    mean_prse DECIMAL(6,1) NULL,
    hourly_median DECIMAL(8,2) NULL,
    annual_median DECIMAL(12,2) NULL,
    annual_p10 DECIMAL(12,2) NULL,
    annual_p25 DECIMAL(12,2) NULL,
    annual_p75 DECIMAL(12,2) NULL,
    annual_p90 DECIMAL(12,2) NULL,
    annual_only TINYINT(1) NOT NULL DEFAULT 0,
    hourly_only TINYINT(1) NOT NULL DEFAULT 0,
    suppression_code VARCHAR(255) NULL,
    topcoded_fields VARCHAR(120) NULL,
    source_id INT UNSIGNED NOT NULL,
    import_run_id BIGINT UNSIGNED NULL,
    imported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_wages (soc_code, area_level, area_code, wage_year),
    KEY ix_wages_metro (cbsa_code, wage_year),
    CONSTRAINT fk_wages_occupation FOREIGN KEY (soc_code) REFERENCES occupations (soc_code),
    CONSTRAINT fk_wages_metro FOREIGN KEY (cbsa_code) REFERENCES metro_areas (cbsa_code),
    CONSTRAINT fk_wages_source FOREIGN KEY (source_id) REFERENCES data_sources (id),
    CONSTRAINT ck_wages_level CHECK (area_level IN ('national','state','metro'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS occupation_profiles (
    soc_code VARCHAR(7) NOT NULL PRIMARY KEY,
    tasks_summary TEXT NULL,
    education_notes VARCHAR(500) NULL,
    typical_entry_education VARCHAR(80) NULL,
    work_experience VARCHAR(80) NULL,
    ojt_training VARCHAR(120) NULL,
    employment_base_thousands DECIMAL(10,1) NULL,
    employment_projected_thousands DECIMAL(10,1) NULL,
    outlook_percent DECIMAL(6,1) NULL,
    annual_openings_thousands DECIMAL(10,1) NULL,
    outlook_period VARCHAR(20) NULL,
    outlook_year SMALLINT NULL,
    source_id INT UNSIGNED NOT NULL,
    source_url VARCHAR(500) NULL,
    CONSTRAINT fk_profiles_occupation FOREIGN KEY (soc_code) REFERENCES occupations (soc_code),
    CONSTRAINT fk_profiles_source FOREIGN KEY (source_id) REFERENCES data_sources (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- CIP codes keep their dotted text form exactly ("23.0101", "23.01", "23").
CREATE TABLE IF NOT EXISTS cip_programs (
    cip_code VARCHAR(10) NOT NULL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT NULL,
    cip_level TINYINT NOT NULL,
    taxonomy_year SMALLINT NOT NULL,
    KEY ix_cip_title (title),
    CONSTRAINT ck_cip_format CHECK (cip_code REGEXP '^[0-9]{2}(\\.[0-9]{2}([0-9]{2})?)?$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Official NCES CIP 2020 -> SOC 2018 crosswalk. Many-to-many. NOT graduate placement outcomes.
CREATE TABLE IF NOT EXISTS cip_soc_crosswalk (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    cip_code VARCHAR(10) NOT NULL,
    soc_code VARCHAR(7) NOT NULL,
    soc_title VARCHAR(255) NULL,
    crosswalk_year SMALLINT NOT NULL,
    source_id INT UNSIGNED NOT NULL,
    UNIQUE KEY uq_cip_soc (cip_code, soc_code, crosswalk_year),
    KEY ix_cip_soc_soc (soc_code),
    CONSTRAINT fk_cip_soc_cip FOREIGN KEY (cip_code) REFERENCES cip_programs (cip_code),
    CONSTRAINT fk_cip_soc_source FOREIGN KEY (source_id) REFERENCES data_sources (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
