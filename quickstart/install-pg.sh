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
	else
        	git clone \
			-c advice.detachedHead=false  \
			--branch REL_${version} https://git.postgresql.org/git/postgresql.git $directory/postgresql
	fi;

	cd postgresql
	./configure --prefix $directory/pghome
	make install -j $(cat /proc/cpuinfo  | grep processor | tail -1 | awk '{print $2}' FS=":")
	cd $MYPWD
}

function create_prof()
{
	echo export PGHOME=$directory/pghome > $directory/activate.sh
	echo export 'PATH=$PGHOME/bin:$PATH' >> $directory/activate.sh
	echo export 'LD_LIBRARY_PATH=$PGHOME/lib:$LD_LIBRARY_PATH' >> $directory/activate.sh
	echo export PGDATA=$directory/pgdata >> $directory/activate.sh
	echo export PGUSER=postgres >> $directory/activate.sh
	chmod a+x $directory/activate.sh
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
	pg_ctl start
}

#install_prereqs
#install_pg
create_prof
create_db
