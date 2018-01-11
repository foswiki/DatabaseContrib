use v5.10;
use strict;

package DatabaseContribTests;

use DatabaseContribTestCommon;
our @ISA = qw( DatabaseContribTestCommon );

use strict;
use Foswiki;
use Foswiki::Func;
use File::Temp;
use Foswiki::Contrib::DatabaseContrib qw(:all);
use Data::Dumper;
use version;

sub db_test_connect {
    my ( $this, $conname ) = @_;
    my $dbh = db_connect($conname);
    $this->assert_not_null( $dbh, "Failed: connection to $conname DB" );
    return $dbh;
}

sub test_permissions {
    my $this = shift;

    foreach my $bunch (qw(valid invalid)) {
        foreach my $access_type ( keys %{ $this->{check_pairs}{$bunch} } ) {
            foreach my $test_pair ( @{ $this->{check_pairs}{$bunch}{$access_type} } ) {
                if ( $bunch eq 'valid' ) {
                    $this->assert(
                        db_access_allowed(
                            'message_board', $test_pair->[1],
                            $access_type,    $test_pair->[0]
                        ),
"$bunch $access_type for $test_pair->[0] on $test_pair->[1] failed but has to conform the following rule: "
                          . $test_pair->[2],
                    );
                }
                else {
                    $this->assert(
                        !db_access_allowed(
                            'message_board', $test_pair->[1],
                            $access_type,    $test_pair->[0]
                        ),
"$bunch $access_type for $test_pair->[0] on $test_pair->[1] succeed but hasn't to because: "
                          . $test_pair->[2],
                    );
                }
            }
        }
    }

    # Check access when no allow_query at all.
    $this->assert(
        db_access_allowed(
            'sample_connection', 'Sandbox.DoTestTopic',
            'allow_query',       'JohnSmith'
        ),
"Connection allowed for query when no `allow_query' but `allow_do' is there",
    );
    $this->assert(
        !db_access_allowed(
            'sample_connection', 'Sandbox.QDummyTopic',
            'allow_query',       'JohnSmith'
        ),
"Connection no allowed for query when no `allow_query' but `allow_do' is there",
    );

}

sub test_connect {
    my $this = shift;

    my $dbh = $this->db_test_connect('message_board');

    $this->assert_null(
        $dbh = db_connect('non_existent'),
        'Failed: connection to non_existent DB',
    );

    db_disconnect;
}

sub test_connected {
    my $this = shift;

    # If a previous test fails it may leave a connection opened.
    db_disconnect;

    $this->assert( !db_connected('message_board'),
        "DB must not be connected at this point." );

    $this->db_test_connect('message_board');

    $this->assert( db_connected('message_board'),
        "DB must be in connected state now" );

    db_disconnect;
}

sub test_attributes {
    my $this = shift;

    my $dbh = $this->db_test_connect('message_board');

    $this->assert_str_equals(
        "YES",
        $dbh->{some_attribute},
        "Expected some_attribute to be 'YES'"
    );

    db_disconnect;

    $Foswiki::cfg{Extensions}{DatabaseContrib}{connections}{message_board}
      {driver_attributes}{some_attribute} = 0;

    # Reinitialize is needed because connection properties are being copied
    # once in module life cycle.
    db_init;

    $dbh = $this->db_test_connect('message_board');

    $this->assert_num_equals(
        0,
        $dbh->{some_attribute},
        "Expected some_attribute to be 0"
    );

    db_disconnect;
}

sub test_version {
    my $this = shift;

    my $required_ver = version->parse("v1.04.01");

    $this->assert(
        $Foswiki::Contrib::DatabaseContrib::VERSION == $required_ver,
"Module version mismatch, expect $required_ver, got $Foswiki::Contrib::DatabaseContrib::VERSION "
    );
}

sub test_glob {
    my $this = shift;

    my $rx = Foswiki::Contrib::DatabaseContrib::_glob2rx('Sandbox.*');
    $this->assert_equals('Sandbox\..*', $rx);

    my $rx = Foswiki::Contrib::DatabaseContrib::_glob2rx('*Sandbox.*');
    $this->assert_equals('.*Sandbox\..*', $rx);

    my $rx = Foswiki::Contrib::DatabaseContrib::_glob2rx('Sandbox.*Group');
    $this->assert_equals('Sandbox\..*Group', $rx);
}

1;
