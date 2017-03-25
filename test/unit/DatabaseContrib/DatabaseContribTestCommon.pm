use v5.10;
use strict;

package DatabaseContribTestCommon;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use strict;
use Foswiki;
use Foswiki::Func;
use File::Temp;
use Foswiki::Contrib::DatabaseContrib qw(:all);
use Data::Dumper;
use version;

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
    
    $this->{check_pairs} = {
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
                [
                    qw(DummyGuest Sandbox.GlobMatchingTopic),
                    "Glob-matching for user's group"
                ],
                [
                    qw(ElvisPresley Sandbox.GlobsTopic),
                    "Glob-matching for user"
                ],
                [
                    qw(ElvisPresley Sandbox.GlobsTopicRestrict),
                    "Glob-matching for user's group"
                ],
                [
                    qw(DummyGuest Sandbox.GlobsTopic),
                    "Glob-matching for user's group"
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
                [
                    qw(DummyGuest Sandbox.GlobMatchingTopic),
                    "Glob-match: user allowed for query, not for do-ing"
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
                [
                    qw(DummyGuest Sandbox.GlobMatchingTopicAha),
                    "Glob-match: user allowed for query, not for do-ing"
                ],
                [
                    qw(DummyGuest Sandbox.GlobsTopicRestrict),
                    "Glob-matching doesn't apply for this user or its groups"
                ],
            ],
        },
    };
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
                "Sandbox.GlobM*Topic"    => [qw(DummyGroup)],
                "Sandbox.GlobsTopic" => [qw(D*Group El*y)],
                "Sandbox.GlobsTopicRestrict" => [qw(Any*Q*Group)],
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

1;
