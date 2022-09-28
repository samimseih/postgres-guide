"""
Author:     Sami Imseih
Revision:   04/30/2022
Comments:   pgenvironment.py is a Python script to automate the
            pulling from mirror, compiling, and cluster creation
            of Postgres.

            It is a useful script for quickly spinning up a
            Postgres instance of a specific version, doing
            functional tests and writing patches.

            It is also possible to spin up a standby as well!

            The script is written and tested with Python 2
            and does not require any non-standard modules.
            This is intentional to make this script available
            for Linux and MacOS distributions without the
            need to install any additional dependencies.

            Windows is not supported and probably will not
            be.

            There is NO WARRANTY for this script and it 
            should not be used in PRODUCTION envrionments.
"""
import os, sys, multiprocessing, argparse, getpass, socket
from sys import platform

VERSION = 1.0

## Global variables
CLONE_DIRECTORY = "postgresql";
PGHOME_DIRECTORY = "pghome";
PGDATA_DIRECTORY = "pgdata";
DEFAULT_DATABASE = "postgres";
PORT = 5432;
REPO_MIRROR_URL = "https://git.postgresql.org/git/postgresql.git";

## OS level things
CPU_COUNT = multiprocessing.cpu_count();
WHOAMI = getpass.getuser();

def validate(with_replica, with_replication_slot):
    if platform == "linux" or platform == "linux2":
        os.system("sudo yum install git gcc readline-devel openssl-devel uuid-devel zlib-devel flex bison sysstat gdb dstat perl-Test-Harness perl-IPC-Run perl-Test-Simple -y");
    elif platform == "darwin":
        pass;
    else:
        print("error: unsupported platform");
        sys.exit(1);

    if (not with_replica) and (with_replication_slot):
        print("warning: ignoring '-s/--with-replication-slot' as it must be used with '-r/--with-replica'");

def clone_repository(work_directory, no_replace, all_branches, version = None, include_patches = None):
    version_git_opts = ""

    # replace the clone of the mirror
    if no_replace:
        return;

    if all_branches:
        all_branches = "";
    else:
        all_branches = "--depth 1"
        
    print("Cloning the Postgres Repository")
    os.system("rm -rfv {work_directory} >/dev/null; mkdir {work_directory}".
                        format(
                                work_directory = work_directory
                        )
    );

    if version is not None:
        version_git_opts = ("""-c advice.detachedHead=false {} --branch REL_"""+version.replace(".", "_")).format(all_branches);
    else:
        version_git_opts = """{}""".format(all_branches);

    # clone the repo
    cmd = "git clone {} {} {}".format(
            version_git_opts,
            REPO_MIRROR_URL,
            os.path.join(work_directory, CLONE_DIRECTORY)
    );
    print("running " + "'" + cmd + "'");

    err = os.system(cmd);
    if (err > 0):
        print("error: cloning the Postgres repository")
        sys.exit(1);

    # build the binaries
    build_postgres(work_directory, version, include_patches);

def build_postgres(work_directory, version, include_patches):
    os.environ["PGHOME"] = os.path.join(work_directory, PGHOME_DIRECTORY)

    patches_to_include = "";
    if include_patches:
        patches_to_include = "git apply {}".format(include_patches);

    if platform == "darwin":
        uuid = "e2fs"
    else:
        uuid = "ossp"

    cmd = """
            cd {};
            {}
            ./configure --prefix={} --with-uuid={} --with-openssl --enable-debug --enable-tap-tests CFLAGS="-fno-omit-frame-pointer" >/dev/null;
            make install -j{} >/dev/null
          """.format(
                        os.path.join(work_directory, CLONE_DIRECTORY),
                        patches_to_include,
                        os.environ["PGHOME"],
                        uuid,
                        CPU_COUNT
                );
    print("running " + "'" + cmd + "'");
    err = os.system(cmd);
    if (err > 0):
        print("error: building postgresql");
        sys.exit(1);

def setenv(work_directory, kill = False):
    print("setting env");
    os.environ["PGHOME"] = os.path.join(work_directory, PGHOME_DIRECTORY);
    os.environ["PGDATA"] = os.path.join(work_directory, PGDATA_DIRECTORY);
    os.environ["PGDATABASE"] = DEFAULT_DATABASE;
    os.environ["PGUSER"] = WHOAMI;
    os.environ["PGPORT"] = str(PORT);
    os.environ["PATH"] = os.path.join(work_directory, PGHOME_DIRECTORY, "bin") + os.pathsep + os.environ["PATH"];
    try:
        os.environ["LD_LIBRARY_PATH"] = os.path.join(os.environ["PGHOME"], "lib") + os.pathsep + os.environ["LD_LIBRARY_PATH"];
    except KeyError:
        os.environ["LD_LIBRARY_PATH"] = os.pathsep + os.path.join(os.environ["PGHOME"], "lib");

    if (kill):
        cmd = """pkill -9 postgres""";
        print("running: {}".format(cmd));
        os.system(cmd);

def initdb(work_directory, no_initdb, with_replica, with_replication_slot, kill_pg, pg_config):
    if no_initdb:
        return;

    setenv(work_directory, kill_pg);

    cmd = "rm -rfv {} >/dev/null".format(os.environ["PGDATA"]);
    print("running: {}".format(cmd));
    os.system(cmd);

    cmd = "{} -D {}".format(
        os.path.join(os.environ["PGHOME"], "bin", "initdb"), 
        os.environ["PGDATA"]);
    print("running: '{}'".format(cmd));
    err = os.system(cmd)
    if (err > 0):
        print("error: could not initdb");
        sys.exit(1);

    if (pg_config is not None):
        list_of_pgconfig = pg_config.split(",");
        if len(list_of_pgconfig) > 0:
            os.system("### custom parameters set by pgenvironment.py");
            for y in list_of_pgconfig:
                os.system("echo {} >> $PGDATA/postgresql.conf".format(y));

    generate_activate_script(args.work_directory);

    if (with_replica):
        initreplica(work_directory, with_replication_slot);
    else:
        os.system("echo wal_level = logical >> $PGDATA/postgresql.conf");
        os.system("pg_ctl start -l $PGDATA/logfile");

