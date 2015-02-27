package Common;

use strict;
use warnings;
use MHA::DBHelper;
use Readonly;

use MyDNS;
use Data::Dumper;

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

      #_master_takeover($dbh, $orig_ip, $orig_host, $new_ip, $new_host);
      _rob_master_takeover($dbh, $orig_ip, $orig_host, $new_ip, $new_host);
      
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

sub _get_name_prefix {
  my $name = shift;

  if ($name =~ m{^(.+)-(a|b|c)$}) { #match RoB servers
    return $1;
  } elsif ($name =~ m{^([a-zA-Z\-]+)(\d+)$}) { #match test servers
    return $1;
  } else {
    return "";
  }
}

sub _check_result {
  my $dbh           = shift;
  my $affected_rows = shift;

  if (not defined($affected_rows)) {
    print "Unexpected error happened from MyDNS.\n";
    $dbh->rollback();
    die;
  }
  elsif ($affected_rows == 0) {
    # no error
    print "No rows matched on MyDNS.\n";
  }
  else {
    print "$affected_rows row(s) were affected.\n";
  }
}

sub _delete_entry_iphost {
  my $dbh  = shift;
  my $ip   = shift;
  my $host = shift;

  my $sth  = $dbh->prepare(<<'SQL');
DELETE FROM rr WHERE name=? AND data=? AND zone='1'
SQL
  printf "Executing delete: DELETE FROM rr WHERE name='%s' AND data='%s' AND zone='1'\n", $host, $ip;
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
UPDATE rr SET data=?, name=? WHERE data=? AND name=? AND zone='1'
SQL
  printf "Executing update: UPDATE rr SET data='%s', name='%s' WHERE data='%s' AND name='%s' AND zone='1'\n",
    $new_ip, $new_host, $orig_ip, $orig_host;
  my $affected_rows = $sth->execute($new_ip, $new_host, $orig_ip, $orig_host);
  _check_result($dbh, $affected_rows);
  print "Updated MyDNS entries successfully.\n";
}

sub _update_entry_new_master {
  my $dbh       = shift;
  my $new_ip    = shift;
  my $new_host  = shift;
  my $orig_ip   = shift;
  my $orig_host = shift;

  my $sth = $dbh->prepare(<<'SQL');
UPDATE rr SET data=?, type='CNAME' WHERE (data=? OR data=?) AND name REGEXP '.+-(m)' AND zone='1' 
SQL
  printf "Executing update: UPDATE rr SET data='%s', type='CNAME' WHERE (data='%s' OR data='%s') AND name REGEXP '.+-(m)' AND zone='1'\n",
    $new_host, $orig_ip, $orig_host;
  my $affected_rows = $sth->execute($new_host, $orig_ip, $orig_host);
  _check_result($dbh, $affected_rows);
  print "Updated MyDNS entries successfully.\n";
}

sub _update_entry_old_master {
  my $dbh       = shift;
  my $new_ip    = shift;
  my $new_host  = shift;
  my $orig_ip   = shift;
  my $orig_host = shift;

  my $sth = $dbh->prepare(<<'SQL');
UPDATE rr SET data=?, type='CNAME' WHERE (data=? OR data=?) AND name REGEXP '.+-(s|bk)' AND zone='1' 
SQL
  printf "Executing update: UPDATE rr SET data='%s', type='CNAME' WHERE (data='%s' OR data='%s') AND name REGEXP '.+-(s|bk)' AND zone='1'\n",
    $orig_host, $new_ip, $new_host;
  my $affected_rows = $sth->execute($orig_host, $new_ip, $new_host);
  _check_result($dbh, $affected_rows);
  print "Updated MyDNS entries successfully.\n";
}

sub _get_remaining_records {
  my $dbh         = shift;
  my $prefix_name = shift;

  my $sth = $dbh->prepare(<<'SQL');
SELECT name, data FROM rr WHERE name LIKE ? AND name REGEXP '.+-(m|s|bk)' AND INET_ATON(data) IS NOT NULL AND type='A'
SQL
  printf "Select: SELECT name, data FROM rr WHERE name LIKE '%s' AND name REGEXP '.+-(m|s|bk)' AND INET_ATON(data) IS NOT NULL AND type='A'\n",
    "$prefix_name%";
  my $execute = $sth->execute("$prefix_name%");

  return $sth->fetchall_arrayref();
}

