use v5.16;
use strict;

package DatabaseContribTests;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use Foswiki;
use Foswiki::Func;
use File::Temp;
use Foswiki::Contrib::DatabaseContrib qw(:all);
use Data::Dumper;

sub new {
    my $self = shift()->SUPER::new(@_);
    return $self;
}

# Set up the test fixture
sub set_up {
    my $this = shift;

    #say STDERR "set_up";

    $this->SUPER::set_up();

    #say STDERR "Predefining users and groups";

    $this->registerUser( 'JohnSmith', 'Jogn', 'Smith',
        'webmaster@otoib.dp.ua' );
    $this->registerUser( 'ElvisPresley', 'Elvis', 'Presley',
        'webmaster@otoib.dp.ua' );
    $this->registerUser( 'DummyGuest', 'Dummy', 'Guest', 'nobody@otoib.dp.ua' );
    $this->registerUser( 'MightyAdmin', 'Miky', 'Theadmin',
        'daemon@otoib.dp.ua' );

    $this->assert(
        Foswiki::Func::addUserToGroup(
            $this->{session}->{user},
            'AdminGroup', 0
        ),
        'Failed to create a new admin'
    );
    $this->assert( Foswiki::Func::addUserToGroup( 'JohnSmith', 'TestGroup', 1 ),
        'Failed to create TestGroup' );
    $this->assert(
        Foswiki::Func::addUserToGroup( 'DummyGuest', 'DummyGroup', 1 ),
        'Failed to create DummyGroup' );
    $this->assert(
        Foswiki::Func::addUserToGroup(
            'ElvisPresley', 'AnywhereQueryingGroup', 1
        ),
        'Failed to create AnywhereQueryingGroup'
    );
    $this->assert(
        Foswiki::Func::addUserToGroup( 'MightyAdmin', 'AdminGroup', 0 ),
        'Failed to create a new admin' );
    $this->assert( Foswiki::Func::addUserToGroup( 'ScumBag', 'AdminGroup', 0 ),
        'Failed to create a new admin' );

    $this->assert( db_init, "DatabaseContrib init failed" );
}

sub tear_down {
    my $this = shift;
    $this->SUPER::tear_down();
}

sub loadExtraConfig {
    my $this = shift;

    #say STDERR "loadExtraConfig";

    $this->SUPER::loadExtraConfig;

    $Foswiki::cfg{Contrib}{DatabaseContrib}{dieOnFailure}   = 0;
    $Foswiki::cfg{Extensions}{DatabaseContrib}{connections} = {
        message_board => {
            driver            => 'Mock',
            database          => 'sample_db',
            codepage          => 'utf8',
            user              => 'unmapped_user',
            password          => 'unmapped_password',
            driver_attributes => {
                mock_unicode   => 1,
                some_attribute => 'YES',
            },
            allow_do => {
                default                 => [qw(AdminGroup)],
                "Sandbox.DoTestTopic"   => [qw(TestGroup)],
                "Sandbox.DoDummyTopic"  => [qw(DummyGroup)],
                "Sandbox.DoForSelected" => [qw(JohnSmith ScumBag)],
            },
            allow_query => {
                default                        => [qw(AnywhereQueryingGroup)],
                '%USERSWEB%.QSiteMessageBoard' => 'DummyGroup',
                'Sandbox.QDummyTopic'          => [qw(DummyGroup)],
                'Sandbox.QTestTopic'           => [qw(JohnSmith)],
                "$this->{test_web}.QSomeImaginableTopic" =>
                  [qw(TestGroup DummyGuest)],
            },
            usermap => {
                DummyGroup => {
                    user     => 'dummy_map_user',
                    password => 'dummy_map_password',
                },
            },

            # host => 'localhost',
        },
        sample_connection => {
            driver            => 'Mock',
            database          => 'sample_db',
            codepage          => 'utf8',
            user              => 'unmapped_user',
            password          => 'unmapped_password',
            driver_attributes => { some_attribute => 1, },
            allow_do          => { "Sandbox.DoTestTopic" => [qw(TestGroup)], },
        },
    };
}

sub db_test_connect {
    my ( $this, $conname ) = @_;
    my $dbh = db_connect($conname);
    $this->assert_not_null( $dbh, "Failed: connection to $conname DB" );
    return $dbh;
}

sub test_permissions {
    my $this = shift;

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
                    "Variable expandsion for topic name is not supported"
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
        foreach my $access_type (qw(allow_do allow_query)) {
            foreach my $test_pair ( @{ $check_pairs{$bunch}{$access_type} } ) {
                if ( $bunch eq 'valid' ) {
                    $this->assert(
                        db_access_allowed(
                            'message_board', $test_pair->[1],
                            $access_type,    $test_pair->[0]
                        ),
"$bunch $access_type for $test_pair->[0] on $test_pair->[1] failed while has to conform the following rule: "
                          . $test_pair->[2],
                    );
                }
                else {
                    $this->assert(
                        !db_access_allowed(
                            'message_board', $test_pair->[1],
                            $access_type,    $test_pair->[0]
                        ),
"$bunch $access_type for $test_pair->[0] on $test_pair->[1]: "
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

    my $required_ver = 1.01;

    $this->assert(
        $Foswiki::Contrib::DatabaseContrib::VERSION == $required_ver,
"Module version mismatch, expect $required_ver, got $Foswiki::Contrib::DatabaseContrib::VERSION "
    );
}

1;
