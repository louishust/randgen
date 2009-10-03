package GenTest::Executor::Drizzle;

require Exporter;

@ISA = qw(GenTest::Executor);

use strict;
use DBI;
use GenTest;
use GenTest::Constants;
use GenTest::Result;
use GenTest::Executor;
use Time::HiRes;

use constant RARE_QUERY_THRESHOLD	=> 5;

my %reported_errors;

my @errors = (
	"Duplicate entry '.*?' for key '.*?'",
	"Can't DROP '.*?'",
	"Duplicate key name '.*?'",
	"Duplicate column name '.*?'",
	"Record has changed since last read in table '.*?'",
	"savepoint does not exist",
	"'.*?' doesn't exist",
	" .*? does not exist",
	"'.*?' already exists",
	"Unknown database '.*?'",
	"Unknown table '.*?'",
	"Unknown column '.*?'",
	"Column '.*?' specified twice",
	"Column '.*?' cannot be null",
	"Duplicate partition name .*?",
	"Tablespace '.*?' not empty",
	"Tablespace '.*?' already exists",
	"Tablespace data file '.*?' already exists",
	"Can't find file: '.*?'",
	"Table '.*?' already exists",
	"You can't specify target table '.*?' for update",
	"Illegal mix of collations .*?, .*?, .*? for operation '.*?'",
	"Illegal mix of collations .*? and .*? for operation '.*?'",
	"Invalid .*? character string: '.*?'",
	"This version of Drizzle doesn't yet support '.*?'",
	"PROCEDURE .*? already exists",
	"FUNCTION .*? already exists",
	"'.*?' isn't in GROUP BY",
	"non-grouping field '.*?' is used in HAVING clause",
	"Table has no partition for value .*?"
);

my @patterns = map { qr{$_}i } @errors;

use constant EXECUTOR_DRIZZLE_AUTOCOMMIT => 10;

#
# Column positions for SHOW SLAVES
# 

use constant SLAVE_INFO_HOST => 1;
use constant SLAVE_INFO_PORT => 2;

#
# Drizzle status codes
#

# Syntax error

use constant	ER_PARSE_ERROR		=> 1064;
use constant	ER_SYNTAX_ERROR		=> 1149;

# Semantic errors

use constant	ER_UPDATE_TABLE_USED	=> 1093;
use constant	ER_BAD_FIELD_ERROR	=> 1054;
use constant	ER_NO_SUCH_TABLE	=> 1146;
use constant	ER_BAD_TABLE_ERROR	=> 1051;
use constant 	ER_CANT_DROP_FIELD_OR_KEY	=> 1091;
use constant	ER_FIELD_SPECIFIED_TWICE	=> 1110;
use constant	ER_MULTIPLE_PRI_KEY	=> 1068;
use constant	ER_DUP_FIELDNAME	=> 1060;
use constant	ER_DUP_KEYNAME		=> 1061;
use constant	ER_SAME_NAME_PARTITION	=> 1517;
use constant	ER_PARTITION_WRONG_VALUES_ERROR	=> 1480;
use constant	ER_CANT_LOCK		=> 1015;
use constant	ER_TABLESPACE_EXIST	=> 1666;
use constant	ER_NO_SUCH_TABLESPACE	=> 1667;
use constant	ER_SP_DOES_NOT_EXIST	=> 1305;
use constant	ER_TABLESPACE_NOT_EMPTY	=> 1671;
use constant	ER_BAD_DB_ERROR		=> 1049;
use constant	ER_PARTITION_MGMT_ON_NONPARTITIONED	=> 1505;
use constant	ER_UNKNOWN_SYSTEM_VARIABLE	=> 1193;
use constant	ER_VAR_CANT_BE_READ	=> 1233;
use constant	ER_TRG_DOES_NOT_EXIST	=> 1360;
use constant	ER_NO_DB_ERROR		=> 1046;
use constant	ER_BAD_NULL_ERROR	=> 1048;
use constant	ER_TABLE_EXISTS_ERROR	=> 1050;
use constant	ER_STMT_NOT_ALLOWED_IN_SF_OR_TRG	=> 1336;
use constant	ER_NOT_SUPPORTED_YET	=> 1235;
use constant	ER_STORED_FUNCTION_PREVENTS_SWITCH_BINLOG_FORMAT	=> 1560;
use constant	ER_EVENT_INTERVAL_NOT_POSITIVE_OR_TOO_BIG	=> 1542;
use constant	ER_COMMIT_NOT_ALLOWED_IN_SF_OR_TRG => 1422;
use constant	ER_CANNOT_USER		=> 1396;
use constant	ER_CHECK_NOT_IMPLEMENTED=> 1178;
use constant	ER_CANT_AGGREGATE_2COLLATIONS	=> 1267;
use constant	ER_CANT_AGGREGATE_3COLLATIONS	=> 1270;
use constant	ER_CANT_AGGREGATE_NCOLLATIONS 	=> 1271;
use constant	ER_INVALID_CHARACTER_STRING	=> 1300;
use constant	ER_SP_ALREADY_EXISTS		=> 1304;
use constant	ER_EVENT_ALREADY_EXISTS		=> 1537;
use constant	ER_TRG_ALREADY_EXISTS		=> 1359;
use constant	ER_WRONG_FIELD_WITH_GROUP	=> 1055;
use constant	ER_NON_GROUPING_FIELD_USED	=> 1463;

