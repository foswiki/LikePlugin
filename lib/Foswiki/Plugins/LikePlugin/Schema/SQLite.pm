# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# LikePlugin is Copyright (C) 2021-2024 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::LikePlugin::Schema::SQLite;

use strict;
use warnings;

use Foswiki::Plugins::LikePlugin::Schema;
our @ISA = ('Foswiki::Plugins::LikePlugin::Schema');

sub getDefinition {
  return [[
      'CREATE TABLE IF NOT EXISTS %prefix%likes (
        id INTEGER PRIMARY KEY,
        web VARCHAR(255),
        topic VARCHAR(255),
        meta_type CHAR(20), 
        meta_id CHAR(255),
        username VARCHAR(255),
        like_count INTEGER DEFAULT 0,
        dislike_count INTEGER DEFAULT 0,
        timestamp INTEGER
      )',

      'CREATE UNIQUE INDEX IF NOT EXISTS %prefix%_idx_likes on %prefix%likes (web, topic, username, meta_type, meta_id)'
    ]
  ];
}

1;