def initreplica(work_directory, with_replication_slot):
    setenv(work_directory);

    print("configuring the primary for streaming replication");

    ## configure the primary
    os.system("echo '#### streaming replication settings' >> $PGDATA/postgresql.conf");
    os.system("echo max_wal_senders = 5 >> $PGDATA/postgresql.conf");
    os.system("echo host replication   all   all  trust >> $PGDATA/pg_hba.conf");
    os.system("pg_ctl start -l $PGDATA/logfile");

    err = os.system("rm -rfv ${PGDATA}_sec >/dev/null");
    if (err > 0):
        print("error cleaning up previous standby database");
        sys.exit(1);
    else:
        print("cleaned up previous standby database");

    if (with_replication_slot):
        repl_slot_string = "--create-slot --slot=pgenvionrment_slot";
    else:
        repl_slot_string = "";

    print("generating command to build standby");

    ## startup a replica
    cmd = """
            pg_basebackup \
            --pgdata=${{PGDATA}}_sec \
            --format=p \
            --write-recovery-conf \
            --checkpoint=fast \
            --label=mffb \
            --progress \
            --username=$PGUSER {}
        """.format(repl_slot_string);
    print("running: {}".format(cmd));
    os.system(cmd);

    os.environ["PGDATA"] = os.environ["PGDATA"]+"_sec";
    os.system("echo '#### streaming replication settings' >> $PGDATA/postgresql.conf");
    os.system("echo port={} >> $PGDATA/postgresql.conf".format(int(os.environ["PGPORT"]) + 1));
    os.system("pg_ctl start -l $PGDATA/logfile");

    generate_activate_script(work_directory, True);

def generate_activate_script(work_directory, standby = False):
    os.environ["PGHOME"] = os.path.join(work_directory, PGHOME_DIRECTORY);
    os.environ["PGDATA"] = os.path.join(work_directory, PGDATA_DIRECTORY);
    os.environ["PATH"] += os.pathsep + os.path.join(work_directory, PGHOME_DIRECTORY, "bin");
    os.environ["LD_LIBRARY_PATH"] += os.pathsep + os.path.join(os.environ["PGHOME"], "lib");

    if standby:
        port = PORT + 1;
        pgdata = os.environ["PGDATA"]+"_sec";
        act = "activate_sec";
        dea = "deactivate_sec";
    else:
        pgdata = os.environ["PGDATA"];
        act = "activate";
        dea = "deactivate";
        port = PORT;


    activate = """## source the postgres environment
export PGHOME={}
export PGDATA={}
export PATH={}:$PATH
export LD_LIBRARY_PATH={}:$LD_LIBRARY_PATH
export PGDATABASE={}
export PGUSER={}
export PGPORT={}
alias start_db="pg_ctl start -l {}"
alias stop_db="pg_ctl stop -mf"
""".format(
        os.environ["PGHOME"], 
        pgdata,
        os.path.join(os.environ["PGHOME"], "bin"),
        os.path.join(pgdata, "lib"),
        DEFAULT_DATABASE,
        WHOAMI,
        port,
        os.path.join(pgdata, "logfile")
        );

    with open(os.path.join(work_directory, act), "w") as text_file:
        text_file.write(activate);

    with open(os.path.join(work_directory, dea), "w") as text_file:
        text_file.write("""## disable the postgres environment
unset PGHOME
unset PGDATA
unset PATH
unset LD_LIBRARY_PATH
unset PGDATABASE
unset PGUSER
unset PGPORT
unalias start_db
unalias stop_db
        """);

parser = argparse.ArgumentParser();
parser.add_argument('-D', '--work-directory', required = True, help = 'directory of the environment');
parser.add_argument('-N', '--no-replace', action = 'store_true', help = 'use existing clone of the repository');
parser.add_argument('-X', '--no-initdb', action = 'store_true', help = 'do not init a new database');
parser.add_argument('-r', '--with-replica', action = 'store_true', help = 'create a streaming replica');
parser.add_argument('-s', '--with-replication-slot', action = 'store_true', help = 'create a replication slot');
parser.add_argument('-c', '--pg-config', help = 'comma delimited key-value pairs of parameters');
parser.add_argument('-k', '--kill-pg', action = 'store_true', help = 'force kill postgres before creating new instances');
parser.add_argument('-p', '--include-patches', help = 'include patches');
parser.add_argument('-v', '--version', help = """
use specific version, i.e. '14.1' or '11.STABLE'.
If a version is not set, the HEAD branch will be used.
""");
parser.add_argument('-A', '--all_branches', action = 'store_true', help = 'fetch all branches')
args = parser.parse_args();

validate(args.with_replica, args.with_replication_slot);
# let's start doing work
clone_repository(args.work_directory, args.no_replace, args.all_branches, args.version, args.include_patches);
initdb(args.work_directory, args.no_initdb, args.with_replica, args.with_replication_slot, args.kill_pg, args.pg_config);

# show the tag/branches
os.system("cd {}; git describe --tags 2>/dev/null; git branch -a 2>/dev/null".format(args.work_directory));
