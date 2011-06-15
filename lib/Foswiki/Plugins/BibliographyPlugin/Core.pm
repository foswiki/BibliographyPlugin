# See bottom of file for license and copyright information
package Foswiki::Plugins::BibliographyPlugin::Core;

use strict;
use warnings;
use Assert;
use HTML::Entities;
use Encode;

# Change to 1 for more debug messages. Perl compiler should optimise out
# (ie. no CPU cost) any statement checking its value when set to zero.
use constant TRACE => 0;

# Ensure that these globals are reinitilised in doInit() for persistent perl
# Environments
my %ref_topics;
my %bibliography;
my $bibliography_loaded;
my %cites_deferred;
my $cites_deferred_total;
my $cite_sequence;
my %cited_refs;
my %missing_refs;
my %messages;

sub _addToCited {
    my ($bibkey) = @_;

    $cite_sequence = $cite_sequence + 1;
    $cited_refs{$bibkey} = {
        value    => $bibliography{$bibkey}{value},
        userkey  => $bibliography{$bibkey}{userkey},
        sequence => $cite_sequence
    };

    return;
}

# Add user's $key to the bibliography, indexed by a filtered version of $key
sub _addToBibliography {
    my ( $key, $value ) = @_;

    $bibliography{ _filterCiteKey($key) } = {
        userkey => $key,
        value   => $value
    };

    return;
}

# Handle a %CITE{}% where the reference exists in the bibliography.
sub _CITE_exists {
    my ($bibkey)        = @_;
    my $encoded_userkey = _encode( $bibliography{$bibkey}{userkey} );
    my $escaped_userkey = _escape( $bibliography{$bibkey}{userkey} );

    Foswiki::Func::writeDebug("%CITE{$bibkey}%: bibliography entry exists")
      if TRACE;

    # Save this reference as cited so it may be included in the generated
    # Bibliography, but only if it hasn't been added before
    if ( not exists $cited_refs{$bibkey} ) {
        Foswiki::Func::writeDebug(
            "%CITE{$bibkey}%: has not been cited before, added")
          if TRACE;
        _addToCited($bibkey);
    }
    return '<noautolink>'
      . CGI::a(
        {
            -class => 'foswikiLink BibliographyPluginReference',
            -title => $escaped_userkey,
            -href  => '#' . $encoded_userkey
        },
        '[' . $cited_refs{$bibkey}{sequence} . ']'
      ) . '</noautolink>';
}

# Handle a %CITE{}% where the reference does not exist in the bibliography.
sub _CITE_missing {
    my ($citedkey) = @_;
    my $escaped_cited = _escape($citedkey);

    $missing_refs{$citedkey} = 1;
    return '<noautolink>'
      . CGI::span(
        {
            -class => 'foswikiAlert BibliographyPluginMissingReference',
            -title => 'Did not find reference "' . $escaped_cited . '".'
        },
        '[??]'
      ) . '</noautolink>';
}

# Forget about a %CITE{"$citekey" occurance="$occurance_id"}% occurance from the
# registry of defferred %CITE{}% occurances.
sub _CITE_undefer {
    my ( $bibkey, $occurance_id ) = @_;

    Foswiki::Func::writeDebug( <<"HERE") if TRACE;
%CITE{$bibkey}%: this was delayed as occurance $occurance_id; deleting
HERE
    delete( $cites_deferred{$occurance_id} );
    $cites_deferred_total = $cites_deferred_total - 1;

    return;
}

# Remember this %CITE{"$userkey"}% occurance in the registry of defferred occurances
# SMELL: Foswiki API/EmptyPlugin docs say that one "cannot" make a macro return
#        another macro, and yet here we are. Not sure how to do this otherwise,
#        unless we re-introduce a commonTagsHandler; but then it becomes
#        difficult to use CITE and BIBLIOGRAPHY from template topics, includes,
#        formfields. Ideas welcome... - PH
sub _CITE_defer {
    my ($userkey) = @_;

    $cites_deferred_total = $cites_deferred_total + 1;
    $cites_deferred{$cites_deferred_total} = 1;
    Foswiki::Func::writeDebug(
"%CITE{$userkey}%: Bibliography not loaded; delayed as occurance $cites_deferred_total"
    ) if TRACE;

    return "%CITE{\"$userkey\" occurance=\"$cites_deferred_total\"}%";
}

