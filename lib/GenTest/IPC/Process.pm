package GenTest::IPC::Process;

if (windows()) {
    use threads;
}

## A Process is a placeholder for an object run in a separate process.
## The contract assumes that the objects constructor is run in the
## parent process and the fork is done in Process->start and then
## obect->run() is invoked.

use Data::Dumper;
use GenTest;

use strict;

my %processes;

sub new {
    my $class = shift;
    my $self = {};
    
    $self->{OBJECT} = shift;

    bless($self, $class);
    
    return $self;
}


sub start {
    my ($self, @args) = @_;

    if (windows()) {
	my $thr = threads->create(sub{$self->{OBJECT}->run(@args)});
	$thr->detach();
	$self->{PID}=$thr->tid();
	$processes{$thr->tid()} = $self->{OBJECT};
	say "".(ref $self->{OBJECT})."(".$thr->tid().") started\n";
    } else {
	my $pid = fork();
	if ($pid == 0 ) {
	    ## Forked process
	    $self->{PID}=$$;
	    $self->{OBJECT}->run(@args);
	    say "".(ref $self->{OBJECT})."($$) terminated normally\n";
	    exit 0;
	} else {
	    say "".(ref $self->{OBJECT})."($pid) started\n";
	    $self->{PID} = $pid;
	    $processes{$pid} = $self->{OBJECT};
	    return $pid;
	}
    }
}


sub childWait {
    my (@list) = @_;
    if (@list < 1) {
        while (1) {
            my $pid = wait();
            last if $pid < 0;
            print "".(ref $processes{$pid})."($pid) stopped with status $?\n";
        }
    } else {
        my %pids;
        map {$pids{$_}=1} @list;
        while ((keys %pids) > 0) {
            my $pid = wait();
            last if $pid < 0;
            print "".(ref $processes{$pid})."($pid) stopped with status $?\n";
            delete $pids{$pid} if exists $pids{$pid};
        }
    }
}

sub childWaitStatus {
    my ($max, @list) = @_;
    my $status = 0;
    if (@list < 1) {
        while (1) {
            my $pid = wait();
            last if $pid < 0;
            $status = $? if $status < $?;
            print "".(ref $processes{$pid})."($pid) stopped with status $?\n";
            last if $status >= $max;
        }
    } else {
        my %pids;
        map {$pids{$_}=1} @list;
        while ((keys %pids) > 0) {
            my $pid = wait();
            last if $pid < 0;
            $status = $? if $status < $?;
            print "".(ref $processes{$pid})."($pid) stopped with status $?\n";
            delete $pids{$pid} if exists $pids{$pid};
            last if $status >= $max;
        }
    }
}

sub kill {
    my ($self) = @_;
    
    if (windows()) {
        ## Not sure yet, but the thread will enevtually die dtogether
        ## with the main program
    } else {
        say "Kill ".(ref $processes{$self->{PID}})."(".$self->{PID}.")\n";
        kill(15, $self->{PID});
    }
}

1;

