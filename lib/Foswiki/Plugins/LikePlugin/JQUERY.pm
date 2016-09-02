# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# BookPlugin is Copyright (C) 2015-2016 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::LikePlugin::JQUERY;

use strict;
use warnings;

use Foswiki::Plugins ();
use Foswiki::Plugins::JQueryPlugin::Plugin ();

our @ISA = qw( Foswiki::Plugins::JQueryPlugin::Plugin );

sub new {
  my $class = shift;
  my $session = shift || $Foswiki::Plugins::SESSION;

  my $this = bless(
    $class->SUPER::new(
      $session,
      name => 'Like',
      version => '1.00',
      author => 'Michael Daum',
      homepage => 'http://foswiki.org/Extensions/LikePlugin',
      puburl => '%PUBURLPATH%/%SYSTEMWEB%/LikePlugin',
      documentation => '%SYSTEMWEB%.LikePlugin',
      javascript => ['like.js'],
      css => ['like.css'],
      dependencies => ['jsonrpc', 'blockui', 'livequery', 'pnotify'],
    ),
    $class
  );


  return $this;
}

1;

