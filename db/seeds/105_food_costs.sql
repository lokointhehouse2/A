-- FuturePath seed 105: USDA Food Plans, Cost of Food at Home at Three Levels, U.S. average, August 2026
-- (issued September 2026). Monthly cost per person in a 4-person household.

SET @usda = (SELECT id FROM data_sources WHERE source_key = 'usda_food');

INSERT INTO regional_cost_observations (geo_system, geo_code, category, period_year, period_label, amount, unit, household_profile_json, source_id, confidence_notes) VALUES
('US', 'US', 'food_low_child_1', 2026, '2026-08', 165.10, 'USD per month', '{"ageGroup":"child_1"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_low_child_2_3', 2026, '2026-08', 173.50, 'USD per month', '{"ageGroup":"child_2_3"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_low_child_4_5', 2026, '2026-08', 178.80, 'USD per month', '{"ageGroup":"child_4_5"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_low_child_6_8', 2026, '2026-08', 262.00, 'USD per month', '{"ageGroup":"child_6_8"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_low_child_9_11', 2026, '2026-08', 270.90, 'USD per month', '{"ageGroup":"child_9_11"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_low_female_19_50', 2026, '2026-08', 275.70, 'USD per month', '{"ageGroup":"female_19_50"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_low_male_19_50', 2026, '2026-08', 317.20, 'USD per month', '{"ageGroup":"male_19_50"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_moderate_child_1', 2026, '2026-08', 185.80, 'USD per month', '{"ageGroup":"child_1"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_moderate_child_2_3', 2026, '2026-08', 207.10, 'USD per month', '{"ageGroup":"child_2_3"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_moderate_child_4_5', 2026, '2026-08', 221.40, 'USD per month', '{"ageGroup":"child_4_5"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_moderate_child_6_8', 2026, '2026-08', 304.50, 'USD per month', '{"ageGroup":"child_6_8"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_moderate_child_9_11', 2026, '2026-08', 349.50, 'USD per month', '{"ageGroup":"child_9_11"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_moderate_female_19_50', 2026, '2026-08', 336.10, 'USD per month', '{"ageGroup":"female_19_50"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_moderate_male_19_50', 2026, '2026-08', 398.10, 'USD per month', '{"ageGroup":"male_19_50"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_liberal_child_1', 2026, '2026-08', 226.00, 'USD per month', '{"ageGroup":"child_1"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_liberal_child_2_3', 2026, '2026-08', 252.30, 'USD per month', '{"ageGroup":"child_2_3"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_liberal_child_4_5', 2026, '2026-08', 267.60, 'USD per month', '{"ageGroup":"child_4_5"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_liberal_child_6_8', 2026, '2026-08', 356.30, 'USD per month', '{"ageGroup":"child_6_8"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_liberal_child_9_11', 2026, '2026-08', 407.40, 'USD per month', '{"ageGroup":"child_9_11"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_liberal_female_19_50', 2026, '2026-08', 428.80, 'USD per month', '{"ageGroup":"female_19_50"}', @usda, 'National average; food at home only'),
('US', 'US', 'food_liberal_male_19_50', 2026, '2026-08', 486.20, 'USD per month', '{"ageGroup":"male_19_50"}', @usda, 'National average; food at home only');
