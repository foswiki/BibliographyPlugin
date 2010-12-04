# See bottom of file for license and copyright information
package Foswiki::Plugins::BibliographyPlugin;
use warnings;
use strict;

our $VERSION          = '$Rev$';
our $RELEASE          = '2.2.1';
our $SHORTDESCRIPTION = <<'DESCRIPTION';
Cite bibliography in one topic and get a references list automatically created.
DESCRIPTION
our $NO_PREFS_IN_TOPIC = 1;

my $needInit;

sub initPlugin {
    my ( $topic, $web ) = @_;

    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        my $message =
          'Version mismatch between ' . __PACKAGE__ . ' and Plugins.pm';
        Foswiki::Func::writeWarning($message);

        return $message;
    }

    Foswiki::Func::registerTagHandler( 'CITE',         \&_CITE );
    Foswiki::Func::registerTagHandler( 'CITEINLINE',   \&_CITEINLINE );
    Foswiki::Func::registerTagHandler( 'BIBLIOGRAPHY', \&_BIBLIOGRAPHY );
    $needInit = 1;

    # Plugin correctly initialized
    Foswiki::Func::writeDebug(
        "Foswiki::Plugins::BibliographyPlugin::initPlugin( $web.$topic )")
      if $Foswiki::cfg{Plugins}{Bibliography}{Debug};

    return 1;
}

sub needInit {

    return $needInit;
}

sub finishInit {
    $needInit = 0;

    return;
}

# _CITE, _CITEINLINE, _BIBLIOGRAPHY:
# Lazy-load the core so we don't have to compile it for requests where
# BibliographyPlugin tags aren't used

sub _CITE {
    my ( $session, $params, $topic, $web, $topicObject ) = @_;

    require Foswiki::Plugins::BibliographyPlugin::Core;

    return Foswiki::Plugins::BibliographyPlugin::Core::CITE( $session, $params,
        $topic, $web, $topicObject );
}

sub _CITEINLINE {
    my ( $session, $params, $topic, $web, $topicObject ) = @_;

    require Foswiki::Plugins::BibliographyPlugin::Core;

    return Foswiki::Plugins::BibliographyPlugin::Core::CITEINLINE( $session,
        $params, $topic, $web, $topicObject );
}

sub _BIBLIOGRAPHY {
    my ( $session, $params, $topic, $web, $topicObject ) = @_;

    require Foswiki::Plugins::BibliographyPlugin::Core;

    return Foswiki::Plugins::BibliographyPlugin::Core::BIBLIOGRAPHY( $session,
        $params, $topic, $web, $topicObject );
}

1;

__DATA__

# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009 - 2010 Andrew Jones, http://andrew-jones.com
# Copyright (C) 2004 Antonio Terceiro, asaterceiro@inf.ufrgs.br
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html