use constant	ER_DROP_PARTITION_NON_EXISTENT		=> 1507;
use constant	ER_DROP_LAST_PARTITION			=> 1508;
use constant	ER_COALESCE_ONLY_ON_HASH_PARTITION	=> 1509;
use constant	ER_REORG_HASH_ONLY_ON_SAME_NO		=> 1510;
use constant	ER_REORG_NO_PARAM_ERROR			=> 1511;
use constant	ER_ONLY_ON_RANGE_LIST_PARTITION		=> 1512;
use constant	ER_NO_PARTITION_FOR_GIVEN_VALUE		=> 1526;
use constant	ER_PARTITION_MAXVALUE_ERROR		=> 1481;
use constant	ER_WRONG_PARTITION_NAME			=> 1567;

use constant	ER_UNKNOWN_KEY_CACHE			=> 1284;


# Transaction errors

use constant	ER_LOCK_DEADLOCK	=> 1213;
use constant	ER_LOCK_WAIT_TIMEOUT	=> 1205;
use constant	ER_CHECKREAD		=> 1020;
use constant	ER_DUP_KEY		=> 1022;
use constant	ER_DUP_ENTRY		=> 1062;

# Storage engine failures

use constant	ER_GET_ERRNO		=> 1030;

# Database corruption

use constant	ER_CRASHED_ON_USAGE	=> 1194;
use constant	ER_NOT_KEYFILE		=> 1034;
use constant	ER_UNEXPECTED_EOF	=> 1039;
use constant	ER_SP_PROC_TABLE_CORRUPT=> 1457;
# Backup

use constant	ER_BACKUP_SEND_DATA	=> 1661;

# Out of disk space, quotas, etc.

use constant	ER_RECORD_FILE_FULL     => 1114;
use constant	ER_DISK_FULL            => 1021;
use constant	ER_OUTOFMEMORY		=> 1037;
use constant	ER_CON_COUNT_ERROR	=> 1040;
use constant	ER_OUT_OF_RESOURCES	=> 1041;
use constant	ER_CANT_CREATE_THREAD	=> 1135;
use constant	ER_STACK_OVERRUN	=> 1119;

use constant   ER_SERVER_SHUTDOWN      => 1053;

