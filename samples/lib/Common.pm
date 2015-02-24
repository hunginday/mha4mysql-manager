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

sub _delete_entry_iphost {
  my $dbh  = shift;
  my $ip   = shift;
  my $host = shift;

  my $sth  = $dbh->prepare(<<'SQL');
DELETE FROM rr WHERE name=? AND data=? AND zone=1
SQL
  printf "Executing delete: DELETE FROM rr WHERE name='%s' AND data='%s' AND zone=1\n", $host, $ip;
  my $affected_rows = $sth->execute($host, $ip);
  _check_result($dbh, $affected_rows);
  print "Deleted MyDNS entries successfully.\n";
}

sub _update_entry_iphost {
  my $dbh       = shift;
  my $new_ip    = shift;
  my $new_host  = shift;
  my $orig_ip   = shift;
  my $orig_host = shift;

  my $sth = $dbh->prepare(<<'SQL');
UPDATE rr SET data=?, host=? WHERE data=? AND host=? AND zone=?
SQL
  printf "Executing update: UPDATE rr SET data='%s', host='%s' WHERE data='%s' AND host='%s' AND zone='%s'\n",
    $new_ip, $new_host, $orig_ip, $orig_host, $ZONE_ID;
  my $affected_rows = $sth->execute($new_ip, $new_host, $orig_ip, $orig_host, $ZONE_ID);
  _check_result($dbh, $affected_rows);
  print "Updated MyDNS entries successfully.\n";
}

sub _master_takeover {
  my $dbh              = shift;
  my $orig_master_ip   = shift;
  my $orig_master_host = shift;
  my $new_master_ip    = shift;
  my $new_master_host  = shift;

  print "_master_takeover..\n";
  print "Deleting existing new master's MyDNS entries $new_master_host($new_master_ip)..\n";
  _delete_entry_iphost($dbh, $new_master_ip, $new_master_host);
  print "Updating MyDNS entries from prev master $orig_master_host($orig_master_ip) to new master $new_master_host($new_master_ip)..\n";
  _update_entry_iphost( $dbh, $new_master_ip, $new_master_host, $orig_master_ip, $orig_master_host);

}

1;
