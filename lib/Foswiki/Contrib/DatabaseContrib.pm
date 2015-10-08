# See bottom of file for default license and copyright information
use v5.16;

package Foswiki::Contrib::DatabaseContrib;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use DBI;

use Foswiki::Func;

# use Error qw(:try);
use CGI qw(:html2);
use Carp qw(longmess);
use Storable qw(dclone);
use Time::HiRes qw(time);
use Data::Dumper;

# $VERSION is referred to by Foswiki, and is the only global variable that
# *must* exist in this package. For best compatibility, the simple quoted decimal
# version '1.00' is preferred over the triplet form 'v1.0.0'.
# "1.23_001" for "alpha" versions which compares lower than '1.24'.

# For triplet format, The v prefix is required, along with "use version".
# These statements MUST be on the same line.
#  use version; our $VERSION = 'v1.2.3_001'
# See "perldoc version" for more information on version strings.
#
# Note:  Alpha versions compare as numerically lower than the non-alpha version
# so the versions in ascending order are:
#   v1.2.1_001 -> v1.2.2 -> v1.2.2_001 -> v1.2.3
#   1.21_001 -> 1.22 -> 1.22_001 -> 1.23
#
use version; our $VERSION = version->declare('v1.02_001');

# $RELEASE is used in the "Find More Extensions" automation in configure.
# It is a manually maintained string used to identify functionality steps.
# You can use any of the following formats:
# tuple   - a sequence of integers separated by . e.g. 1.2.3. The numbers
#           usually refer to major.minor.patch release or similar. You can
#           use as many numbers as you like e.g. '1' or '1.2.3.4.5'.
# isodate - a date in ISO8601 format e.g. 2009-08-07
# date    - a date in 1 Jun 2009 format. Three letter English month names only.
# Note: it's important that this string is exactly the same in the extension
# topic - if you use %$RELEASE% with BuildContrib this is done automatically.
# It is preferred to keep this compatible with $VERSION. At some future
# date, Foswiki will deprecate RELEASE and use the VERSION string.
#
our $RELEASE = '15 Sep 2015';

# One-line description of the module
our $SHORTDESCRIPTION =
  'Provides subroutines useful in writing plugins that access a SQL database.';

use Exporter;
our ( @ISA, @EXPORT_OK, %EXPORT_TAGS );
@ISA = qw( Exporter );

@EXPORT_OK =
  qw( db_init db_connect db_disconnect db_connected db_access_allowed db_allowed );

%EXPORT_TAGS = ( all => [@EXPORT_OK], );

=begin TML

---++ Internal object structure.

Top level keys:

|*Key name*|*Type*|*Description*|
|=_dbh=|=hashref=|Mapping of a connection name into initialized database handler =dbh=.|
|=_cached=|=hashref=|Keeps miscellaneous data for easier or perhaps faster access. Makes it possible to freeze data at certain state.|

=cut

# Internally used object for emulating deprecated procedural interface.
my $db_object;

sub _warning (@) {
    return Foswiki::Func::writeWarning(@_);
}

sub warning {
    my $self = shift;
    return Foswiki::Func::writeWarning(@_);
}

sub _failure ($) {
    my $msg = shift;
    if ( $Foswiki::cfg{Contrib}{DatabaseContrib}{dieOnFailure} ) {
        die $msg;
    }
    else {
        return 1;
    }
}

sub _fail {
    my $self = shift;
    if ( $Foswiki::cfg{Contrib}{DatabaseContrib}{dieOnFailure} ) {

        # TODO Some kind of message prefix is to be considered
        throw Error::Simple -text => join( '', @_ );
    }
    else {
        return 1;
    }
}

sub _check_init {
    die
"DatabaseContrib has not been initalized yet. Call db_init() before use please."
      unless defined($db_object)
      && $db_object->isa('Foswiki::Contrib::DatabaseContrib');
}

sub new {
    my $self = bless {}, shift;

    $self->init(@_);

    return $self;
}

sub _cache {
    my $self = shift;
    my ( $key, $data ) = @_;

    if ( @_ > 1 ) {
        $self->{_cached}{$key} = {
            time => time,
            data => dclone($data),
        };
    }
    return undef
      unless defined $self->{_cached} && defined $self->{_cached}{$key};
    return wantarray
      ? ( @{ $self->{_cached}{$key} }{qw(time data)} )
      : $self->{_cached}{$key}{data};
}