my %err2type = (
	ER_GET_ERRNO()		=> STATUS_SEMANTIC_ERROR,

	ER_PARSE_ERROR()	=> STATUS_SYNTAX_ERROR,
	ER_SYNTAX_ERROR()	=> STATUS_SYNTAX_ERROR,

	ER_UPDATE_TABLE_USED()	=> STATUS_SEMANTIC_ERROR,
	ER_NO_SUCH_TABLE()	=> STATUS_SEMANTIC_ERROR,
	ER_BAD_TABLE_ERROR()	=> STATUS_SEMANTIC_ERROR,
	ER_BAD_FIELD_ERROR()	=> STATUS_SEMANTIC_ERROR,
	ER_CANT_DROP_FIELD_OR_KEY()	=> STATUS_SEMANTIC_ERROR,
	ER_FIELD_SPECIFIED_TWICE()	=> STATUS_SEMANTIC_ERROR,
	ER_MULTIPLE_PRI_KEY()	=> STATUS_SEMANTIC_ERROR,
	ER_DUP_FIELDNAME()	=> STATUS_SEMANTIC_ERROR,
	ER_DUP_KEYNAME()	=> STATUS_SEMANTIC_ERROR,
	ER_SAME_NAME_PARTITION()=> STATUS_SEMANTIC_ERROR,
	ER_PARTITION_WRONG_VALUES_ERROR() => STATUS_SEMANTIC_ERROR,
	ER_CANT_LOCK()		=> STATUS_SEMANTIC_ERROR,
	ER_TABLESPACE_EXIST()	=> STATUS_SEMANTIC_ERROR,
	ER_NO_SUCH_TABLESPACE()	=> STATUS_SEMANTIC_ERROR,
	ER_SP_DOES_NOT_EXIST()	=> STATUS_SEMANTIC_ERROR,
	ER_TABLESPACE_NOT_EMPTY()	=> STATUS_SEMANTIC_ERROR,
	ER_BAD_DB_ERROR()	=> STATUS_SEMANTIC_ERROR,
	ER_PARTITION_MGMT_ON_NONPARTITIONED()	=> STATUS_SEMANTIC_ERROR,
	ER_UNKNOWN_SYSTEM_VARIABLE() => STATUS_SEMANTIC_ERROR,
	ER_VAR_CANT_BE_READ()	=> STATUS_SEMANTIC_ERROR,
	ER_TRG_DOES_NOT_EXIST() => STATUS_SEMANTIC_ERROR,
	ER_NO_DB_ERROR()	=> STATUS_SEMANTIC_ERROR,
	ER_BAD_NULL_ERROR()	=> STATUS_SEMANTIC_ERROR,
	ER_TABLE_EXISTS_ERROR() => STATUS_SEMANTIC_ERROR,
	ER_STMT_NOT_ALLOWED_IN_SF_OR_TRG() => STATUS_SEMANTIC_ERROR,
	ER_NOT_SUPPORTED_YET()	=> STATUS_SEMANTIC_ERROR,
	ER_STORED_FUNCTION_PREVENTS_SWITCH_BINLOG_FORMAT() => STATUS_SEMANTIC_ERROR,
	ER_EVENT_INTERVAL_NOT_POSITIVE_OR_TOO_BIG() => STATUS_SEMANTIC_ERROR,
	ER_COMMIT_NOT_ALLOWED_IN_SF_OR_TRG() => STATUS_SEMANTIC_ERROR,
	ER_CANNOT_USER() => STATUS_SEMANTIC_ERROR,
	ER_CHECK_NOT_IMPLEMENTED() => STATUS_SEMANTIC_ERROR,
	ER_CANT_AGGREGATE_2COLLATIONS() => STATUS_SEMANTIC_ERROR,
	ER_CANT_AGGREGATE_3COLLATIONS() => STATUS_SEMANTIC_ERROR,
	ER_CANT_AGGREGATE_NCOLLATIONS() => STATUS_SEMANTIC_ERROR,
	ER_INVALID_CHARACTER_STRING()	=> STATUS_SEMANTIC_ERROR,
	ER_SP_ALREADY_EXISTS() 		=> STATUS_SEMANTIC_ERROR,
	ER_EVENT_ALREADY_EXISTS()	=> STATUS_SEMANTIC_ERROR,
	ER_TRG_ALREADY_EXISTS()		=> STATUS_SEMANTIC_ERROR,
	ER_WRONG_FIELD_WITH_GROUP()	=> STATUS_SEMANTIC_ERROR,
	ER_NON_GROUPING_FIELD_USED()	=> STATUS_SEMANTIC_ERROR,

	ER_DROP_LAST_PARTITION()		=> STATUS_SEMANTIC_ERROR,
	ER_COALESCE_ONLY_ON_HASH_PARTITION()	=> STATUS_SEMANTIC_ERROR,
	ER_REORG_HASH_ONLY_ON_SAME_NO()		=> STATUS_SEMANTIC_ERROR,
	ER_REORG_NO_PARAM_ERROR()		=> STATUS_SEMANTIC_ERROR,
	ER_ONLY_ON_RANGE_LIST_PARTITION()	=> STATUS_SEMANTIC_ERROR,
	ER_NO_PARTITION_FOR_GIVEN_VALUE()	=> STATUS_SEMANTIC_ERROR,
	ER_DROP_PARTITION_NON_EXISTENT()	=> STATUS_SEMANTIC_ERROR,
	ER_PARTITION_MAXVALUE_ERROR()		=> STATUS_SEMANTIC_ERROR,
	ER_WRONG_PARTITION_NAME()		=> STATUS_SEMANTIC_ERROR,

	ER_UNKNOWN_KEY_CACHE()	=> STATUS_SEMANTIC_ERROR,

	ER_LOCK_DEADLOCK()	=> STATUS_TRANSACTION_ERROR,
	ER_LOCK_WAIT_TIMEOUT()	=> STATUS_TRANSACTION_ERROR,
	ER_CHECKREAD()		=> STATUS_TRANSACTION_ERROR,
	ER_DUP_KEY()		=> STATUS_TRANSACTION_ERROR,
	ER_DUP_ENTRY()		=> STATUS_TRANSACTION_ERROR,
	
	ER_NOT_KEYFILE()	=> STATUS_DATABASE_CORRUPTION,
	ER_CRASHED_ON_USAGE()	=> STATUS_DATABASE_CORRUPTION,
	ER_UNEXPECTED_EOF()	=> STATUS_DATABASE_CORRUPTION,
	ER_SP_PROC_TABLE_CORRUPT() => STATUS_DATABASE_CORRUPTION,

	ER_BACKUP_SEND_DATA()	=> STATUS_BACKUP_FAILURE,

	ER_CANT_CREATE_THREAD()	=> STATUS_ENVIRONMENT_FAILURE,
	ER_OUT_OF_RESOURCES()	=> STATUS_ENVIRONMENT_FAILURE,
	ER_CON_COUNT_ERROR()	=> STATUS_ENVIRONMENT_FAILURE,
	ER_RECORD_FILE_FULL()   => STATUS_ENVIRONMENT_FAILURE,
	ER_DISK_FULL()          => STATUS_ENVIRONMENT_FAILURE,
	ER_OUTOFMEMORY()	=> STATUS_ENVIRONMENT_FAILURE,
	ER_STACK_OVERRUN()	=> STATUS_ENVIRONMENT_FAILURE,

	ER_SERVER_SHUTDOWN()    => STATUS_SERVER_KILLED
);