# Encode cite keys with HTML entities to ensure only valid chars when used as
# <a name="... anchors
sub _encode {
    my ($foo) = @_;

    return HTML::Entities::encode($foo);
}

# Encode " and ' quotes to ensure the value will form a legal string when used
# in a title="" attribute. SMELL: redundant if already using CGI to build HTML
sub _escape {
    my ($escape) = @_;
    my $_escaped = $escape;

    #    $_escaped =~ s/(["])/&quot;/g;

    return $_escaped;
}

sub _doInit {
    if ( Foswiki::Plugins::BibliographyPlugin::needInit() ) {

        # All the globals need to be initilised in mod_perl, fastcgi enviroment
        %ref_topics           = ();
        %bibliography         = ();
        $bibliography_loaded  = 0;
        %cites_deferred       = ();
        $cites_deferred_total = 0;
        $cite_sequence        = 0;
        %cited_refs           = ();
        %missing_refs         = ();
        %messages             = ();
        Foswiki::Plugins::BibliographyPlugin::finishInit();
    }

    return;
}

sub CITE {
    my ( $session, $params, $topic, $web, $topicObject ) = @_;
    my $userkey = $params->{_DEFAULT};
    my $bibkey  = _filterCiteKey($userkey);

    # $topicObject is sometimes undef on save with 1.0.x
    if ($topicObject) {
        _doInit();
        if ($bibliography_loaded) {
            Foswiki::Func::writeDebug("%CITE{$userkey}%: bibliography loaded")
              if $Foswiki::cfg{Plugins}{BibliographyPlugin}{Debug};
            if ( $params->{occurance} ) {
                _CITE_undefer( $bibkey, $params->{occurance} );
            }
            if ( $bibliography{$bibkey} ) {
                return _CITE_exists($bibkey);
            }
            else {
                return _CITE_missing($bibkey);
            }
        }
        else {

            # Need to delay expansion of this macro until the bibliography is
            # loaded. If it hasn't been delayed before, give it an occurance id
            if ( not $params->{occurance} ) {
                return _CITE_defer($userkey);
            }
            else {
                Foswiki::Func::writeDebug(<<"HERE") if TRACE;
%CITE{$userkey}%: Bibliography not loaded; already deferred as occurance $params->{occurance}
HERE
                return;
            }
        }
    }
    else {
        Foswiki::Func::writeDebug(
            <<"HERE") if $Foswiki::cfg{Plugins}{BibliographyPlugin}{Debug};
\$topicObject is undef in CITE on $web.$topic
HERE
    }
}

sub CITEINLINE {
    my ( $session, $params, $topic, $web, $topicObject ) = @_;

    _addToBibliography( $params->{_DEFAULT}, $params->{_DEFAULT} );

    return CITE( $session, $params, $topic, $web, $topicObject );
}