sub init {
    my $self = shift;

    if ( scalar(@_) % 2 ) {
        throw Error::Simple "Odd number of parameters in call to "
          . ref($self)
          . "::init()";
    }

    my %attrs = @_;

    # check for Plugins.pm versions
    my $expectedVer = 0.77;
    if ( $Foswiki::Plugins::VERSION < $expectedVer ) {
        $self->warning(
"Version mismatch between DatabaseContrib.pm and Plugins.pm (expecting: $expectedVer, get: "
              . $Foswiki::Plugins::VERSION
              . ")" );
        return undef;
    }

    unless ( $Foswiki::cfg{Extensions}{DatabaseContrib}{connections} ) {
        $self->warning("No connections defined.");
        return 0;
    }
    unless (
        ref( $Foswiki::cfg{Extensions}{DatabaseContrib}{connections} ) eq
        'HASH' )
    {
        $self->warning(
'$Foswiki::cfg{Extensions}{DatabaseContrib}{connections} entry is not a HASH ref.'
        );
        return 0;
    }

   # Never give a chance of accidental mangling with the original configuration.
   # It is mostly related to tests.
    $self->_cache( 'connections',
        $Foswiki::cfg{Extensions}{DatabaseContrib}{connections} );

    if ( defined $attrs{allow_mapping} ) {
        $self->_cache( allow_mapping => $attrs{allow_mapping} );
    }

    return $self;
}

sub connected {
    my $self = shift;
    my ($conname) = @_;

    #say STDERR "{_dbh} = ", Dumper($self->{_dbh});

    return ( defined( $self->{_dbh} ) && defined( $self->{_dbh}{$conname} ) );
}

sub dbh {
    my $self = shift;
    my ($conname) = @_;

    return undef unless $self->connected($conname);
    return $self->{_dbh}{$conname};
}

sub db_init {
    $db_object =
      Foswiki::Contrib::DatabaseContrib->new( @_,
        allow_mapping => { allow_query => 'allow_do' } );
    return $db_object;
}

sub db_connected {
    _check_init;

    return $db_object->connected(@_);
}

sub _set_codepage {
    my $self       = shift;
    my ($conname)  = @_;
    my $connection = $self->_cache('connections')->{$conname};
    my $dbh        = $self->dbh($conname);

    if ( $connection->{codepage} ) {

        # SETTING CODEPAGE $connection->{codepage} for $conname\n";
        if ( $connection->{driver} =~ /^(mysql|Pg)$/ ) {
            $dbh->do("SET NAMES $connection->{codepage}");
            if ( $connection->{driver} eq 'mysql' ) {
                $dbh->do("SET CHARACTER SET $connection->{codepage}");
            }
        }
    }
}

# Finds mapping of a user in a list of users or groups.
# Returns matched entry from $allow_map list
sub _find_mapping {
    my $self = shift;
    my ( $mappings, $user ) = @_;

#say STDERR "_find_mapping(", join(",", map {$_ // '*undef*'} @_), ")";
#say STDERR "Mappings list: [", join(",", map {$_ // '*undef*'} @$mappings), "]";

    $user = Foswiki::Func::getWikiUserName( $user ? $user : () );
    my $found = 0;
    my $match;
    foreach my $entity (@$mappings) {
        $match = $entity;

        #say STDERR "Matching $user against $entity";

        # Checking for access of $user within $entity
        if ( Foswiki::Func::isGroup($entity) ) {

            # $entity is a group
            #say STDERR "$entity is a group";
            $found =
              Foswiki::Func::isGroupMember( $entity, $user, { expand => 1 } );
        }
        else {
            $entity = Foswiki::Func::getWikiUserName($entity);

            #say STDERR "$entity is a user";
            $found = ( $user eq $entity );
        }
        last if $found;
    }
    return $found ? $match : undef;
}

# $conname - connection name from the configutation
# $section – page we're checking access for in form Web.Topic
# $access_type - one of the allow_* keys.
sub access_allowed {
    my $self = shift;
    my ( $conname, $web, $access_type, $user ) = @_;

    my $connection = $self->_cache('connections')->{$conname};

    #say STDERR "db_access_allowed(", join(",", map {$_ // '*undef*'} @_), ")";

    unless ( defined $connection ) {

        #say STDERR "No $conname in connections";
        return 0 if $self->_fail("No connection $conname in the configuration");
    }

    my $allow_mapping = $self->_cache('allow_mapping') // {};

    #say STDERR "\$connection: ", Dumper($connection);

    # Defines map priorities. Thus, no point to specify additional
    # allow_query access right if allow_do has been defined for a topic
    # already.

    # By default we deny all.
    my $match;

    $user = Foswiki::Func::getWikiUserName() unless defined $user;

    if ( defined $connection->{$access_type} ) {

        #say STDERR "Checking $user of $conname at $web";

        my $final_web =
          defined( $connection->{$access_type}{$web} )
          ? $web
          : "default";

       #say STDERR "Final web would be $final_web: $connection->{$access_type}";
        my $allow_map =
          defined( $connection->{$access_type}{$final_web} )
          ? (
            ref( $connection->{$access_type}{$final_web} ) eq 'ARRAY'
            ? $connection->{$access_type}{$final_web}
            : [
                ref( $connection->{$access_type}{$final_web} )
                ? ()
                : $connection->{$access_type}{$final_web}
            ]
          )
          : [];
        $match = $self->_find_mapping( $allow_map, $user );

        #say STDERR "Match result: ", $match // '*undef*';
    }
    if ( !defined($match) && defined( $allow_mapping->{$access_type} ) ) {

# Check for higher level access map if feasible.
#say STDERR "No match found, checking for higher level access map $map_inclusions{$access_type}";
        return $self->access_allowed( $conname, $web,
            $allow_mapping->{$access_type}, $user );
    }

    return defined $match;
}