my %caches;
	
sub init {
	my $executor = shift;
	my $dbh = DBI->connect($executor->dsn(), undef, undef, {
		PrintError => 0,
		RaiseError => 0,
		AutoCommit => 1
	} );

	if (not defined $dbh) {
		say("connect() to dsn ".$executor->dsn()." failed: ".$DBI::errstr);
		return STATUS_ENVIRONMENT_FAILURE;
	}

	$executor->setDbh($dbh);

	say("Executor initialized, id ".$executor->id());

	return STATUS_OK;
}

sub execute {
	my ($executor, $query, $silent) = @_;

	my $dbh = $executor->dbh();

	return GenTest::Result->new( query => $query, status => STATUS_UNKNOWN_ERROR ) if not defined $dbh;

	if (
		(not defined $executor->[EXECUTOR_DRIZZLE_AUTOCOMMIT]) &&
		(
			($query =~ m{^\s*start transaction}io) ||
			($query =~ m{^\s*begin}io) 
		)
	) {	
		$dbh->do("SET AUTOCOMMIT=OFF");
		$executor->[EXECUTOR_DRIZZLE_AUTOCOMMIT] = 0;
	}

	my $start_time = Time::HiRes::time();
	my $sth = $dbh->prepare($query);

	if (not defined $sth) {			# Error on PREPARE
		my $errstr = $executor->normalizeError($sth->errstr());
		$executor->[EXECUTOR_ERROR_COUNTS]->{$errstr}++ if $executor->debug() && !$silent;
		return GenTest::Result->new(
			query		=> $query,
			status		=> $executor->getStatusFromErr($dbh->err()) || STATUS_UNKNOWN_ERROR,
			err		=> $dbh->err(),
			errstr	 	=> $dbh->errstr(),
			sqlstate	=> $dbh->state(),
			start_time	=> $start_time,
			end_time	=> Time::HiRes::time()
		);
	}

	my $affected_rows = $sth->execute();
	my $end_time = Time::HiRes::time();

	my $err = $sth->err();
	my $result;
        if ($executor->debug()) {
                say("Running Query--> $query");
        }

	if (defined $err) {			# Error on EXECUTE
		my $err_type = $err2type{$err};

		if (
			($err_type == STATUS_SYNTAX_ERROR) ||
			($err_type == STATUS_SEMANTIC_ERROR) ||
			($err_type == STATUS_TRANSACTION_ERROR)
		) {
			my $errstr = $executor->normalizeError($sth->errstr());
			$executor->[EXECUTOR_ERROR_COUNTS]->{$errstr}++ if $executor->debug() && !$silent;
			if (not defined $reported_errors{$errstr}) {
				say("Query: $query failed: $err $errstr. Further errors of this kind will be suppressed.") if !$silent;
				$reported_errors{$errstr}++;
			}
		} else {
			$executor->[EXECUTOR_ERROR_COUNTS]->{$sth->errstr()}++ if $executor->debug() && !$silent;
			say("Query: $query failed: $err ".$sth->errstr()) if !$silent;
		}

		$result = GenTest::Result->new(
			query		=> $query,
			status		=> $err2type{$err} || STATUS_UNKNOWN_ERROR,
			err		=> $err,
			errstr		=> $sth->errstr(),
			sqlstate	=> $sth->state(),
			start_time	=> $start_time,
			end_time	=> $end_time
		);
	} elsif ((not defined $sth->{NUM_OF_FIELDS}) || ($sth->{NUM_OF_FIELDS} == 0)) {
		$result = GenTest::Result->new(
			query		=> $query,
			status		=> STATUS_OK,
			affected_rows	=> $affected_rows,
			start_time	=> $start_time,
			end_time	=> $end_time
		);
		$executor->[EXECUTOR_ERROR_COUNTS]->{'(no error)'}++ if $executor->debug() && !$silent;
	} else {
		#
		# We do not use fetchall_arrayref() due to a memory leak
		# We also copy the row explicitly into a fresh array
		# otherwise the entire @data array ends up referencing row #1 only
		#
		my @data;
		while (my $row = $sth->fetchrow_arrayref()) {
			my @row = @$row;
			push @data, \@row;
		}	

		$result = GenTest::Result->new(
			query		=> $query,
			status		=> STATUS_OK,
			affected_rows 	=> $affected_rows,
			data		=> \@data,
			start_time	=> $start_time,
			end_time	=> $end_time
		);

		$executor->[EXECUTOR_ERROR_COUNTS]->{'(no error)'}++ if $executor->debug() && !$silent;
	}

	$sth->finish();

	if ($sth->{drizzle_warning_count} > 0) {
		my $warnings = $dbh->selectcol_arrayref("SHOW WARNINGS");
		$result->setWarnings($warnings);
	}

	if (
		($executor->debug()) &&
		($query =~ m{^\s*select}sio) &&
		(!$silent)
	) {
		$executor->explain($query);
		my $row_group = $sth->rows() > 100 ? '>100' : ($sth->rows() > 10 ? ">10" : sprintf("%5d",$sth->rows()) );
		$executor->[EXECUTOR_ROW_COUNTS]->{$row_group}++;
	}

	return $result;
}

