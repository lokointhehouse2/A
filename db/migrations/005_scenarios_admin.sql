-- FuturePath 005: saved anonymous scenarios, results, admin users

-- Anonymous by default: no names, emails, ages or addresses are stored with a scenario.
CREATE TABLE IF NOT EXISTS simulation_scenarios (
    scenario_uuid CHAR(36) NOT NULL PRIMARY KEY,
    anonymous_session_id CHAR(64) NULL,
    user_id INT UNSIGNED NULL,
    title VARCHAR(120) NULL,
    selected_soc_code VARCHAR(7) NULL,
    unitid INT UNSIGNED NULL,
    cip_code VARCHAR(10) NULL,
    cbsa_code CHAR(5) NULL,
    household_json TEXT NULL,
    education_json TEXT NULL,
    income_json TEXT NULL,
    assumptions_json TEXT NULL,
    data_years_json TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY ix_scenarios_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS simulation_results (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    scenario_uuid CHAR(36) NOT NULL,
    calculation_version VARCHAR(20) NOT NULL,
    result_json MEDIUMTEXT NOT NULL,
    calculated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_results_scenario (scenario_uuid),
    CONSTRAINT fk_results_scenario FOREIGN KEY (scenario_uuid) REFERENCES simulation_scenarios (scenario_uuid) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS admin_users (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(190) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'admin',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at DATETIME NULL,
    UNIQUE KEY uq_admin_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