sub _get_host_list {
  my $dbh         = shift;
  my $prefix_name = shift;

  my $host_list = {};

  my $sth = $dbh->prepare(<<'SQL');
SELECT name, data FROM rr WHERE name LIKE ? AND NOT( name REGEXP '.+-(m|s|bk)' ) AND INET_ATON(data) IS NOT NULL AND type='A'
SQL
  printf "Select: SELECT name, data FROM rr WHERE name LIKE '%s' AND NOT( name REGEXP '.+-(m|s|bk)' ) AND INET_ATON(data) IS NOT NULL AND type='A'\n",
    "$prefix_name%";
  my $execute = $sth->execute("$prefix_name%");

  while (my ($name, $ip) = $sth->fetchrow_array) {
    $host_list->{$ip} = $name;
  }

  return $host_list;
}

sub _replace_ip_by_host {
  my $dbh      = shift;
  my $name     = shift;
  my $ip       = shift;
  my $new_host = shift;

  my $sth = $dbh->prepare(<<'SQL');
UPDATE rr SET data=?, type='CNAME' WHERE name=? AND data=? AND name REGEXP '.+-(m|s|bk)' AND zone='1' 
SQL
  printf "Executing update: UPDATE rr SET data='%s', type='CNAME' WHERE name='%s' AND data='%s' AND name REGEXP '.+-(m|s|bk)' AND zone='1'\n",
    $new_host, $name, $ip;
  my $affected_rows = $sth->execute($new_host, $name, $ip);
  _check_result($dbh, $affected_rows);
  print "Updated MyDNS entries successfully.\n";
}

sub _master_takeover {
  my $dbh              = shift;
  my $orig_master_ip   = shift;
  my $orig_master_host = shift;
  my $new_master_ip    = shift;
  my $new_master_host  = shift;

  print "Deleting existing new master's MyDNS entries $new_master_host($new_master_ip)..\n";
  _delete_entry_iphost($dbh, $new_master_ip, $new_master_host);
  print "Updating MyDNS entries from prev master $orig_master_host($orig_master_ip) to new master $new_master_host($new_master_ip)..\n";
  _update_entry_iphost($dbh, $new_master_ip, $new_master_host, $orig_master_ip, $orig_master_host);
}

sub _rob_master_takeover {
  my $dbh              = shift;
  my $orig_master_ip   = shift;
  my $orig_master_host = shift;
  my $new_master_ip    = shift;
  my $new_master_host  = shift;

  print "Updating MyDNS entries from prev master $orig_master_host($orig_master_ip) to new master $new_master_host($new_master_ip)..\n";
  _update_entry_new_master($dbh, $new_master_ip, $new_master_host, $orig_master_ip, $orig_master_host);
  print "Updating MyDNS entries from new master $new_master_host($new_master_ip) to prev master $orig_master_host($orig_master_ip)..\n";
  _update_entry_old_master($dbh, $new_master_ip, $new_master_host, $orig_master_ip, $orig_master_host);

  print "Get prefix..\n";
  my $prefix_name = _get_name_prefix($new_master_host);
  print "prefix_name = $prefix_name\n";

  print "Get all host IPs..\n";
  my $host_list = _get_host_list($dbh, $prefix_name);

  print "Get remaining records..\n";
  my $records = _get_remaining_records($dbh, $prefix_name);

  foreach (@$records) {
    my $name = $_->[0];
    my $ip   = $_->[1];
    if (exists $host_list->{$ip}) {
      my $new_host = $host_list->{$ip};
      print ". Relace IP (A): $ip by hostname (CNAME): $new_host..\n";
      _replace_ip_by_host($dbh, $name, $ip, $new_host);
    }
  }

}


1;