#
# Run EXPLAIN on the query in question, recording all notes in the EXPLAIN's Extra field into the statistics
#

sub id {
	my $executor = shift;

	# if no ID string has been defined yet, define one.

	if ($executor->SUPER::id() eq '') {
		my $dbh = $executor->dbh();
		my $version = $dbh->selectrow_array("SELECT VERSION()");

		my @capabilities;

		push @capabilities, "master" if $dbh->selectrow_array("SHOW SLAVE HOSTS");
		push @capabilities, "slave" if $dbh->selectrow_array("SHOW SLAVE STATUS");
		push @capabilities, "no_semijoin" if $dbh->selectrow_array('SELECT @@optimizer_switch') =~ m{no_semijoin}sio;
		push @capabilities, "no_materialization" if $dbh->selectrow_array('SELECT @@optimizer_switch') =~ m{no_materialization}sio;
		push @capabilities, "mo_mrr" if $dbh->selectrow_array('SELECT @@optimizer_use_mrr') eq '0';
		push @capabilities, "no_condition_pushdown" if $dbh->selectrow_array('SELECT @@engine_condition_pushdown') eq '0';
		$executor->setId(ref($executor)." ".$version." (".join('; ', @capabilities).")");
	}
	
	# Pass the call back to the parent class. It will respond with the id that was (just) defined.

	return $executor->SUPER::id();
}