sub BIBLIOGRAPHY {
    my ( $session, $params, $topic, $web, $topicObject ) = @_;
    my $header =
         Foswiki::Func::getPreferencesValue('BIBLIOGRAPHYPLUGIN_DEFAULTHEADER')
      || $params->{header}
      || '---++ References';
    my $order =
         Foswiki::Func::getPreferencesValue('BIBLIOGRAPHYPLUGIN_DEFAULTSORTING')
      || $params->{order}
      || 'alpha';
    my $sort_fn = \&_bibliographyOrderSort;
    my $output;

    # $topicObject is sometimes undef on save with 1.0.x
    if ($topicObject) {
        _doInit();
        if ( not $bibliography_loaded ) {
            $bibliography_loaded =
              _loadBibliography( $session, $topicObject,
                $params->{referencesTopic} );
        }
        if ( $params->{order} and ( $params->{order} eq 'alpha' ) ) {
            $sort_fn = \&_bibliographyAlphaSort;
        }
        if ($cites_deferred_total) {

      # Some CITE macro expansion was deferred because the bibliography
      # wasn't loaded until now. So %BIBLIOGRAPHY{}% will be deferred until
      # the Fosiwki renderer has had another chance to expand the deferred CITEs
            Foswiki::Func::writeDebug(
"Deferring %BIBLIOGRAPHY{}% because there were $cites_deferred_total deferred %CITE{}%s"
            ) if $Foswiki::cfg{Plugins}{BibliographyPlugin}{Debug};
        }
        else {
            $output = _generateBibliography( $header, $sort_fn );
        }
    }
    else {
        Foswiki::Func::writeDebug(
            <<"HERE") if $Foswiki::cfg{Plugins}{BibliographyPlugin}{Debug};
\$topicObject is undef in CITE on $web.$topic
HERE
    }

    return $output;
}

# Sets up an array of { web => 'foo', topic => 'bar'} to be passed in as the
# list of reference topics to _parseBibliographyTopics()
sub _loadBibliography {
    my ( $session, $topicObject, $webTopicListString ) = @_;
    my $_webTopicListString = $webTopicListString
      || Foswiki::Func::getPreferencesValue(
        'BIBLIOGRAPHYPLUGIN_DEFAULTBIBLIOGRAPHYTOPIC')
      || $Foswiki::cfg{SystemWebName} . '.BibliographyPlugin';
    my @webTopics;

    foreach my $webTopicString ( split( /,\s*/, $_webTopicListString ) ) {
        my ( $_web, $_topic ) =
          Foswiki::Func::normalizeWebTopicName( $topicObject->web(),
            $webTopicString );
        push( @webTopics, { web => $_web, topic => $_topic } );

    }

    return _parseBibliographyTopics( $session, \@webTopics );
}

sub _filterCiteKey {
    my ($citekey) = @_;
    my $_cit = $citekey;

    if ($_cit) {
        $_cit =~ s/<[^>]+>//g;
        $_cit =~ s/\s+//g;
        $_cit = lc($_cit);
    }

    return $_cit;
}

sub _parseline {
    my ($line) = @_;

    if ( $line =~ /^\|\s+([^\|]+)\s+\|\s+([^\|]+)\s+\|/ ) {
        my $userkey = $1;
        my $bibkey;
        my $value = $2;

        $userkey =~ s/<[^>]+>//g;
        $bibkey = _filterCiteKey($userkey);

        if ($bibkey) {
            $bibliography{$bibkey} = {
                userkey => $userkey,
                value   => $value
            };

            return 1;
        }
        else {
            return 0;
        }
    }

    return 0;
}

