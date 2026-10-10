-- FuturePath 004: housing and living-cost observations, versioned tax rules, loan assumptions

-- bedroom_key: '0','1','2','3','4','5+' or 'all'
CREATE TABLE IF NOT EXISTS rent_observations (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    geo_system VARCHAR(30) NOT NULL,
    geo_code VARCHAR(40) NOT NULL,
    geo_name VARCHAR(255) NULL,
    cbsa_code CHAR(5) NULL,
    bedroom_key VARCHAR(4) NOT NULL,
    monthly_rent DECIMAL(10,2) NULL,
    margin_of_error DECIMAL(10,2) NULL,
    year SMALLINT NOT NULL,
    period_label VARCHAR(40) NOT NULL,
    measurement_type VARCHAR(40) NOT NULL,
    source_id INT UNSIGNED NOT NULL,
    import_run_id BIGINT UNSIGNED NULL,
    UNIQUE KEY uq_rent_obs (geo_system, geo_code, bedroom_key, year, measurement_type),
    KEY ix_rent_obs_cbsa (cbsa_code, measurement_type, year),
    CONSTRAINT fk_rent_obs_source FOREIGN KEY (source_id) REFERENCES data_sources (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS housing_price_observations (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    geo_system VARCHAR(30) NOT NULL,
    geo_code VARCHAR(40) NOT NULL,
    geo_name VARCHAR(255) NULL,
    cbsa_code CHAR(5) NULL,
    value DECIMAL(14,2) NULL,
    margin_of_error DECIMAL(14,2) NULL,
    year SMALLINT NOT NULL,
    period_label VARCHAR(40) NOT NULL,
    metric_type VARCHAR(40) NOT NULL,
    source_id INT UNSIGNED NOT NULL,
    import_run_id BIGINT UNSIGNED NULL,
    UNIQUE KEY uq_house_obs (geo_system, geo_code, year, metric_type),
    KEY ix_house_obs_cbsa (cbsa_code, metric_type, year),
    CONSTRAINT fk_house_obs_source FOREIGN KEY (source_id) REFERENCES data_sources (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS regional_cost_observations (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    geo_system VARCHAR(30) NOT NULL,
    geo_code VARCHAR(40) NOT NULL,
    category VARCHAR(80) NOT NULL,
    period_year SMALLINT NOT NULL,
    period_label VARCHAR(40) NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    unit VARCHAR(40) NOT NULL,
    household_profile_json VARCHAR(500) NULL,
    source_id INT UNSIGNED NOT NULL,
    confidence_notes VARCHAR(500) NULL,
    UNIQUE KEY uq_regional_cost (geo_system, geo_code, category, period_label),
    CONSTRAINT fk_regional_cost_source FOREIGN KEY (source_id) REFERENCES data_sources (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- jurisdiction_code: US (federal), state postal code, or a locality key such as NYC.
-- rule_type: bracket | standard_deduction | payroll | credit | none
CREATE TABLE IF NOT EXISTS tax_rules (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    jurisdiction_code VARCHAR(12) NOT NULL,
    tax_year SMALLINT NOT NULL,
    filing_status VARCHAR(10) NOT NULL,
    rule_type VARCHAR(30) NOT NULL,
    lower_bound DECIMAL(14,2) NOT NULL DEFAULT 0,
    upper_bound DECIMAL(14,2) NULL,
    rate DECIMAL(8,5) NOT NULL DEFAULT 0,
    fixed_amount DECIMAL(14,2) NULL,
    parameters_json VARCHAR(1000) NULL,
    source_id INT UNSIGNED NOT NULL,
    source_url VARCHAR(500) NULL,
    notes VARCHAR(500) NULL,
    KEY ix_tax_rules_lookup (jurisdiction_code, tax_year, filing_status, rule_type),
    CONSTRAINT fk_tax_rules_source FOREIGN KEY (source_id) REFERENCES data_sources (id),
    CONSTRAINT ck_tax_rules_status CHECK (filing_status IN ('single','mfj','hoh','all'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS loan_assumptions (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    loan_key VARCHAR(40) NOT NULL,
    description VARCHAR(255) NOT NULL,
    annual_interest_rate DECIMAL(6,3) NOT NULL,
    duration_months SMALLINT UNSIGNED NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE NULL,
    source_id INT UNSIGNED NOT NULL,
    source_url VARCHAR(500) NULL,
    UNIQUE KEY uq_loan_assumptions (loan_key, valid_from),
    CONSTRAINT fk_loan_assumptions_source FOREIGN KEY (source_id) REFERENCES data_sources (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
