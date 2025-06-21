BEGIN;
-- Test AGE extension installation
CREATE EXTENSION IF NOT EXISTS age;

-- Load the extension
LOAD 'age';

-- Test that ag_catalog schema exists
SELECT has_schema('ag_catalog');

-- Test basic AGE functionality
SELECT age.create_graph('test_graph');
SELECT age.drop_graph('test_graph', true);

ROLLBACK;