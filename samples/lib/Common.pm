package Common;

use strict;
use warnings;
use MHA::DBHelper;
use Readonly;

use MyDNS;

Readonly my $MYDNS => MyDNS->new();

sub master_takeover_mydns {
  my $command   = shift;
  my $orig_host = shift;
  my $orig_ip   = shift;
  my $new_host  = shift;
  my $new_ip    = shift;

  eval {
    if ($command eq "start") {
      my $dbh;

      $dbh = $MYDNS->get_db_handle();

      print "Updating MyDNS..\n";
      _master_takeover($dbh, $orig_ip, $orig_host, $new_ip, $new_host);
      $dbh->commit();
      print " ok.\n";

      $dbh->disconnect();

    }
    elsif ($command eq "stop") {
      # do nothing
    }
    else {
      die "Invalid command $command\n";
    }
  };
  if ($@) {
    die $@;
  }
}

sub _master_takeover {
  my $dbh              = shift;
  my $orig_master_ip   = shift;
  my $orig_master_host = shift;
  my $new_master_ip    = shift;
  my $new_master_host  = shift;

  print "_master_takeover..\n";

}

1;
