# Scripts

## Inventory
* [pgenvironment](#pgenvironment)

### pgenvironment<a id='pgenvironment'></a>

pgenvironment.py is a helper script to automate building a
Postgres in an isolated environment. The script also creates
a starter database with the defaults.

The script requires only standard Python 2 and works for both
Linux and MacOS systems.

##### To access to the help menu
```
python  ./pgenvironment.py -h
```
##### Sample usage
This creates the environment in a directory called **/tmp/path_to_my_env**
Optionally, the version can be passed using the **-v** flag
```
python ./pgenvironment.py -D /tmp/path_to_my_env -v 11.10
```
Optionally, the "-c" flag can be passed with a comma
delimited list of key/value pairs of postgresql.config
parameters. i.e ```-c 'shared_buffers=4GB,max_wal_size=1GB'```

Also, the ```-r``` false is passed, a standby is created
using streaming replication.
The standby will listen on a port that is one number higher
by default. The primary is on port 5432 and the standby is on
port 5433.
##### To activate the environment
```
cd /tmp/path_to_my_env
. ./activate
```
For the standby, there will be a ```activate_sec``` script.
##### To start the database
```
start_db
```
##### Connect to Postgres
```
psql -d postgres -c "select version()";
                                                    version
----------------------------------------------------------------------------------------------------------------
 PostgreSQL 11.10 on aarch64-unknown-linux-gnu, compiled by gcc (GCC) 7.3.1 20180712 (Red Hat 7.3.1-13), 64-bit
(1 row)
```
##### To stop the database
```
stop_db
```
##### To deactivate the environment
```
cd /tmp/path_to_my_env
. ./deactivate
```
For the standby, there will be a ```deactivate_sec``` script.
