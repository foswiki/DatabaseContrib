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

1;
