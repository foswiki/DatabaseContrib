use v5.10;
use strict;

package DatabaseContribOOTests;

use DatabaseContribTestCommon;
our @ISA = qw( DatabaseContribTestCommon );

use strict;
use Foswiki;
use Foswiki::Func;
use File::Temp;
use Foswiki::Contrib::DatabaseContrib qw(:all);
use Data::Dumper;
use version;

sub test_connect {
    my $this = shift;

    my ( $dbc, $dbh );

    $this->assert_not_null(
        $dbc = Foswiki::Contrib::DatabaseContrib->new,
        "Failed to create a new DatabaseContrib object",
    );

    $this->assert_not_null(
        $dbh = $dbc->connect('message_board'),
        "Failed to connect to existing 'message_board' connection",
    );

    $this->assert_null(
        $dbh = $dbc->connect('non_existent'),
        "Failed: connection to 'non_existent' DB didn't return null",
    );
}

sub test_connected {
    my $this = shift;

    my ( $dbc, $dbh );

    $this->assert_not_null(
        $dbc = Foswiki::Contrib::DatabaseContrib->new,
        "Failed to create a new DatabaseContrib object",
    );

    $this->assert( !$dbc->connected('message_board'),
        "'message_board' must have been DISCONNECTED by this time" );

    $this->assert_not_null(
        $dbh = $dbc->connect('message_board'),
        "Failed to connect to existing 'message_board' connection",
    );

    $this->assert( $dbc->connected('message_board'),
        "'message_board' must have been CONNECTED by this time" );

    $dbc->disconnect;

    $this->assert( !$dbc->connected('message_board'),
        "'message_board' must have been DISCONNECTED again by this time" );
}

sub test_attributes {
    my $this = shift;

    my ( $dbc, $dbh );

    $this->assert_not_null(
        $dbc = Foswiki::Contrib::DatabaseContrib->new,
        "Failed to create a new DatabaseContrib object",
    );

    $this->assert_not_null(
        $dbh = $dbc->connect('message_board'),
        "Failed to connect to existing 'message_board' connection",
    );

    $this->assert_str_equals(
        "YES",
        $dbh->{some_attribute},
        "Expected some_attribute to be 'YES'"
    );

    $dbc->disconnect;

    $Foswiki::cfg{Extensions}{DatabaseContrib}{connections}{message_board}
      {driver_attributes}{some_attribute} = 0;

    # Reinitialize is needed because connection properties are being copied
    # once in module life cycle.
    $this->assert( $dbc->reinit, "Cannot reinitialize DatabaseContrib object" );

    $this->assert_not_null( $dbh = $dbc->connect('message_board'),
        "Failed to connect to 'message_board' connection" );

    $this->assert_num_equals(
        0,
        $dbh->{some_attribute},
        "Expected some_attribute to be 0"
    );

    $dbc->disconnect;
}

sub test_version {
    my $this = shift;

    my $required_ver = version->parse("v1.03_001");

    $this->assert(
        $Foswiki::Contrib::DatabaseContrib::VERSION == $required_ver,
"Module version mismatch, expect $required_ver, got $Foswiki::Contrib::DatabaseContrib::VERSION "
    );
}

sub test_permissions {
    my $this = shift;

    my $dbc;

    $this->assert_not_null(
        $dbc = Foswiki::Contrib::DatabaseContrib->new(
            acl_inheritance => {
                allow_query  => 'allow_do',
                allow_child1 => 'allow_query',
                allow_child2 => [ 'allow_child4', 'allow_do' ],
                allow_child3 => 'allow_child2',
                allow_child4 => 'allow_child3',
                allow_child5 => 'allow_child2',
            },
        ),
        "Failed to create a new DatabaseContrib object",
    );

    foreach my $bunch (qw(valid invalid)) {
        foreach my $access_type ( keys %{ $this->{check_pairs}{$bunch} } ) {
            foreach
              my $test_pair ( @{ $this->{check_pairs}{$bunch}{$access_type} } )
            {
                if ( $bunch eq 'valid' ) {
                    $this->assert(
                        $dbc->access_allowed(
                            'message_board', $test_pair->[1],
                            $access_type,    $test_pair->[0]
                        ),
"$bunch $access_type for $test_pair->[0] on $test_pair->[1] failed but has to conform the following rule: "
                          . $test_pair->[2],
                    );
                }
                else {
                    $this->assert(
                        !$dbc->access_allowed(
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
        $dbc->access_allowed(
            'sample_connection', 'Sandbox.DoTestTopic',
            'allow_query',       'JohnSmith'
        ),
"User shall be allowed for query when `allow_query' inherits from existing `allow_do' but is not defined for a connection",
    );
    $this->assert(
        !db_access_allowed(
            'sample_connection', 'Sandbox.QDummyTopic',
            'allow_query',       'JohnSmith'
        ),
"User shall not be allowed for query when `allow_query' inherits from existing `allow_do' but is not defined for a connection",
    );

}

sub test_usermap {
    my $this = shift;

    my $query = Unit::Request->new("");
    $this->createNewFoswikiSession( $Foswiki::cfg{AdminUserLogin}, $query );

    $Foswiki::cfg{Extensions}{DatabaseContrib}{connections}{sample_connection}
      {usermap} = [
        AdminGroup => {
            user     => "dbadmin",
            password => "admin_pass",
        },
        MightyAdmin => {
            user     => "madmin",
            password => "ma_pass",
        },
        DummyGroup => {
            user     => "dummy",
            password => "nopassword",
        },
        JohnSmith => {
            user     => "jsmith",
            password => "js_pass",
        },
      ];

    my $dbc;
    $this->assert_not_null(
        $dbc = Foswiki::Contrib::DatabaseContrib->new,
        "Failed to create a new DatabaseContrib object",
    );

    my ( $dbuser, $dbpass );

    ( $dbuser, $dbpass ) =
      $dbc->map2dbuser( "sample_connection", 'MightyAdmin' );

    # Must not be madmin/ma_pass because AdminGroup is defined first.
    $this->assert_equals( 'dbadmin',    $dbuser );
    $this->assert_equals( 'admin_pass', $dbpass );

    ( $dbuser, $dbpass ) = $dbc->map2dbuser( "sample_connection", 'JohnSmith' );

    $this->assert_equals( 'jsmith',  $dbuser );
    $this->assert_equals( 'js_pass', $dbpass );

    Foswiki::Func::addUserToGroup( 'JohnSmith', 'DummyGroup', 0 );

    # Now group shall override user's mapping because the group comes first in
    # the list.
    ( $dbuser, $dbpass ) = $dbc->map2dbuser( "sample_connection", 'JohnSmith' );

    $this->assert_equals( 'dummy',      $dbuser );
    $this->assert_equals( 'nopassword', $dbpass );

    $this->assert(
        Foswiki::Func::removeUserFromGroup( 'JohnSmith', 'DummyGroup' ),
        "Failed to remove user JohnSmith from DummyGroup"
    );

    # And it must map to the user again because he is not a group member
    # anymore.
    ( $dbuser, $dbpass ) = $dbc->map2dbuser( "sample_connection", 'JohnSmith' );

    $this->assert_equals( 'jsmith',  $dbuser );
    $this->assert_equals( 'js_pass', $dbpass );

    say STDERR "$dbuser, $dbpass";
}

1;
