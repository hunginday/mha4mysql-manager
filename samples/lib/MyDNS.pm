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

#use DeNA::Conf::Common;
#use DeNA::Conf::DNSRR2;
#use DeNA::Utils;
#use Admin::Host;


sub new {
    my $class = shift;
    my %args = @_ == 1 ? %{ $_[0] } : @_;

    $args{conf} = 'DeNA/Conf/DNSRR2.pm' unless $args{conf};
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

    $args{region} or croak "not found region args";
    $args{mode} //= 'W';

    if (defined $self->{dbh}->{ $args{region} }
            and $self->{dbh}->{ $args{region} }->ping) {
        return $self->{dbh}->{ $args{region} };
    }

    my $timeout = $args{timeout} || 10;
    my $conf    = $DeNA::Conf::DNSRR2::CONF{regions}->{ $args{region} };

    my $dsn = sprintf("DBI:mysql:database=%s;host=%s;mysql_connect_timeout=%d;mysql_read_default_file=/etc/my.cnf;mysql_read_default_group=mysql;mysql_skip_secure_auth=1",
                      $conf->{db_name},
                      $conf->{db_host},
                      $timeout,
                     );
    debugf("dsn: %s", $dsn);
    my %credential = $args{mode} eq 'R'
        ? %DeNA::Conf::DB_MYDNS_R : %DeNA::Conf::DB_MYDNS_W;
    my $autocommit = $args{mode} eq 'R' ? 1 : 0;

    my $dbh = DBI->connect($dsn,
                           $credential{user},
                           $credential{password},
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
    return $self->{dbh}->{ $args{region} } = $dbh;
}


sub disconnect_all {
    my $self = shift;

    ### close all DB connection
    while (my($region, $dbh) = each %{ $self->{dbh} }) {
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
}


1;
