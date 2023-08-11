directory=$1
version=$2
MYPWD=$PWD

function install_prereqs()
{
	sudo yum install \
		git \
		autoconf \
		gcc \
		automake \
		readline-devel \
		zlib-devel \
		flex \
		bison \
		perl-Test-Harness \
		perl-IPC-Run \
		perl-Test-Simple \
		libxslt \
		autoconf-archive \
		docbook-xsl \
		libtool -y

	sudo dnf install perl -y
}

function install_pg()
{
	rm -rfv $directory >/dev/null; mkdir -pv $directory;

	cd $directory

	if [[ "$version" == "current" ]];
	then
        	git clone https://github.com/postgres/postgres.git
		cd postgres
	else
        	git clone \
			-c advice.detachedHead=false  \
			--branch REL_${version} https://git.postgresql.org/git/postgresql.git $directory/postgresql
		cd postgresql
	fi;

	./configure --prefix $directory/pghome --with-openssl
	make install -j $(cat /proc/cpuinfo  | grep processor | tail -1 | awk '{print $2}' FS=":")
	cd $MYPWD
}

function build_extensions()
{
        cd $directory/postgres/contrib
        cd pg_stat_statements
        make install
        cd ../postgres_fdw
        make install
        cd $MYPWD
}

function create_prof()
{
	echo export PGHOME=$directory/pghome > $directory/activate.sh
	echo export 'PATH=$PGHOME/bin:$PATH' >> $directory/activate.sh
	echo export 'LD_LIBRARY_PATH=$PGHOME/lib:$LD_LIBRARY_PATH' >> $directory/activate.sh
	echo export PGDATA=$directory/pgdata >> $directory/activate.sh
	echo export PGUSER=postgres >> $directory/activate.sh
	echo export PGPORT=5432 >> $directory/activate.sh
	chmod a+x $directory/activate.sh
}
function create_prof_replica()
{
	echo export PGHOME=$directory/pghome > $directory/activate_sec.sh
	echo export 'PATH=$PGHOME/bin:$PATH' >> $directory/activate_sec.sh
	echo export 'LD_LIBRARY_PATH=$PGHOME/lib:$LD_LIBRARY_PATH' >> $directory/activate_sec.sh
	echo export PGDATA=$directory/pgdata_sec >> $directory/activate_sec.sh
	echo export PGUSER=postgres >> $directory/activate_sec.sh
	echo export PGPORT=5433 >> $directory/activate_sec.sh
	chmod a+x $directory/activate_sec.sh
}

function create_db()
{
	pkill -9 postgres
	source $directory/activate.sh
	rm -rfv $PGDATA >/dev/null
	rm -rfv $directory/backups >/dev/null; mkdir $directory/backups >/dev/null
	rm -rfv $directory/archive_logs >/dev/null; mkdir $directory/archive_logs >/dev/null
	initdb -U postgres
	echo wal_level = logical >> $PGDATA/postgresql.conf
	echo archive_mode = off >> $PGDATA/postgresql.conf
	echo restore_command = \'cp $directory/archive_logs/%f %p\' >> $PGDATA/postgresql.conf
	echo archive_command = \'test \! -f $directory/archive_logs/%f \&\& \
		cp %p $directory/archive_logs/%f\'  >> $PGDATA/postgresql.conf
	echo logging_collector = on >> $PGDATA/postgresql.conf
	echo max_wal_senders = 5 >> $PGDATA/postgresql.conf
	echo host replication   all   all  trust >> $PGDATA/pg_hba.conf
	echo ssl=on >> $PGDATA/postgresql.conf

	MYPWD=`pwd`
	cd $PGDATA
	openssl req -new -x509 -days 365 -nodes -text -out server.crt \
	-keyout server.key -subj "/CN=localhost"
	chmod og-rwx server.key
	cd $MYPWD

	pg_ctl start
        psql -c "alter system set shared_preload_libraries='pg_stat_statements'";
        pg_ctl stop -mf
        pg_ctl start
}

function create_replica()
{
	source $directory/activate.sh
	rm -rfv ${PGDATA}_sec >/dev/null
	pg_basebackup \
		--pgdata=${PGDATA}_sec \
		--format=p \
		--write-recovery-conf \
		--checkpoint=fast \
		--label=mffb \
		--progress \
		--username=$PGUSER \
		--create-slot \
		--slot=pgenv_slot
	export PGDATA=${PGDATA}_sec
	echo port=5433 >> $PGDATA/postgresql.conf
	echo archive_mode = off >> $PGDATA/postgresql.conf
	echo restore_command = \'\' >> $PGDATA/postgresql.conf
	echo archive_command = \'\' >> $PGDATA/postgresql.conf
	echo ssl=on >> $PGDATA/postgresql.conf

	MYPWD=`pwd`
	cd $PGDATA
	openssl req -new -x509 -days 365 -nodes -text -out server.crt \
	-keyout server.key -subj "/CN=localhost"
	chmod og-rwx server.key
	cd $MYPWD

	pg_ctl start
	psql -c "alter system set shared_preload_libraries='pg_stat_statements'";
	pg_ctl stop -mf
	pg_ctl start

}

install_prereqs
install_pg
build_extensions
create_prof
create_db
create_replica
create_prof_replica