sub version {
	my $executor = shift;
	my $dbh = $executor->dbh();
	return $dbh->selectrow_array("SELECT VERSION()");
}

sub slaveInfo {
	my $executor = shift;
	my $slave_info = $executor->dbh()->selectrow_arrayref("SHOW SLAVE HOSTS");
	return ($slave_info->[SLAVE_INFO_HOST], $slave_info->[SLAVE_INFO_PORT]);
}

sub masterStatus {
	my $executor = shift;
	return $executor->dbh()->selectrow_array("SHOW MASTER STATUS");
}

sub explain {
	my ($executor, $query) = @_;
	my $explain_output = $executor->dbh()->selectall_arrayref("EXPLAIN $query");
	my @explain_fragments;
	foreach my $explain_row (@$explain_output) {
		push @explain_fragments, "select_type: ".($explain_row->[1] || '(empty)');

		push @explain_fragments, "type: ".($explain_row->[3] || '(empty)');

		foreach my $extra_item (split('; ', ($explain_row->[9] || '(empty)')) ) {
			$extra_item =~ s{0x.*?\)}{%d\)}sgio;
			$extra_item =~ s{PRIMARY|[a-z_]+_key}{%s}sgio;
			push @explain_fragments, "extra: ".$extra_item;
		}
	}
	
	foreach my $explain_fragment (@explain_fragments) {
		$executor->[EXECUTOR_EXPLAIN_COUNTS]->{$explain_fragment}++;
		if ($executor->[EXECUTOR_EXPLAIN_COUNTS]->{$explain_fragment} > RARE_QUERY_THRESHOLD) {
			delete $executor->[EXECUTOR_EXPLAIN_QUERIES]->{$explain_fragment};
		} else {
			push @{$executor->[EXECUTOR_EXPLAIN_QUERIES]->{$explain_fragment}}, $query;
		}
	}

}

