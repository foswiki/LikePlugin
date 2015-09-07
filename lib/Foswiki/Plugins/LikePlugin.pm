# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# LikePlugin is Copyright (C) 2015 Michael Daum http://michaeldaumconsulting.com
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

our $VERSION = '0.01';
our $RELEASE = '07 Sep 2015';
our $SHORTDESCRIPTION = 'Like-style voting for content';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

sub initPlugin {

  Foswiki::Func::registerTagHandler('LIKE', sub { return core()->LIKE(@_); });
  Foswiki::Plugins::JQueryPlugin::registerPlugin('Like', 'Foswiki::Plugins::LikePlugin::JQUERY');
  Foswiki::Contrib::JsonRpcContrib::registerMethod("LikePlugin", "vote", sub {
    return core()->jsonRpcVote(@_);
  });

  return 1;
}

sub core {
  unless (defined $core) {
    require Foswiki::Plugins::LikePlugin::Core;
    $core = new Foswiki::Plugins::LikePlugin::Core();
  }
  return $core;
}

sub finishPlugin {
  undef $core;
}

1;
