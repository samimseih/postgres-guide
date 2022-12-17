## set username
WHOAMI=`whoami`
PRIMPORT=5432
SECPORT=5433

## promote standby to primary
psql -h localhost -d postgres -U $WHOAMI -p $SECPORT <<EOF
select pg_promote();
EOF

## create db1 on fdw target
psql -h localhost -d postgres -U $WHOAMI -p $SECPORT <<EOF
create database db1;
create extension pg_stat_statements;
select count(*) from pg_stat_statements;
EOF

## create db1 on fdw source
psql -h localhost -d postgres -U $WHOAMI -p $PRIMPORT <<EOF
create database db1;
EOF

## create foreign server on fdw source
psql -h localhost -d db1 -U $WHOAMI -p $PRIMPORT <<EOF
CREATE EXTENSION postgres_fdw;
DROP SERVER kcn cascade;
CREATE SERVER kcn FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'localhost', dbname 'db1', port '${SECPORT}');
CREATE USER MAPPING FOR CURRENT_USER SERVER kcn OPTIONS (user '${WHOAMI}');
EOF

## create customer table on fdw_source
psql -h localhost -d db1 -U $WHOAMI -p $PRIMPORT <<EOF
DROP TABLE customer;
CREATE TABLE customer (customer_id int, customer_name text, customer_location int) PARTITION BY HASH (customer_id);
DROP TABLE locations;
CREATE TABLE locations (location_id int, state text, city text) PARTITION BY HASH (location_id);
EOF

## create partition of fdw target
psql -h localhost -d db1 -U $WHOAMI -p $SECPORT <<EOF
DROP TABLE customer, customer_0, customer_1, customer_2;
CREATE TABLE customer (customer_id int, customer_name text, customer_location int) PARTITION BY HASH (customer_id);
CREATE TABLE customer_0 PARTITION OF customer FOR VALUES WITH (MODULUS 3,REMAINDER 0);
CREATE TABLE customer_1 PARTITION OF customer FOR VALUES WITH (MODULUS 3,REMAINDER 1);
CREATE TABLE customer_2 PARTITION OF customer FOR VALUES WITH (MODULUS 3,REMAINDER 2);

DROP TABLE locations, locations_0, locations_1, locations_2;
CREATE TABLE locations (location_id int, state text, city text) PARTITION BY HASH (location_id);
CREATE TABLE locations_0 PARTITION OF locations FOR VALUES WITH (MODULUS 3,REMAINDER 0);
CREATE TABLE locations_1 PARTITION OF locations FOR VALUES WITH (MODULUS 3,REMAINDER 1);
CREATE TABLE locations_2 PARTITION OF locations FOR VALUES WITH (MODULUS 3,REMAINDER 2);

CREATE sequence customer_id_seq;
CREATE sequence locations_id_seq;
EOF

## create partition table with foreign partitions on fdw source
psql -h localhost -d db1 -U $WHOAMI -p $PRIMPORT  <<EOF
CREATE FOREIGN TABLE customer_0
    PARTITION OF customer FOR VALUES WITH (MODULUS 3,REMAINDER 0)
    SERVER kcn;
CREATE FOREIGN TABLE customer_1
    PARTITION OF customer FOR VALUES WITH (MODULUS 3,REMAINDER 1)
    SERVER kcn;
CREATE FOREIGN TABLE customer_2
    PARTITION OF customer FOR VALUES WITH (MODULUS 3,REMAINDER 2)
    SERVER kcn;
select * from customer;

CREATE FOREIGN TABLE locations_0
    PARTITION OF locations FOR VALUES WITH (MODULUS 3,REMAINDER 0)
    SERVER kcn;
CREATE FOREIGN TABLE locations_1
    PARTITION OF locations FOR VALUES WITH (MODULUS 3,REMAINDER 1)
    SERVER kcn;
CREATE FOREIGN TABLE locations_2
    PARTITION OF locations FOR VALUES WITH (MODULUS 3,REMAINDER 2)
    SERVER kcn;
select * from locations;

EOF