sub DESTROY {
	my $executor = shift;
	if ($executor->debug()) {
		say("Statistics for Executor ".$executor->dsn());
		use Data::Dumper;
		$Data::Dumper::Sortkeys = 1;
		say("Rows returned:");
		print Dumper $executor->[EXECUTOR_ROW_COUNTS];
		say("Explain items:");
		print Dumper $executor->[EXECUTOR_EXPLAIN_COUNTS];
		say("Errors:");
		print Dumper $executor->[EXECUTOR_ERROR_COUNTS];
		say("Rare EXPLAIN items:");
		print Dumper $executor->[EXECUTOR_EXPLAIN_QUERIES];
	}
	$executor->dbh()->disconnect();
}

sub databases {
	my $executor = shift;

	return [] if not defined $executor->dbh();

	$caches{databases} = $executor->dbh()->selectcol_arrayref("SHOW DATABASES") if not exists $caches{databases};
	return $caches{databases};
}

sub tables {
	my ($executor, $database) = @_;

	return [] if not defined $executor->dbh();

	my $cache_key = join('-', ('tables', $database));
	my $query = "SHOW TABLES ".(defined $database ? "FROM $database" : "");
	$caches{$cache_key} = $executor->dbh()->selectcol_arrayref($query) if not exists $caches{$cache_key};
	return $caches{$cache_key};
}

sub fields {
	my ($executor, $table, $database) = @_;
	
	return [] if not defined $executor->dbh();

	my $cache_key = join('-', ('fields', $table, $database));
	my $query = defined $table ? "SHOW FIELDS FROM $table" : "SHOW FIELDS FROM ".$executor->tables($database)->[0];
	$query .= " FROM $database" if defined $database;

	$caches{$cache_key} = $executor->dbh()->selectcol_arrayref($query) if not exists $caches{$cache_key};

	return $caches{$cache_key};
}

sub fieldsNoPK {
	my ($executor, $table, $database) = @_;

	return [] if not defined $executor->dbh();

	my $cache_key = join('-', ('fields_no_pk', $table, $database));
	$caches{$cache_key} = $executor->dbh()->selectcol_arrayref("
		SELECT COLUMN_NAME
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE TABLE_NAME = '".(defined $table ? $table : $executor->tables($database)->[0] )."'
		AND TABLE_SCHEMA = ".(defined $database ? "'$database'" : 'DATABASE()' )."
		AND COLUMN_KEY != 'PRI'
	");

	return $caches{$cache_key};
}

sub fieldsIndexed {
	my ($executor, $table, $database) = @_;

	return [] if not defined $executor->dbh();

	my $cache_key = join('-', ('fields_indexed', $table, $database));

	$caches{$cache_key} = $executor->dbh()->selectcol_arrayref("
		SHOW INDEX
		FROM ".(defined $table ? $table : $executor->tables($database)->[0]).
		(defined $database ? " FROM $database " : "")
	, { Columns=>[5] }) if not defined $caches{$cache_key};

	return $caches{$cache_key};
}

sub collations {
	my $executor = shift;

	return [] if not defined $executor->dbh();

	return $executor->dbh()->selectcol_arrayref("
		SELECT COLLATION_NAME
		FROM INFORMATION_SCHEMA.COLLATIONS
	");
}

sub charsets {
	my $executor = shift;

	return [] if not defined $executor->dbh();

	return $executor->dbh()->selectcol_arrayref("
		SELECT DISTINCT CHARACTER_SET_NAME
		FROM INFORMATION_SCHEMA.COLLATIONS
	");
}

sub database {
	my $executor = shift;

	return undef if not defined $executor->dbh();

	return $executor->dbh()->selectrow_array("SELECT DATABASE()");
}

sub errorType {
	return undef if not defined $_[0];
	return $err2type{$_[0]} || STATUS_UNKNOWN_ERROR ;
}

sub normalizeError {
	my ($executor, $errstr) = @_;

	$errstr =~ s{\d+}{%d}sgio if $errstr !~ m{from storage engine}sio; # Make all errors involving numbers the same, e.g. duplicate key errors

	foreach my $i (0..$#errors) {
		last if $errstr =~ s{$patterns[$i]}{$errors[$i]}si;
	}

	$errstr =~ s{\.\*\?}{%s}sgio;

	return $errstr;
}

1;
