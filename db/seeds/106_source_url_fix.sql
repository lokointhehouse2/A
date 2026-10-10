-- FuturePath seed 106: point the editable-assumption "source" at the in-app assumptions page.

UPDATE data_sources SET source_url = '/sources' WHERE source_key = 'futurepath_assumption';
