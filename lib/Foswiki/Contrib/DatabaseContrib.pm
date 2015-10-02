# See bottom of file for default license and copyright information
use v5.16;

package Foswiki::Contrib::DatabaseContrib;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use DBI;

# use Error qw(:try);
use CGI qw(:html2);
use Carp qw(longmess);
use Data::Dumper;

my ( $INIT_COMPLETE, %dbi_connections );

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
our $VERSION = '1.01';

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

sub _warning (@) {
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

sub _check_init {
    die
"DatabaseContrib has not been initalized yet. Call db_init() before use please."
      unless $INIT_COMPLETE;
}

sub db_init {

    # check for Plugins.pm versions
    my $expectedVer = 0.77;
    if ( $Foswiki::Plugins::VERSION < $expectedVer ) {
        _warning
"Version mismatch between DatabaseContrib.pm and Plugins.pm (expecting: $expectedVer, get: "
          . $Foswiki::Plugins::VERSION . ")";
        return 0;
    }

    my $connections = $Foswiki::cfg{Extensions}{DatabaseContrib}{connections};
    unless ($connections) {
        _warning "No connections defined.";
        return 0;
    }
    %dbi_connections = %$connections;

    # Contrib correctly initialized
    return ( $INIT_COMPLETE = 1 );
}

sub db_connected {
    _check_init;

    my ($conname) = @_;

    return undef unless defined $dbi_connections{$conname};
    return defined $dbi_connections{$conname}{dbh};
}

sub _set_codepage {
    my $conname    = shift;
    my $connection = $dbi_connections{$conname};
    if ( $connection->{codepage} ) {

        # SETTING CODEPAGE $connection->{codepage} for $conname\n";
        if ( $connection->{driver} =~ /^(mysql|Pg)$/ ) {
            $connection->{dbh}->do("SET NAMES $connection->{codepage}");
            if ( $connection->{driver} eq 'mysql' ) {
                $connection->{dbh}
                  ->do("SET CHARACTER SET $connection->{codepage}");
            }
        }
    }
}

# Finds mapping of a user in a list of users or groups.
# Returns matched entry from $allow_map list
sub _find_mapping {
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
my %map_inclusions = ( allow_query => 'allow_do', );

sub db_access_allowed {
    _check_init;
    my ( $conname, $section, $access_type, $user ) = @_;

    #say STDERR "db_access_allowed(", join(",", map {$_ // '*undef*'} @_), ")";

    unless ( defined $dbi_connections{$conname} ) {

        #say STDERR "No $conname in connections";
        return 0 if _failure "No connection $conname in the configuration";
    }

    my $connection = $dbi_connections{$conname};

    #say STDERR "\$connection: ", Dumper($connection);

    # Defines map priorities. Thus, no point to specify additional
    # allow_query access right if allow_do has been defined for a topic
    # already.

    # By default we deny all.
    my $match;

    $user = Foswiki::Func::getWikiUserName() unless defined $user;

    if ( defined $connection->{$access_type} ) {

        #say STDERR "Checking $user of $conname at $section";

        my $final_section =
          defined( $connection->{$access_type}{$section} )
          ? $section
          : "default";

#say STDERR "Final section would be $final_section: $connection->{$access_type}";
        my $allow_map =
          defined( $connection->{$access_type}{$final_section} )
          ? (
            ref( $connection->{$access_type}{$final_section} ) eq 'ARRAY'
            ? $connection->{$access_type}{$final_section}
            : [
                ref( $connection->{$access_type}{$final_section} )
                ? ()
                : $connection->{$access_type}{$final_section}
            ]
          )
          : [];
        $match = _find_mapping( $allow_map, $user );

        #say STDERR "Match result: ", $match // '*undef*';
    }
    if ( !defined($match) && defined( $map_inclusions{$access_type} ) ) {

# Check for higher level access map if feasible.
#say STDERR "No match found, checking for higher level access map $map_inclusions{$access_type}";
        return db_access_allowed( $conname, $section,
            $map_inclusions{$access_type}, $user );
    }

    # TODO User-defined map_inclusions in %dbi_connections.
    return defined $match;
}

# db_allowed is deprecated and kept for compatibility matters only.
sub db_allowed {
    _check_init;
    my ( $conname, $section ) = @_;

    return db_access_allowed( $conname, $section, 'allow_do' );
}

sub db_connect {
    _check_init;
    my $conname = shift;
    unless ( exists $dbi_connections{$conname} ) {
        return
          if _failure "No connection `$conname' defined in the cofiguration";
    }
    my $connection      = $dbi_connections{$conname};
    my @required_fields = qw(database driver);

    unless ( defined $connection->{dsn} ) {
        foreach my $field (@required_fields) {
            unless ( defined $connection->{$field} ) {
                return
                  if _failure
"Required field $field is not defined for database connection $conname.\n";
            }
        }
    }

    my ( $dbuser, $dbpass ) =
      ( $connection->{user} || "", $connection->{password} || "" );

    # $connection->{user} may be undef for cases where connection doesn't
    # require username but general allowance of access to the DB is granted
    # to all Wiki users.
    my $access_allowed = exists $connection->{user};

    if ( defined( $connection->{usermap} ) ) {

       # Individual mappings are checked first when it's about user->dbuser map.
        my @maps =
          sort { ( $a =~ /Group$/ ) <=> ( $b =~ /Group$/ ) }
          keys %{ $connection->{usermap} };

        my $usermap_key = _find_mapping( \@maps );
        if ($usermap_key) {
            $dbuser         = $connection->{usermap}{$usermap_key}{user};
            $dbpass         = $connection->{usermap}{$usermap_key}{password};
            $access_allowed = 1;
        }
    }

    unless ($access_allowed) {
        return
          if _failure
          "User/password are not defined for database connection $conname";
    }

# CONNECTING TO $conname, ", (defined $connection->{dbh} ? $connection->{dbh} : "*undef*"), ", ", (defined $dbi_connections{$conname}{dbh} ? $dbi_connections{$conname}{dbh} : "*undef*"), "\n";
    unless ( $connection->{dbh} ) {

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
            @drv_attrs =
              map { $_ => $connection->{driver_attributes}{$_} }
              grep { !/^(?:RaiseError|PrintError|FetchHashKeyName)$/ }
              keys %{ $connection->{driver_attributes} };

        }
        my $dbh = DBI->connect(
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
            return;
        }
        $connection->{dbh} = $dbh;
    }

    _set_codepage($conname);

    if ( defined $connection->{init} ) {
        $connection->{dbh}->do( $connection->{init} );
    }

    return $connection->{dbh};
}

sub db_disconnect {
    _check_init;
    my @connections = scalar(@_) > 0 ? @_ : keys %dbi_connections;
    foreach my $conname (@connections) {
        if ( $dbi_connections{$conname}{dbh} ) {
            $dbi_connections{$conname}{dbh}->commit
              unless $dbi_connections{$conname}{dbh}{AutoCommit};
            $dbi_connections{$conname}{dbh}->disconnect;
            delete $dbi_connections{$conname}{dbh};
        }
    }
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
