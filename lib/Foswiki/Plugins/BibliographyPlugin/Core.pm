# See bottom of file for license and copyright information
package Foswiki::Plugins::BibliographyPlugin::Core;

use strict;
use warnings;
use Assert;
use HTML::Entities;
# Change to 1 for more debug messages. Perl compiler should optimise out
# (ie. no CPU cost) any statement checking its value when set to zero.
use constant TRACE => 0;

my %bibliography         = ();
my $bibliography_loaded  = 0;
my %cites_deferred       = ();
my $cites_deferred_total = 0;
my %cited_refs           = ();
my %missing_refs         = ();
my %ref_topics           = ();
my $ref_sequence         = 0;
my %messages             = ();

sub CITE {
    my ( $session, $params, $topic, $web, $topicObject ) = @_;
    my $cit         = $params->{_DEFAULT};
    my $encoded_ref = HTML::Entities::encode($cit);

    if ($bibliography_loaded) {
        Foswiki::Func::writeDebug(
            "%CITE{$params->{_DEFAULT}}%: bibliography loaded")
          if $Foswiki::cfg{Plugins}{BibliographyPlugin}{Debug};
        if ( $params->{occurance} ) {
            Foswiki::Func::writeDebug( <<"HERE") if TRACE;
%CITE{$params->{_DEFAULT}}%: this was delayed as occurance $params->{occurance}; deleting
HERE
            delete( $cites_deferred{ $params->{occurance} } );
            $cites_deferred_total = $cites_deferred_total - 1;
        }
        if ( $bibliography{$cit} ) {
            Foswiki::Func::writeDebug( <<"HERE") if TRACE;
%CITE{$params->{_DEFAULT}}%: bibliography entry exists
HERE
            if ( not exists $cited_refs{$cit} ) {
                Foswiki::Func::writeDebug( <<"HERE") if TRACE;
%CITE{$params->{_DEFAULT}}%: has not been cited before, added
HERE
                $ref_sequence = $ref_sequence + 1;
                $cited_refs{$cit} = {
                    value    => $bibliography{$cit},
                    name     => $cit,
                    sequence => $ref_sequence
                };
                $cited_refs{$cit}{sequence} = $ref_sequence;
            }
            return '<noautolink>'
              . CGI::a(
                {
                    -class => 'foswikiLink BibliographyPluginReference',
                    -title => $encoded_ref,
                    -href  => '#' . $encoded_ref
                },
                '[' . $cited_refs{$cit}{sequence} . ']'
              ) . '</noautolink>';
        }
        else {
            $missing_refs{$encoded_ref} = 1;
            return '<noautolink>'
              . CGI::span(
                {
                    -class => 'foswikiAlert BibliographyPluginMissingReference',
                    -title => 'Did not find reference "' . $encoded_ref . '".'
                },
                '[??]'
              ) . '</noautolink>';
        }
    }
    else {
        my $output;
        my $message;
        $message = "%CITE{$params->{_DEFAULT}}%: Bibliography not loaded"
          if TRACE;

        # Need to delay expansion of this macro until the bibliography is
        # loaded. If it hasn't been delayed before, give it an occurance id
        if ( not $params->{occurance} ) {
            my $safe_ref = $params->{_DEFAULT};    # Defuse quotes
            $safe_ref =~ s/["]/\\"/g;
            $cites_deferred{$cites_deferred_total} = 1;
            $cites_deferred_total = $cites_deferred_total + 1;
            $message .= ", delayed as occurance $cites_deferred_total" if TRACE;
            $output =
              "%CITE{\"$safe_ref\" occurance=\"$cites_deferred_total\"}%";
        }
        else {
            $message .= ", already delayed as occurance $params->{occurance}"
              if TRACE;
        }
        Foswiki::Func::writeDebug($message) if TRACE;

        return $output;
    }
}

sub CITEINLINE {
    my ( $session, $params, $topic, $web, $topicObject ) = @_;

    $bibliography{ $params->{_DEFAULT} } = $params->{_DEFAULT};

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
    $bibliography_loaded =
      _loadBibliography( $session, $topicObject, $bibliography_loaded,
        $params->{referencesTopic} );
    my $output;

    if ( $params->{order} and ( $params->{order} eq 'alpha' ) ) {
        $sort_fn = \&_bibliographyAlphaSort;
    }
    if ($cites_deferred_total) {

        # Some CITE macro expansion was deferred because the bibliography
        # wasn't loaded until now. So %BIBLIOGRAPHY{}% will be deferred until
        # the Fosiwki renderer has had another chance to expand them.
        Foswiki::Func::writeDebug(
"Deferring %BIBLIOGRAPHY{}% because there were $cites_deferred_total deferred %CITE{}%s"
        ) if $Foswiki::cfg{Plugins}{BibliographyPlugin}{Debug};
    }
    else {
        $output = _generateBibliography( $header, $sort_fn );
    }

    return $output;
}

sub _loadBibliography {
    my ( $session, $topicObject, $already_loaded, $webTopicListString ) = @_;

    if ( not $already_loaded ) {
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

    return 1;
}

sub _parseline {
    my ($line) = @_;

    if ( $line =~ /^\|\s+([^\|]+)\s+\|\s+([^\|]+)\s+\|/ ) {
        $bibliography{$1} = $2;

        return 1;
    }

    return 0;
}

sub _getTopicObject {
    my ( $session, $web, $topic ) = @_;
    my $topicObject;

    if ( $Foswiki::Plugins::VERSION >= 2.1 ) {
        $topicObject = Foswiki::Meta->new( $session, $web, $topic );
        $topicObject->reload();
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
                if ( open my $text_fh, '<', \$text ) {
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
%MAKETEXT{"Unable to begin processing [_1] for references" args="[[$web.$topic]]"
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

    return lc( $cited_refs{$a}{name} ) cmp lc( $cited_refs{$b}{name} );
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
    foreach my $key ( sort { &{$sort_fn}( $a, $b ) } ( keys %cited_refs ) ) {
        push(
            @list,
            CGI::li(
                '<noautolink>'
                  . CGI::a(
                    {
                        -name =>
                          HTML::Entities::encode( $cited_refs{$key}{name} )
                    },
                    ' '
                  )
                  . '</noautolink>',
                $cited_refs{$key}{value}
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
