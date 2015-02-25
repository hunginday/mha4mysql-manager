package Config;

use strict;
use warnings;

our $TTL_NORMAL = 180;
our $TTL_SHORT  = 3;

our %CONF = (
    db_host   => 'infra-hanoi-test04',
    db_name   => 'mydns',
    db_user   => 'mydns',
    db_pwd    => '@mydns',
);

1;
