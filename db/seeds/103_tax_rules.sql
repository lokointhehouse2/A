-- FuturePath seed 103: versioned, simplified tax rules.
-- Every figure below was checked against the cited official publication (see docs/DATA_SOURCES.md).
-- Brackets: tax = sum over brackets of rate * (min(income, upper) - lower). upper_bound NULL = no upper limit.

SET @irs = (SELECT id FROM data_sources WHERE source_key = 'irs_rev_proc');
SET @ssa = (SELECT id FROM data_sources WHERE source_key = 'ssa_wage_base');
SET @ny = (SELECT id FROM data_sources WHERE source_key = 'ny_dtf');
SET @dc = (SELECT id FROM data_sources WHERE source_key = 'dc_otr');
SET @va = (SELECT id FROM data_sources WHERE source_key = 'va_tax');
SET @nowage = (SELECT id FROM data_sources WHERE source_key = 'state_no_wage_tax');

-- ---------------------------------------------------------------- Federal 2026 (Rev. Proc. 2025-32)
INSERT INTO tax_rules (jurisdiction_code, tax_year, filing_status, rule_type, lower_bound, upper_bound, rate, fixed_amount, parameters_json, source_id, source_url, notes) VALUES
('US', 2026, 'single', 'standard_deduction', 0, NULL, 0, 16100, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', 'Rev. Proc. 2025-32 sec. 4.15'),
('US', 2026, 'mfj', 'standard_deduction', 0, NULL, 0, 32200, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', 'Rev. Proc. 2025-32 sec. 4.15'),
('US', 2026, 'hoh', 'standard_deduction', 0, NULL, 0, 24150, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', 'Rev. Proc. 2025-32 sec. 4.15'),

('US', 2026, 'single', 'bracket', 0, 12400, 0.10, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', 'Table 3 unmarried individuals'),
('US', 2026, 'single', 'bracket', 12400, 50400, 0.12, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'single', 'bracket', 50400, 105700, 0.22, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'single', 'bracket', 105700, 201775, 0.24, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'single', 'bracket', 201775, 256225, 0.32, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'single', 'bracket', 256225, 640600, 0.35, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'single', 'bracket', 640600, NULL, 0.37, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),

('US', 2026, 'mfj', 'bracket', 0, 24800, 0.10, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', 'Table 1 married filing jointly'),
('US', 2026, 'mfj', 'bracket', 24800, 100800, 0.12, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'mfj', 'bracket', 100800, 211400, 0.22, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'mfj', 'bracket', 211400, 403550, 0.24, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'mfj', 'bracket', 403550, 512450, 0.32, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'mfj', 'bracket', 512450, 768700, 0.35, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'mfj', 'bracket', 768700, NULL, 0.37, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),

('US', 2026, 'hoh', 'bracket', 0, 17700, 0.10, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', 'Table 2 heads of households'),
('US', 2026, 'hoh', 'bracket', 17700, 67450, 0.12, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'hoh', 'bracket', 67450, 105700, 0.22, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'hoh', 'bracket', 105700, 201750, 0.24, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'hoh', 'bracket', 201750, 256200, 0.32, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'hoh', 'bracket', 256200, 640600, 0.35, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),
('US', 2026, 'hoh', 'bracket', 640600, NULL, 0.37, NULL, NULL, @irs, 'https://www.irs.gov/irb/2025-45_IRB', NULL),

('US', 2026, 'all', 'child_tax_credit', 0, NULL, 0, 2200, '{"refundableMaxPerChild":1700,"refundableEarnedIncomeFloor":2500,"refundableRate":0.15,"phaseoutStart":{"single":200000,"hoh":200000,"mfj":400000},"phaseoutPerThousand":50}', @irs, 'https://www.irs.gov/irb/2025-45_IRB', 'Rev. Proc. 2025-32 sec. 4.05: $2,200 per child, refundable portion $1,700. Phase-out thresholds are statutory (IRC 24(b)).'),

('US', 2026, 'all', 'social_security', 0, 184500, 0.062, NULL, NULL, @ssa, 'https://www.ssa.gov/oact/cola/cbb.html', 'Employee OASDI share; wage base applies per earner'),
('US', 2026, 'all', 'medicare', 0, NULL, 0.0145, NULL, NULL, @ssa, 'https://www.ssa.gov/oact/cola/cbb.html', 'Employee HI share, no wage cap'),
('US', 2026, 'single', 'additional_medicare', 200000, NULL, 0.009, NULL, NULL, @irs, 'https://www.irs.gov/taxtopics/tc560', 'Statutory threshold (not indexed)'),
('US', 2026, 'hoh', 'additional_medicare', 200000, NULL, 0.009, NULL, NULL, @irs, 'https://www.irs.gov/taxtopics/tc560', 'Statutory threshold (not indexed)'),
('US', 2026, 'mfj', 'additional_medicare', 250000, NULL, 0.009, NULL, NULL, @irs, 'https://www.irs.gov/taxtopics/tc560', 'Statutory threshold (not indexed), combined wages');

-- ---------------------------------------------------------------- States with no wage income tax
INSERT INTO tax_rules (jurisdiction_code, tax_year, filing_status, rule_type, lower_bound, upper_bound, rate, fixed_amount, parameters_json, source_id, source_url, notes) VALUES
('FL', 2026, 'all', 'no_income_tax', 0, NULL, 0, NULL, NULL, @nowage, 'https://floridarevenue.com/taxes/taxesfees/Pages/default.aspx', 'Florida has no personal income tax'),
('TX', 2026, 'all', 'no_income_tax', 0, NULL, 0, NULL, NULL, @nowage, 'https://comptroller.texas.gov/taxes/', 'Texas has no personal income tax'),
('NV', 2026, 'all', 'no_income_tax', 0, NULL, 0, NULL, NULL, @nowage, 'https://tax.nv.gov/', 'Nevada has no personal income tax'),
('WA', 2026, 'all', 'no_income_tax', 0, NULL, 0, NULL, NULL, @nowage, 'https://dor.wa.gov/', 'Washington has no tax on wage income'),
('TN', 2026, 'all', 'no_income_tax', 0, NULL, 0, NULL, NULL, @nowage, 'https://www.tn.gov/revenue.html', 'Tennessee has no tax on wage income'),
('SD', 2026, 'all', 'no_income_tax', 0, NULL, 0, NULL, NULL, @nowage, 'https://dor.sd.gov/', 'South Dakota has no personal income tax'),
('WY', 2026, 'all', 'no_income_tax', 0, NULL, 0, NULL, NULL, @nowage, 'https://revenue.wyo.gov/', 'Wyoming has no personal income tax'),
('AK', 2026, 'all', 'no_income_tax', 0, NULL, 0, NULL, NULL, @nowage, 'https://tax.alaska.gov/', 'Alaska has no personal income tax'),
('NH', 2026, 'all', 'no_income_tax', 0, NULL, 0, NULL, NULL, @nowage, 'https://www.revenue.nh.gov/', 'New Hampshire does not tax wage income');

-- ---------------------------------------------------------------- New York State 2026 (IT-2105-I 2026)
INSERT INTO tax_rules (jurisdiction_code, tax_year, filing_status, rule_type, lower_bound, upper_bound, rate, fixed_amount, parameters_json, source_id, source_url, notes) VALUES
('NY', 2026, 'single', 'standard_deduction', 0, NULL, 0, 8000, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', 'Single, not claimed as a dependent'),
('NY', 2026, 'mfj', 'standard_deduction', 0, NULL, 0, 16050, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'hoh', 'standard_deduction', 0, NULL, 0, 11200, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),

('NY', 2026, 'single', 'bracket', 0, 8500, 0.039, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'single', 'bracket', 8500, 11700, 0.044, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'single', 'bracket', 11700, 13900, 0.0515, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'single', 'bracket', 13900, 80650, 0.054, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'single', 'bracket', 80650, 215400, 0.059, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'single', 'bracket', 215400, 1077550, 0.0685, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'single', 'bracket', 1077550, 5000000, 0.0965, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'single', 'bracket', 5000000, 25000000, 0.103, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'single', 'bracket', 25000000, NULL, 0.109, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),

('NY', 2026, 'mfj', 'bracket', 0, 17150, 0.039, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'mfj', 'bracket', 17150, 23600, 0.044, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'mfj', 'bracket', 23600, 27900, 0.0515, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'mfj', 'bracket', 27900, 161550, 0.054, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'mfj', 'bracket', 161550, 323200, 0.059, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'mfj', 'bracket', 323200, 2155350, 0.0685, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'mfj', 'bracket', 2155350, 5000000, 0.0965, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'mfj', 'bracket', 5000000, 25000000, 0.103, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'mfj', 'bracket', 25000000, NULL, 0.109, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),

('NY', 2026, 'hoh', 'bracket', 0, 12800, 0.039, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'hoh', 'bracket', 12800, 17650, 0.044, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'hoh', 'bracket', 17650, 20900, 0.0515, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'hoh', 'bracket', 20900, 107650, 0.054, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'hoh', 'bracket', 107650, 269300, 0.059, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'hoh', 'bracket', 269300, 1616450, 0.0685, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'hoh', 'bracket', 1616450, 5000000, 0.0965, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'hoh', 'bracket', 5000000, 25000000, 0.103, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NY', 2026, 'hoh', 'bracket', 25000000, NULL, 0.109, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL);

-- ---------------------------------------------------------------- New York City resident tax 2026 (applies to NY taxable income)
INSERT INTO tax_rules (jurisdiction_code, tax_year, filing_status, rule_type, lower_bound, upper_bound, rate, fixed_amount, parameters_json, source_id, source_url, notes) VALUES
('NYC', 2026, 'single', 'bracket', 0, 12000, 0.03078, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', 'NYC residents only'),
('NYC', 2026, 'single', 'bracket', 12000, 25000, 0.03762, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NYC', 2026, 'single', 'bracket', 25000, 50000, 0.03819, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NYC', 2026, 'single', 'bracket', 50000, NULL, 0.03876, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NYC', 2026, 'mfj', 'bracket', 0, 21600, 0.03078, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NYC', 2026, 'mfj', 'bracket', 21600, 45000, 0.03762, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NYC', 2026, 'mfj', 'bracket', 45000, 90000, 0.03819, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NYC', 2026, 'mfj', 'bracket', 90000, NULL, 0.03876, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NYC', 2026, 'hoh', 'bracket', 0, 14400, 0.03078, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NYC', 2026, 'hoh', 'bracket', 14400, 30000, 0.03762, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NYC', 2026, 'hoh', 'bracket', 30000, 60000, 0.03819, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL),
('NYC', 2026, 'hoh', 'bracket', 60000, NULL, 0.03876, NULL, NULL, @ny, 'https://www.tax.ny.gov/pdf/current_forms/it/it2105i.pdf', NULL);

-- ---------------------------------------------------------------- District of Columbia (latest published: tax year 2025)
INSERT INTO tax_rules (jurisdiction_code, tax_year, filing_status, rule_type, lower_bound, upper_bound, rate, fixed_amount, parameters_json, source_id, source_url, notes) VALUES
('DC', 2025, 'single', 'standard_deduction', 0, NULL, 0, 15000, NULL, @dc, 'https://otr.cfo.dc.gov/page/dc-individual-and-fiduciary-income-tax-rates', 'DC decoupled from the federal standard deduction for tax years beginning 2025'),
('DC', 2025, 'mfj', 'standard_deduction', 0, NULL, 0, 30000, NULL, @dc, 'https://otr.cfo.dc.gov/page/dc-individual-and-fiduciary-income-tax-rates', NULL),
('DC', 2025, 'hoh', 'standard_deduction', 0, NULL, 0, 22500, NULL, @dc, 'https://otr.cfo.dc.gov/page/dc-individual-and-fiduciary-income-tax-rates', NULL),
('DC', 2025, 'all', 'bracket', 0, 10000, 0.04, NULL, NULL, @dc, 'https://otr.cfo.dc.gov/page/dc-individual-and-fiduciary-income-tax-rates', 'Same schedule for all filing statuses'),
('DC', 2025, 'all', 'bracket', 10000, 40000, 0.06, NULL, NULL, @dc, 'https://otr.cfo.dc.gov/page/dc-individual-and-fiduciary-income-tax-rates', NULL),
('DC', 2025, 'all', 'bracket', 40000, 60000, 0.065, NULL, NULL, @dc, 'https://otr.cfo.dc.gov/page/dc-individual-and-fiduciary-income-tax-rates', NULL),
('DC', 2025, 'all', 'bracket', 60000, 250000, 0.085, NULL, NULL, @dc, 'https://otr.cfo.dc.gov/page/dc-individual-and-fiduciary-income-tax-rates', NULL),
('DC', 2025, 'all', 'bracket', 250000, 500000, 0.0925, NULL, NULL, @dc, 'https://otr.cfo.dc.gov/page/dc-individual-and-fiduciary-income-tax-rates', NULL),
('DC', 2025, 'all', 'bracket', 500000, 1000000, 0.0975, NULL, NULL, @dc, 'https://otr.cfo.dc.gov/page/dc-individual-and-fiduciary-income-tax-rates', NULL),
('DC', 2025, 'all', 'bracket', 1000000, NULL, 0.1075, NULL, NULL, @dc, 'https://otr.cfo.dc.gov/page/dc-individual-and-fiduciary-income-tax-rates', NULL);

-- ---------------------------------------------------------------- Virginia 2026 (standard deduction confirmed for 2026; statutory rates)
INSERT INTO tax_rules (jurisdiction_code, tax_year, filing_status, rule_type, lower_bound, upper_bound, rate, fixed_amount, parameters_json, source_id, source_url, notes) VALUES
('VA', 2026, 'single', 'standard_deduction', 0, NULL, 0, 8750, NULL, @va, 'https://www.tax.virginia.gov/deductions', NULL),
('VA', 2026, 'hoh', 'standard_deduction', 0, NULL, 0, 8750, NULL, @va, 'https://www.tax.virginia.gov/deductions', 'Virginia has no separate head-of-household amount'),
('VA', 2026, 'mfj', 'standard_deduction', 0, NULL, 0, 17500, NULL, @va, 'https://www.tax.virginia.gov/deductions', NULL),
('VA', 2026, 'all', 'bracket', 0, 3000, 0.02, NULL, NULL, @va, 'https://www.tax.virginia.gov/sites/default/files/vatax-pdf/2025-760-instructions.pdf', 'Same schedule for all filing statuses'),
('VA', 2026, 'all', 'bracket', 3000, 5000, 0.03, NULL, NULL, @va, 'https://www.tax.virginia.gov/sites/default/files/vatax-pdf/2025-760-instructions.pdf', NULL),
('VA', 2026, 'all', 'bracket', 5000, 17000, 0.05, NULL, NULL, @va, 'https://www.tax.virginia.gov/sites/default/files/vatax-pdf/2025-760-instructions.pdf', NULL),
('VA', 2026, 'all', 'bracket', 17000, NULL, 0.0575, NULL, NULL, @va, 'https://www.tax.virginia.gov/sites/default/files/vatax-pdf/2025-760-instructions.pdf', NULL);
