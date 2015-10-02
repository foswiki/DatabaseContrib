# ---+ Extensions
# ---++ DatabaseContrib
# **PERL 20x40 LABEL="List of database connections"**
# <h2>Setup for Local databases table</h2>
# Table of configuration info for all the databases you might access.
# This structure is a hash of connection definitions. Each connection
# is defined using a hash reference where the fields are:
# <ol>
# <li> <code>description</code> - Symbolic name for this database</li>
# <li> <code>driver</code> - DB driver - values like: mysql, Oracle, etc.</li>
# <li> <code>host</code> - DB host</li>
# <li> <code>database</code> - DB name</li>
# <li> <code>user</code> - DB username</li>
# <li> <code>password</code> - DB password</li>
# <li> <code>codepage</code> - character information, such as utf8</li>
# <li> <code>driver_attributes</code> - hash reference of additional driver attributes like <code>AutoCommit</code> or <code>mysql_enable_utf8</code>. <code>RaiseError</code>, <code>PrintError</code> and <code>FetchHashKeyName</code> ignored as they're set internally. Note that these atributes could be overriden by <code>db_connect()</code> call arguments.</li>
# <li> <code>allow_do</code> - hash reference of Foswiki topics that contain data base access to lists of allowed users</li>
# <li> <code>init</code> - a database statement to be passed to <code>$dbh->do()</code> call upon successful connect</li>
# </ol>
$Foswiki::cfg{Extensions}{DatabaseContrib}{connections} = {
    message_board => {
        user => 'dbuser',
        password => 'dbpasswd',
        driver => 'mysql',
        database => 'message_board',
        codepage => 'utf8',
        allow_do => {
            default => [qw(FoswikiAdminGroup)],
            'Sandbox.CommonDiscussion' => [qw(FoswikiGuest)],
        },
        # host => 'localhost',
    },
};

# **BOOLEAN LABEL="Die on failures" EXPERT**
# Die if an internal error took place. Useful for testing purposes mostly.
$Foswiki::cfg{Extensions}{DatabaseContrib}{dieOnFailure} = 0;
1;
# vim: ft=perl et ts=4
