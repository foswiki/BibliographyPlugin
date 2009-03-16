# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
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

# =========================
package Foswiki::Plugins::BibliographyPlugin;    # change the package name and $pluginName!!!

# =========================
use vars qw(
        $web $topic $VERSION $RELEASE $pluginName
        $debug 
    );

# This should always be $Rev$ so that Foswiki can determine the checked-in
# status of the plugin. It is used by the build automation tools, so
# you should leave it alone.
our $VERSION = '$Rev$';

# This is a free-form string you can use to "name" your own plugin version.
# It is *not* used by the build automation tools, but is reported as part
# of the version number in PLUGINDESCRIPTIONS.
our $RELEASE = '1.0';

our $pluginName = 'BibliographyPlugin';  # Name of this Plugin

# =========================
sub initPlugin
{
    ( $topic, $web ) = @_;

    # Get plugin debug flag
    #$debug = Foswiki::Func::getPreferencesFlag( "\U$pluginName\E_DEBUG" );
    $debug = 1;

    # Plugin correctly initialized
    Foswiki::Func::writeDebug( "- Foswiki::Plugins::${pluginName}::initPlugin( $web.$topic ) is OK" ) if $debug;
    return 1;
}
 
sub readBibliography
{
  # read the references topics:
  my @referencesTopics = @_;

  my %bibliography;
  my ($key, $value, $topic);

  foreach $topic (@referencesTopics)
  {
    Foswiki::Func::writeDebug("readBibliography:: reading $topic") if $debug;

    $_ = Foswiki::Func::readTopicText($web, $topic, "", 1);
    Foswiki::Func::writeDebug($_) if $debug;
    while (m/^\|([^\|]*)\|([^\|]*)\|/gm)
    {
      ($key,$value) = ($1,$2);
      
      # remove leading and trailing whitespaces from $key and from $value
      $key   =~ s/^\s+|\s+$//g; 
      $value =~ s/^\s+|\s+$//g;

      $bibliography{$key} = {  "name" => $value,
                              "cited" => 0,
                              "order" => 0
                            };
      Foswiki::Func::writeDebug("Adding key $key") if $debug;
    }
  }

  Foswiki::Func::writeDebug("ended reading bibliography topics") if $debug;
  return %bibliography;

}

sub bibliographyAlphaSort
{
  return lc($bibliography{$a}{"name"}) cmp lc($bibliography{$b}{"name"});
}

sub bibliographyOrderSort
{
  return $bibliography{$a}{"order"} <=> $bibliography{$b}{"order"};
}

sub generateBibliography
{
  my ($header, %bibliography) = @_;

  # could give decent class names
  my $list = "<ol> \n";
  foreach $key (sort bibliographyOrderSort (keys %bibliography))
  {
    my $name = $bibliography{$key}{"name"};
    $list .= "<li> $name </li> \n";
  }
  $list .= "</ol> \n";
 
  return Foswiki::Func::renderText($header) . "\n" . $list;
}

sub parseArgs
{
  my $args = $_[0];

  # get the typed header. Defaults to the BIBLIOGRAPHYPLUGIN_DEFAULTHEADER setting.
  my $header = &Foswiki::Func::getPreferencesValue("BIBLIOGRAPHYPLUGIN_DEFAULTHEADER");
  if ($args =~ m/header="([^"]*)"/)
  {
    $header = $1;
  }

  #get the typed references topic. Defaults do the BIBLIOGRAPHYPLUGIN_DEFAULTBIBLIOGRAPHYTOPIC.
  my $referencesTopics = &Foswiki::Func::getPreferencesValue("BIBLIOGRAPHYPLUGIN_DEFAULTBIBLIOGRAPHYTOPIC");
  if ($args =~ m/referencesTopic="([^"]*)"/)
  {
    $referencesTopics = $1;
  }
  @referencesTopics = split(/\s*,\s*/,$referencesTopics);

  # get the typed order. Defaults to BIBLIOGRAPHYPLUGIN_DEFAULTSORTING setting.
  my $order = &Foswiki::Func::getPreferencesValue("BIBLIOGRAPHYPLUGIN_DEFAULTSORTING");
  if ($args =~ m/order="([^"]*)"/)
  {
    $order = $1;
  }

  return ($header, $order, @referencesTopics);
}


sub handleCitation
{
  my ($cit, %bibliography) = @_;
  if (exists $bibliography{$cit})
  {
    return "[" . $bibliography{$cit}{"order"}. "]";
  }
  else
  {
    return "[??]";
  }
}

# was startRenderingHandler before. changed to preRenderingHandler as indicated
# in Foswiki:Extensions/DeprecatedHandlers.
sub preRenderingHandler
{
### my ( $text, $web ) = @_;   # do not uncomment, use $_[0], $_[1] instead

    Foswiki::Func::writeDebug( "- ${pluginName}::startRenderingHandler( $_[1] )" ) if $debug;

    # This handler is called by getRenderedVersion just before the line loop

    # do custom extension rule, like for example:
    # $_[0] =~ s/old/new/g;
    
    my ($header, @referencesTopics, $order);
    if ($_[0] =~ m/%BIBLIOGRAPHY{([^}]*)}%/mg)
    {
      ($header, $order, @referencesTopics) = parseArgs ($1);
      %bibliography = readBibliography (@referencesTopics);
    }
    else
    {
      ($header, $order, @referencesTopics) = parseArgs ("");
      %bibliography= ();
    }

    ######################################################

    # mark cited entries:
    my $i = 1;
    $_ = $_[0];
    while (m/%CITE(INLINE)?{([^}]*)}%/mg)
    {
      if ($1) {
        # was a %CITEINLINE{...}%:
        if (not (exists $bibliography{$2}))
        {
          $bibliography{$2}{"name"} = $2;
          $bibliography{$2}{"cited"} = 1;
          $bibliography{$2}{"order"} = $i++;
        }
      }
      else
      {
        # was a %CITE{...}%
        if (exists $bibliography{$2})
        {
          if (not $bibliography{$2}{"cited"})
          {
            $bibliography{$2}{"cited"} = 1;
            $bibliography{$2}{"order"} = $i++; # citation order
          }
        }
      }
    }

    # delete non-cited entries:
    foreach $key (keys %bibliography)
    {
      if (not $bibliography{$key}{"cited"})
      {
        delete $bibliography{$key};
      }
    }

    #if needed, resort the cited entries for generating the numeration
    if ($order eq "alpha")
    {
      my $i = 1;
      foreach $key (sort bibliographyAlphaSort (keys %bibliography))
      {
        $bibliography{$key}{"order"} = $i++;
      }
    }
    
    $_[0] =~ s/%CITE(INLINE)?{([^}]*)}%/&handleCitation($2,%bibliography)/ge;
    $_[0] =~ s/%BIBLIOGRAPHY{([^}]*)}%/&generateBibliography($header, %bibliography)/ge;
}

1;
