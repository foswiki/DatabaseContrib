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

    my $required_ver = version->parse("v1.02_001");

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

    my %check_pairs = (
        valid => {
            allow_do => [
                [
                    qw(ScumBag AnyWeb.AnyTopic),
                    "Admins are allowed anywhere by default"
                ],
                [
                    qw(scum AnyWeb.AnyTopic),
                    "Admin by his short login is allowed anywhere by default"
                ],
                [
                    qw(JohnSmith Sandbox.DoForSelected),
                    "Individual user allowed for a topic"
                ],
                [
                    qw(DummyGuest Sandbox.DoDummyTopic),
                    "A user belongs to an allowed group"
                ],
            ],
            allow_query => [
                [
                    qw(MightyAdmin AnyWeb.AnyTopic),
"Admins are like gods: allowed anywhere by default in allow_do"
                ],
                [
                    qw(JohnSmith Sandbox.QTestTopic),
                    "Inidividual user allowed for a topic"
                ],
                [
                    'DummyGuest',
                    "$this->{test_web}.QSomeImaginableTopic",
                    "Individual user defined together with a group for a topic"
                ],
                [
                    'JohnSmith',
                    "$this->{test_web}.QSomeImaginableTopic",
"User within a group defined together with a individual user for a topic"
                ],
                [
                    qw(JohnSmith Sandbox.DoForSelected),
                    "Individual user defined in allow_do"
                ],
                [
                    qw(DummyGuest Sandbox.DoDummyTopic),
                    "User within a group defined in allow_do"
                ],
                [
                    qw(ElvisPresley AnotherWeb.AnotherTopic),
"The king yet not the god: cannot be do-ing but still may query anywhere"
                ],
            ],
            allow_child1 => [
                [
                    qw(JohnSmith Sandbox.DoForSelected),
                    "Individual user defined in allow_do"
                ],
            ],
            allow_child5 => [
                [
                    qw(JohnSmith Sandbox.DoForSelected),
"Deep inheritance for individual user despite of circular dependency"
                ],
            ],
        },
        invalid => {
            allow_do => [
                [
                    qw(DummyGuest AnyWeb.AnyTopic),
                    "A user anywhere outside his allowed zone is unallowed"
                ],
                [
                    qw(JohnSmith Sandbox.QTestTopic),
                    "Allowed for query, not for do-ing"
                ],
            ],
            allow_query => [
                [
                    'DummyGuest',
                    "$Foswiki::cfg{UsersWebName}.QSiteMessageBoard",
                    "Variable expansion for topic name is not supported"
                ],
                [
                    'JohnSmith',
                    "Sandbox.QDummyTopic",
                    "Individual user not allowed for a topic"
                ],
            ],
        },
    );

    foreach my $bunch (qw(valid invalid)) {
        foreach my $access_type ( keys %{ $check_pairs{$bunch} } ) {
            foreach my $test_pair ( @{ $check_pairs{$bunch}{$access_type} } ) {
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

1;
