-- Create additional databases for Matrix Authentication Service and Authelia
-- The main 'synapse' database is already created via POSTGRES_DB env var

-- Create database for Matrix Authentication Service (MAS)
CREATE DATABASE mas;

-- Create database for Authelia
CREATE DATABASE authelia;

-- Grant privileges to the synapse user for all databases
GRANT ALL PRIVILEGES ON DATABASE mas TO synapse;
GRANT ALL PRIVILEGES ON DATABASE authelia TO synapse;

-- Display confirmation
\echo 'Additional databases created: mas, authelia'
