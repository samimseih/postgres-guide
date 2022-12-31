total_partitions=$1
pghome=$2
recreate_home=$3

if [[ -z $1 || -z $2 ]];
then
	echo ""
	echo "./pg_fdw.sh <# of partitions> <pg data> <recreate home (t to recreate)> <patch to apply. Can only be used with recreate home set to 't'>"
	exit 1;
fi
WHOAMI=`whoami`
PRIMPORT=5432
SECPORT=5433

if [ "$3" == "t" ];
then

	if [ -z $4 ];
	then
		python3 pgenvironment.py -D $2 -kr -c "shared_preload_libraries=pg_stat_statements";
	else
		python3 pgenvironment.py -D $2 -kr -p $4 -c "shared_preload_libraries=pg_stat_statements";
	fi;
else
	python3 pgenvironment.py -D $2 -krN -c "shared_preload_libraries=pg_stat_statements";
fi;

. ${2}/activate

psql -h localhost -d postgres -U $WHOAMI -p $SECPORT <<EOF
select pg_promote();
EOF

## create db1 on fdw target
psql -h localhost -d postgres -U $WHOAMI -p $SECPORT <<EOF
create database db1;
\c db1
create extension pg_stat_statements;
select count(*) from pg_stat_statements;
EOF

## create db1 on fdw source
psql -h localhost -d postgres -U $WHOAMI -p $PRIMPORT <<EOF
create database db1;
\c db1
create extension pg_stat_statements;
select count(*) from pg_stat_statements;
EOF
## create foreign server on fdw source
psql -h localhost -d db1 -U $WHOAMI -p $PRIMPORT <<EOF
CREATE EXTENSION postgres_fdw;
DROP SERVER kcn cascade;
CREATE SERVER kcn FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'localhost', dbname 'db1', port '${SECPORT}');
CREATE USER MAPPING FOR CURRENT_USER SERVER kcn OPTIONS (user '${WHOAMI}');
EOF

pgbench -h localhost -d db1 -U $WHOAMI -p $SECPORT -i -s 1 --partition-method=hash --partitions=${total_partitions}
pgbench -h localhost -d db1 -U $WHOAMI -p $PRIMPORT -i -s 1 --partition-method=hash --partitions=1
psql -h localhost -d db1 -U $WHOAMI -p $PRIMPORT <<EOF
alter table pgbench_accounts detach partition pgbench_accounts_1;
drop table pgbench_accounts_1;
alter table pgbench_accounts drop constraint pgbench_accounts_pkey;
drop table pgbench_tellers;
drop table pgbench_branches;
drop table pgbench_history;
CREATE FOREIGN TABLE pgbench_history
(
    tid integer,
    bid integer,
    aid integer,
    delta integer,
    mtime timestamp without time zone,
    filler character(22)
) SERVER kcn;

CREATE FOREIGN TABLE pgbench_tellers
(
    tid integer,
    bid integer,
    tbalance integer,
    filler character(84)
) SERVER KCN;

CREATE FOREIGN TABLE pgbench_branches
(
    bid integer,
    bbalance integer,
    filler character(88)
) SERVER KCN;
EOF

for (( c=0; c<$total_partitions; c++ ))
do 
   let "t=c+1"
   echo "CREATE FOREIGN TABLE pgbench_accounts_${t} PARTITION OF pgbench_accounts FOR VALUES WITH (MODULUS ${total_partitions},REMAINDER ${c}) SERVER kcn;" >>/tmp/$$.create.$$.sql
done
psql -h localhost -d db1 -U $WHOAMI -p $PRIMPORT -f /tmp/$$.create.$$.sql ; rm -rfv /tmp/$$.create.$$.sql

echo ""
echo ""
echo ""
echo PGBENCH COMMAND IS: pgbench -h localhost -d db1 -U $WHOAMI -p $PRIMPORT  -c 10 -t 1000
echo ""
echo ""
echo ""