sub _getTopicObject {
    my ( $session, $web, $topic ) = @_;
    my $topicObject;

    if ( $Foswiki::Plugins::VERSION >= 2.1 ) {
        $topicObject = Foswiki::Meta->load( $session, $web, $topic );
        if ( not $topicObject->haveAccess('VIEW') ) {
            $topicObject->finish();
            $topicObject = undef;
        }
    }
    else {
        ($topicObject) = Foswiki::Func::readTopic( $web, $topic );
        if (
            not Foswiki::Func::checkAccessPermission(
                'VIEW', Foswiki::Func::getWikiName(),
                undef,  $topic,
                $web,   $topicObject
            )
          )
        {
            $topicObject->finish();
            $topicObject = undef;
        }
    }
    if ( not $topicObject ) {
        $messages{<<"HERE"} = 1;
%MAKETEXT{\"Did not have VIEW access to [_1]\" args=\"[[$web.$topic]]\"}%
HERE
    }

    return $topicObject;
}

sub _parseBibliographyTopics {
    my ( $session, $webTopics ) = @_;

    foreach my $webTopic ( @{$webTopics} ) {
        my $web   = $webTopic->{web};
        my $topic = $webTopic->{topic};

        $ref_topics{ $web . '.' . $topic } = 1;
        Foswiki::Func::writeDebug(
            "_parseBibliographyTopics: reading $web.$topic")
          if $Foswiki::cfg{Plugins}{BibliographyPlugin}{Debug};
        my $topicObject = _getTopicObject( $session, $web, $topic );

        if ($topicObject) {
            my $text = $topicObject->text();

            if ($text) {

                # Use a $fh rather than loope over a split(/[\r\n]+/
                # ... so we save a little memory
                if (
                    open my $text_fh,
                    '<:encoding('
                    . ( $Foswiki::cfg{Site}{CharSet} || 'iso-8859-1' ) . ')',
                    \$text
                  )
                {
                    while ( my $line = <$text_fh> ) {
                        _parseline($line);
                    }
                    ASSERT( close($text_fh),
                        '_parseBibliographyTopics: error closing text_fh' );
                }
                else {
                    ASSERT( 0,
                        '_parseBibliographyTopics: error opening text_fh' );
                }
            }
            else {
                $messages{<<"MESSAGE"} = 1;
%MAKETEXT{"Unable to begin processing [_1] for references" args="[[$web.$topic]]"}%
MESSAGE
            }
        }
        else {
            Foswiki::Func::writeDebug(
                <<"DEBUG") if $Foswiki::cfg{Plugins}{BibliographyPlugin}{Debug};
Did not have VIEW permission for $web.$topic
DEBUG
        }
    }

    return 1;
}

sub _bibliographyAlphaSort {
    my ( $a, $b ) = @_;

    return lc( $cited_refs{$a}{userkey} ) cmp lc( $cited_refs{$b}{userkey} );
}

sub _bibliographyOrderSort {
    my ( $a, $b ) = @_;

    return $cited_refs{$a}{sequence} <=> $cited_refs{$b}{sequence};
}

sub _generateBibliography {
    my ( $header, $sort_fn ) = @_;
    my @list;
    my $output = '';

    Foswiki::Func::writeDebug('_generateBibliography()')
      if $Foswiki::cfg{Plugins}{BibliographyPlugin}{Debug};

    # There must be no deferred CITEs remaining
    ASSERT( not $cites_deferred_total );
    foreach my $bibkey ( sort { &{$sort_fn}( $a, $b ) } ( keys %cited_refs ) ) {
        push(
            @list,
            CGI::li(
                '<noautolink>'
                  . CGI::a(
                    { -name => _encode( $cited_refs{$bibkey}{userkey} ) }, ' ' )
                  . '</noautolink>',
                $cited_refs{$bibkey}{value}
            )
        );
    }
    if ( scalar(@list) ) {
        $output =
          CGI::ol( { -class => 'BibliographyPluginReferences' }, @list );
    }
    if ( scalar(%missing_refs) ) {
        $output .= '<noautolink>'
          . CGI::div(
            { -class => 'foswikiAlert BibliographyPluginMissingReferences' },
            '%MAKETEXT{"Reference(s)"}%: "'
              . join( '", "', keys %missing_refs )
              . '" - %MAKETEXT{"were not found in the specified reference topic(s)"}%: [['
              . join( ']], [[', keys %ref_topics ) . ']].'
          ) . '</noautolink>';
    }
    if ( scalar(%messages) ) {
        $output .= '<noautolink>'
          . CGI::div(
            { -class => 'foswikiAlert BibliographyPluginMessages' },
            '%MAKETEXT{"Errors were encountered"}%: '
              . join( ', ', keys %messages )
          ) . '</noautolink>';
    }

    return $header . "\n" . $output;
}

1;

__DATA__
# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
# Copyright (C) 2010 Paul Harvey, http://trin.org.au
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
