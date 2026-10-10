-- FuturePath 003: institutions (College Scorecard / IPEDS UNITID), programs, outcomes, education pathways

CREATE TABLE IF NOT EXISTS institutions (
    unitid INT UNSIGNED NOT NULL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    city VARCHAR(120) NULL,
    state_code CHAR(2) NULL,
    website_url VARCHAR(255) NULL,
    control_type VARCHAR(40) NULL,
    predominant_degree VARCHAR(40) NULL,
    student_size INT UNSIGNED NULL,
    latitude DECIMAL(9,6) NULL,
    longitude DECIMAL(9,6) NULL,
    active_flag TINYINT(1) NOT NULL DEFAULT 1,
    source_year VARCHAR(40) NULL,
    source_id INT UNSIGNED NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY ix_institutions_name (name),
    KEY ix_institutions_state (state_code, city)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Each cost concept is a separate column: tuition, cost of attendance and average net price are never summed.
CREATE TABLE IF NOT EXISTS institution_costs (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    unitid INT UNSIGNED NOT NULL,
    academic_year VARCHAR(20) NOT NULL,
    in_state_tuition DECIMAL(12,2) NULL,
    out_state_tuition DECIMAL(12,2) NULL,
    total_cost_of_attendance DECIMAL(12,2) NULL,
    average_net_price DECIMAL(12,2) NULL,
    reporting_population VARCHAR(255) NULL,
    source_id INT UNSIGNED NOT NULL,
    UNIQUE KEY uq_inst_costs (unitid, academic_year),
    CONSTRAINT fk_inst_costs_inst FOREIGN KEY (unitid) REFERENCES institutions (unitid) ON DELETE CASCADE,
    CONSTRAINT fk_inst_costs_source FOREIGN KEY (source_id) REFERENCES data_sources (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS institution_outcomes (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    unitid INT UNSIGNED NOT NULL,
    report_year VARCHAR(20) NOT NULL,
    completion_rate DECIMAL(6,4) NULL,
    retention_rate DECIMAL(6,4) NULL,
    median_debt DECIMAL(12,2) NULL,
    published_definitions_json TEXT NULL,
    source_id INT UNSIGNED NOT NULL,
    UNIQUE KEY uq_inst_outcomes (unitid, report_year),
    CONSTRAINT fk_inst_outcomes_inst FOREIGN KEY (unitid) REFERENCES institutions (unitid) ON DELETE CASCADE,
    CONSTRAINT fk_inst_outcomes_source FOREIGN KEY (source_id) REFERENCES data_sources (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS institution_programs (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    unitid INT UNSIGNED NOT NULL,
    cip_code VARCHAR(10) NOT NULL,
    credential_level_code TINYINT NOT NULL,
    credential_title VARCHAR(80) NULL,
    program_label VARCHAR(255) NOT NULL,
    reported_awards INT UNSIGNED NULL,
    reporting_year VARCHAR(20) NOT NULL,
    UNIQUE KEY uq_inst_programs (unitid, cip_code, credential_level_code, reporting_year),
    KEY ix_inst_programs_cip (cip_code),
    CONSTRAINT fk_inst_programs_inst FOREIGN KEY (unitid) REFERENCES institutions (unitid) ON DELETE CASCADE,
    CONSTRAINT fk_inst_programs_cip FOREIGN KEY (cip_code) REFERENCES cip_programs (cip_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Observed outcomes for former students of a field of study at an institution (not occupational wages).
CREATE TABLE IF NOT EXISTS program_outcomes (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    unitid INT UNSIGNED NOT NULL,
    cip_code VARCHAR(10) NOT NULL,
    credential_level_code TINYINT NOT NULL,
    report_year VARCHAR(20) NOT NULL,
    earnings_horizon VARCHAR(10) NOT NULL,
    earnings_median DECIMAL(12,2) NULL,
    earnings_measure VARCHAR(120) NULL,
    earnings_count INT UNSIGNED NULL,
    debt_median DECIMAL(12,2) NULL,
    debt_measure VARCHAR(120) NULL,
    cohort_info_json TEXT NULL,
    suppressed_flag TINYINT(1) NOT NULL DEFAULT 0,
    source_id INT UNSIGNED NOT NULL,
    UNIQUE KEY uq_program_outcomes (unitid, cip_code, credential_level_code, report_year, earnings_horizon),
    CONSTRAINT fk_program_outcomes_inst FOREIGN KEY (unitid) REFERENCES institutions (unitid) ON DELETE CASCADE,
    CONSTRAINT fk_program_outcomes_source FOREIGN KEY (source_id) REFERENCES data_sources (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS education_pathways (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    pathway_key VARCHAR(40) NOT NULL,
    name VARCHAR(120) NOT NULL,
    type VARCHAR(20) NOT NULL,
    minimum_years DECIMAL(4,1) NOT NULL,
    typical_years DECIMAL(4,1) NOT NULL,
    cost_basis VARCHAR(255) NULL,
    licensing_notes VARCHAR(500) NULL,
    description VARCHAR(500) NULL,
    source_id INT UNSIGNED NULL,
    sort_order SMALLINT NOT NULL DEFAULT 0,
    UNIQUE KEY uq_pathways_key (pathway_key),
    CONSTRAINT fk_pathways_source FOREIGN KEY (source_id) REFERENCES data_sources (id),
    CONSTRAINT ck_pathways_type CHECK (type IN ('work','ged','certificate','apprenticeship','associate','bachelor','master','doctoral','professional'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS occupation_pathways (
    soc_code VARCHAR(7) NOT NULL,
    pathway_id INT UNSIGNED NOT NULL,
    requirement_status VARCHAR(12) NOT NULL,
    source_notes VARCHAR(500) NULL,
    PRIMARY KEY (soc_code, pathway_id),
    CONSTRAINT fk_occ_path_occupation FOREIGN KEY (soc_code) REFERENCES occupations (soc_code),
    CONSTRAINT fk_occ_path_pathway FOREIGN KEY (pathway_id) REFERENCES education_pathways (id),
    CONSTRAINT ck_occ_path_status CHECK (requirement_status IN ('common','required','alternative'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
