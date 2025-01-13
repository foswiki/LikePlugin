# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# LikePlugin is Copyright (C) 2015-2025 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::LikePlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::JQueryPlugin ();
use Foswiki::Contrib::JsonRpcContrib ();

our $VERSION = '3.10';
our $RELEASE = '%$RELEASE%';
our $SHORTDESCRIPTION = 'Like-style voting for content';
our $LICENSECODE = '%$LICENSECODE%';
our $NO_PREFS_IN_TOPIC = 1;
our $core;
our @knownAfterLikeHandler = ();

sub initPlugin {

  Foswiki::Func::registerTagHandler('LIKE', sub { return getCore()->LIKE(@_); });
  Foswiki::Plugins::JQueryPlugin::registerPlugin('Like', 'Foswiki::Plugins::LikePlugin::JQUERY');
  Foswiki::Contrib::JsonRpcContrib::registerMethod("LikePlugin", "vote", sub {
    return getCore()->jsonRpcVote(@_);
  });

  if (exists $Foswiki::cfg{Plugins}{SolrPlugin} && $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
    require Foswiki::Plugins::SolrPlugin;
    Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(sub {
      return getCore()->solrIndexTopicHandler(@_);
    });
  }

  if (exists $Foswiki::cfg{Plugins}{DBCachePlugin} && $Foswiki::cfg{Plugins}{DBCachePlugin}{Enabled}) {
    require Foswiki::Plugins::DBCachePlugin;
    Foswiki::Plugins::DBCachePlugin::registerIndexTopicHandler(sub {
      return getCore()->dbcacheIndexTopicHandler(@_);
    });
  }

  return 1;
}

sub afterRenameHandler {
  return getCore()->afterRenameHandler(@_);
}

sub getCore {
  unless (defined $core) {
    require Foswiki::Plugins::LikePlugin::Core;
    $core = new Foswiki::Plugins::LikePlugin::Core();
  }
  return $core;
}

sub registerAfterLikeHandler {
  push @knownAfterLikeHandler, shift;
}

sub finishPlugin {
  undef $core;

  @knownAfterLikeHandler = ();
}

1;