sub db_access_allowed {
    _check_init;
    return $db_object->access_allowed(@_);
}

# db_allowed is deprecated and is been kept for compatibility matters only.
sub db_allowed {
    _check_init;
    my ( $conname, $section ) = @_;

    return db_access_allowed( $conname, $section, 'allow_do' );
}

sub connect {
    my $self    = shift;
    my $conname = shift;

    my $connection = $self->_cache('connections')->{$conname};
    unless ( defined $connection ) {
        return
          if _failure "No connection `$conname' defined in the cofiguration";
    }

    my $dbh = $self->dbh($conname);

    return $dbh if defined $dbh;

    my @required_fields = qw(database driver);

    unless ( defined $connection->{dsn} ) {
        foreach my $field (@required_fields) {
            unless ( defined $connection->{$field} ) {
                return
                  if $self->fail(
"Required field $field is not defined for database connection $conname.\n"
                  );
            }
        }
    }

    my ( $dbuser, $dbpass ) =
      ( $connection->{user} // "", $connection->{password} // "" );

    if ( defined( $connection->{usermap} ) ) {

       # Individual mappings are checked first when it's about user->dbuser map.
        my @maps =
          sort { ( $a =~ /Group$/ ) <=> ( $b =~ /Group$/ ) }
          keys %{ $connection->{usermap} };

        my $usermap_key = _find_mapping( \@maps );
        if ($usermap_key) {
            $dbuser = $connection->{usermap}{$usermap_key}{user};
            $dbpass = $connection->{usermap}{$usermap_key}{password};
        }
    }

# CONNECTING TO $conname, ", (defined $connection->{dbh} ? $connection->{dbh} : "*undef*"), ", ", (defined $dbi_connections{$conname}{dbh} ? $dbi_connections{$conname}{dbh} : "*undef*"), "\n";

    # CONNECTING TO $conname\n";
    my $dsn;
    if ( defined $connection->{dsn} ) {
        $dsn = $connection->{dsn};
    }
    else {
        my $server =
          $connection->{server} ? "server=$connection->{server};" : "";
        $dsn =
"dbi:$connection->{driver}\:${server}database=$connection->{database}";
        $dsn .= ";host=$connection->{host}" if $connection->{host};
    }

    my @drv_attrs;
    if ( defined $connection->{driver_attributes}
        && ref( $connection->{driver_attributes} ) eq 'HASH' )
    {
        @drv_attrs = map { $_ => $connection->{driver_attributes}{$_} }
          grep { !/^(?:RaiseError|PrintError|FetchHashKeyName)$/ }
          keys %{ $connection->{driver_attributes} };

    }
    $dbh = DBI->connect(
        $dsn, $dbuser, $dbpass,
        {
            RaiseError       => 1,
            PrintError       => 1,
            FetchHashKeyName => NAME_lc => @drv_attrs,
            @_
        }
    );
    unless ( defined $dbh ) {

#	        throw Error::Simple("DBI connect error for connection $conname: $DBI::errstr");
        $self->_cache( 'errors',
            { $conname => { errstr => $DBI::errstr, err => $DBI::err } } );
        return undef;
    }

    $self->{_dbh}{$conname} = $dbh;

    $self->_set_codepage($conname);

    if ( defined $connection->{init} ) {
        $dbh->do( $connection->{init} );
    }

    #say STDERR "Connected to $conname";

    return $dbh;
}

sub db_connect {
    _check_init;
    return $db_object->connect(@_);
}

sub disconnect {
    my $self        = shift;
    my $connections = $self->_cache('connections');
    my @connames    = scalar(@_) > 0 ? @_ : keys %$connections;
    foreach my $conname (@connames) {

        #say STDERR "Disconnecting $conname";
        if ( $self->connected($conname) ) {
            my $dbh = $self->{_dbh}{$conname};
            $dbh->commit unless $dbh->{AutoCommit};
            $dbh->disconnect;
            delete $self->{_dbh}{$conname};
        }
    }
}

sub db_disconnect {
    _check_init;
    return $db_object->disconnect(@_);
}

sub DESTROY {
    shift->disconnect;
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2015 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
