-- FuturePath seed 104: federal student loan rates (2026-27) and generic education pathways

SET @fsa = (SELECT id FROM data_sources WHERE source_key = 'fsa_rates');
SET @fp = (SELECT id FROM data_sources WHERE source_key = 'futurepath_assumption');

INSERT INTO loan_assumptions (loan_key, description, annual_interest_rate, duration_months, valid_from, valid_to, source_id, source_url) VALUES
('direct_undergrad', 'Direct Subsidized / Unsubsidized Loan, undergraduate (fixed rate, 10-year standard repayment)', 6.520, 120, '2026-07-01', '2027-06-30', @fsa, 'https://edfinancial.studentaid.gov/interest-rates-for-federal-student-loans'),
('direct_grad', 'Direct Unsubsidized Loan, graduate or professional (fixed rate, 10-year standard repayment)', 8.070, 120, '2026-07-01', '2027-06-30', @fsa, 'https://edfinancial.studentaid.gov/interest-rates-for-federal-student-loans'),
('direct_plus', 'Direct PLUS Loan, parents and graduate/professional students (fixed rate, 10-year standard repayment)', 9.070, 120, '2026-07-01', '2027-06-30', @fsa, 'https://edfinancial.studentaid.gov/interest-rates-for-federal-student-loans');

-- Years are counted from high school graduation. Typical full-time lengths; real timelines vary.
INSERT INTO education_pathways (pathway_key, name, type, minimum_years, typical_years, cost_basis, licensing_notes, description, source_id, sort_order) VALUES
('work', 'Start working after high school', 'work', 0, 0, 'No tuition', NULL, 'Enter the workforce directly; many employers train on the job.', @fp, 10),
('ged', 'GED or high school equivalency, then work', 'ged', 0.3, 0.5, 'Testing fees only (varies by state)', 'A GED is accepted as high school equivalency by most employers and colleges.', 'Earn a high school equivalency credential, then start working or continue training.', @fp, 20),
('certificate', 'Certificate or postsecondary nondegree award', 'certificate', 0.5, 1, 'Program tuition (see school data)', 'Some occupations require a state license or exam after training.', 'Short career-focused programs at technical and community colleges.', @fp, 30),
('apprenticeship', 'Registered apprenticeship (earn while you learn)', 'apprenticeship', 1, 4, 'Usually paid by employer; apprentices earn wages', 'Many trades require a journeyworker license after the apprenticeship.', 'Paid on-the-job training plus classroom instruction, typically 1 to 6 years.', @fp, 40),
('associate', 'Associate degree', 'associate', 2, 2, 'Tuition and fees (see school data)', NULL, 'Two-year degree at a community or technical college; many students take longer.', @fp, 50),
('bachelor', 'Bachelor''s degree', 'bachelor', 4, 4, 'Tuition and fees (see school data)', 'Teaching in public K-12 schools also requires a state teaching license.', 'Four-year degree; many students take five or six years.', @fp, 60),
('master', 'Master''s degree', 'master', 5, 6, 'Bachelor''s plus graduate tuition', NULL, 'One to three years of graduate study after a bachelor''s degree.', @fp, 70),
('doctoral', 'Doctoral degree (PhD)', 'doctoral', 8, 10, 'Bachelor''s plus doctoral study (often funded by assistantships)', 'College professor positions typically require a doctoral degree, and they are competitive.', 'Research degree after a bachelor''s degree; length varies widely.', @fp, 80),
('professional', 'Professional degree (e.g. law, pharmacy, dentistry)', 'professional', 6, 7, 'Bachelor''s plus professional school tuition', 'Most professional occupations require passing a licensing exam.', 'Degree from a professional school after (or combined with) undergraduate study.', @fp, 90),
('medicine', 'Medical degree (MD or DO) plus residency', 'professional', 11, 12, 'Bachelor''s plus four years of medical school; residents are paid', 'Physicians must complete residency (3 to 7 years) and pass licensing exams.', 'Pre-med bachelor''s, four years of medical school, then paid residency training.', @fp, 100);
