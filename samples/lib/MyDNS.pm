package MyDNS;

use strict;
use warnings;
use 5.010_000;

our $VERSION = '0.01';

use Carp;
use DBI;
use Socket;
use Parallel::ForkManager;
use Log::Minimal env_debug => 'MYDNS_DEBUG';


sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{ $_[0] } : @_;

    $args{conf} = 'ConfigMyDNS.pm' unless $args{conf};
    eval { require $args{conf}; };
    $@ and croak "couldn't require $args{conf} ($@)";
    if ($args{conf} !~ m{^/} and exists $INC{ $args{conf} }) {
        $args{conf} = $INC{ $args{conf} };
    }
    debugf("conf: %s", $args{conf});

    bless \%args, $class;
}

# Not using DeNA::DA::getHandle:
# It's safer not to use D::D::getHandle in trying to update DNS records,
# since it refers to DNS
sub get_db_handle {
    my $self = shift;
    my %args = @_ == 1 ? %{ $_[0] } : @_;

    my $timeout = $args{timeout} || 10;
    my $conf    = $ConfigMyDNS::CONF;

    my $dsn = sprintf("DBI:mysql:database=%s;host=%s;mysql_connect_timeout=%d;mysql_read_default_file=/etc/my.cnf;mysql_read_default_group=mysql;mysql_skip_secure_auth=1",
                      $conf->{db_name},
                      $conf->{db_host},
                      $timeout,
                     );
    debugf("dsn: %s", $dsn);

    my $autocommit = 1;

    my $dbh = DBI->connect($dsn,
                           $conf->{db_user},
                           $conf->{db_pwd},
                           {
                               AutoCommit           => $autocommit,
                               PrintError           => 0,
                               RaiseError           => 1,
                               ShowErrorStatement   => 1,
                               AutoInactiveDestroy  => 1,
                               mysql_auto_reconnect => 0,
                           }) or croak "connect failed : " . $DBI::errstr;
    if ($dbh->{AutoCommit} != $autocommit) {
        croak "can't set AutoCommit=$autocommit : " . $DBI::errstr;
    }
    return $self->{dbh} = $dbh;
}

sub disconnect_all {
    my $self = shift;

    ### close all DB connection
    my $dbh = $self->{dbh};
    if ($dbh && $dbh->ping()) {
        eval {
            if (!$dbh->{AutoCommit}) {
                $dbh->rollback;
            }
            $dbh->disconnect;
        };
        if ($@) {
            warn "failed to close DBH for $region: $@";
        }
    }
}


1;
