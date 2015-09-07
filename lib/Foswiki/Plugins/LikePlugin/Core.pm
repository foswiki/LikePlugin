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

package Foswiki::Plugins::LikePlugin::Core;

use strict;
use warnings;

use Foswiki::Func ();
use Error qw(:try);
use DBI ();

use constant TRACE => 0; # toggle me

our %SQL_TEMPLATES = (
  'insert_like' => <<'HERE',
      replace into %likesTable%
        (web, topic, meta_type, meta_id, username, like, dislike, timestamp) values 
        (?, ?, ?, ?, ?, ?, ?, ?)
HERE

  'select_like_of_user' => <<'HERE',
      select like, dislike from %likesTable% where 
        web = ? and 
        topic = ? and 
        meta_type = ? and
        meta_id = ? and
        username = ?
HERE

  'select_likes' => <<'HERE',
      select sum(like), sum(dislike), sum(like)-sum(dislike) from %likesTable% where
        web = ? and 
        topic = ? and 
        meta_type = ? and
        meta_id = ? 
HERE
);

###############################################################################
sub writeDebug {
  return unless TRACE;
  #Foswiki::Func::writeDebug("LikePlugin::Core - $_[0]");
  print STDERR "LikePlugin::Core - $_[0]\n";
}

###############################################################################
sub new {
  my $class = shift;

  my $this = bless({
    dsn => $Foswiki::cfg{LikePlugin}{Database}{DSN} || 'dbi:SQLite:dbname=' . Foswiki::Func::getWorkArea('LikePlugin') . '/likes.db',
    username => $Foswiki::cfg{LikePlugin}{Database}{UserName},
    password => $Foswiki::cfg{LikePlugin}{Database}{Password},
    tablePrefix => $Foswiki::cfg{LikePlugin}{Database}{TablePrefix} || 'foswiki_',
    themes => $Foswiki::cfg{LikePlugin}{Themes} || {
      default => {
        wrapperClass => "jqLikeDefault",
        selectionClass => "selected",
      },
      padding => {
        wrapperClass => "jqLikeDefault jqLikePadding",
        selectionClass => "selected",
      },
      lightgray => {
        wrapperClass => "jqLikeDefault jqLikeLightGray",
        selectionClass => "selected",
      },
      gray => {
        wrapperClass => "jqLikeDefault jqLikeGray",
        selectionClass => "selected",
      },
      black => {
        wrapperClass => "jqLikeDefault jqLikeBlack",
        selectionClass => "selected",
      },
      simple => {
        wrapperClass => "jqLikeSimple",
        selectionClass => "selected",
      },
      pattern => {
        wrapperClass => "jqLikePattern",
        selectionClass => "selected",
      },
      ui => {
        wrapperClass => "jqLikeUI ui-widget ui-like",
        buttonClass => "ui-button ui-widget ui-state-default ui-corner-all ui-button-text-icon-primary" ,
        buttonText => "ui-button-text",
        iconClass => "ui-button-icon-primary ui-icon",
        selectionClass => "selected ui-state-highlight",
      }
    },
    @_
  }, $class);

  $this->{likesTable} = $this->{tablePrefix}.'likes';

  return $this;
}

###############################################################################
sub finish {
  my $this = shift;

  if ($this->{sths}) {
    foreach my $sth (values %{$this->{sths}}) {
      $sth->finish;
    }
    $this->{sths} = undef;
  }

  $this->{dbh}->disconnect if defined $this->{dbh};
  $this->{dbh} = undef;
}

###############################################################################
sub initDatabase {
  my $this = shift;

  unless (defined $this->{dbh}) {

    writeDebug("connect database");
    $this->{dbh} = DBI->connect(
      $this->{dsn},
      $this->{username},
      $this->{password},
      {
        PrintError => 0,
        RaiseError => 1,
        AutoCommit => 1,
        ShowErrorStatement => 1,
      }
    );

    throw Error::Simple("Can't open database $this->{dsn}: " . $DBI::errstr)
      unless defined $this->{dbh};

    #writeDebug("creating likes table");
    $this->{dbh}->do(<<HERE);
      create table if not exists $this->{likesTable} (
        id integer primary key autoincrement,
        web varchar(255),
        topic varchar(255),
        meta_type char(20), 
        meta_id char(20),
        username varchar(255),
        like integer default 0,
        dislike integer default 0,
        timestamp integer
      )
HERE
      $this->{dbh}->do(<<HERE);
      create unique index if not exists $this->{likesTable}_index on $this->{likesTable} (web, topic, username, meta_type, meta_id)
HERE

  }

  return $this->{dbh};
}


###############################################################################
sub getStatementHandler {
  my ($this, $id) = @_;

  my $sth = $this->{sths}{$id};

  unless (defined $sth) {
    my $statement = $SQL_TEMPLATES{$id};

    throw Error::Simple("unknown statement id '$id'") unless $statement;

    $statement =~ s/\%(likesTable)\%/$this->{$1}/g;

    $sth = $this->{sths}{$id} = $this->{dbh}->prepare($statement);
  }

  return $sth;
}

###############################################################################
sub LIKE {
  my ($this, $session, $params, $topic, $web) = @_;

  writeDebug("called LIKE()");

  my ($theWeb, $theTopic) = Foswiki::Func::normalizeWebTopicName($params->{web} || $web, $params->{_DEFAULT} || $params->{topic} || $topic);
  my $type = $params->{type};
  my $id = $params->{id};
  my $hideNull = Foswiki::Func::isTrue($params->{hidenull}, 0);

  $this->initDatabase;

  my ($likeCount, $dislikeCount) = $this->getLikes($theWeb, $theTopic, $type, $id);
  return "" if $hideNull && !$likeCount && !$dislikeCount;

  my $context = Foswiki::Func::getContext();
  my $editable = (!$context->{static} && $context->{authenticated})?"editable":"";

  my $myLike = 0;
  my $myDislike = 0;

  ($myLike, $myDislike) = $this->getLikeOfUser($theWeb, $theTopic, $type, $id)
    if $editable;

  my $likeSelected = ($myLike > 0)?'%selectionClass%':'';
  my $dislikeSelected = ($myDislike > 0)?'%selectionClass%':'';

  my $result = $params->{format} // "<div class='jqLike %class% %wrapperClass% %editable%' %params%>%like%%dislike%</div>";

  my $showCount = Foswiki::Func::isTrue($params->{showcount}, 1);
  my $countFormat = $showCount?"<span class='jqLikeCount %counterClass%'>%num%</span>":"";

  my $likeFormat = $params->{likeformat} // "<div class='jqLikeButton %buttonClass% %likeSelected%'><span class='jqLikeButtonText %buttonText%'><a href='#' title='%MAKETEXT{\"Click to vote\"}%'>%likeIcon%%thisLikeLabel%</a>%count%</span></div>";
  $likeFormat =~ s/%count%/$countFormat/g;
  $likeFormat =~ s/%num%/%likeCount%/g;

  my $showDislike = Foswiki::Func::isTrue($params->{showdislike}, 1);
  my $dislikeFormat = $showDislike?$params->{dislikeformat} // "<div class='jqDislikeButton %buttonClass% %dislikeSelected%'><spal class='jqLikeButtonText %buttonText%'><a href='#' title='%MAKETEXT{\"Click to vote\"}%'>%dislikeIcon%%thisDislikeLabel%</a>%count%</span></div>":"";
  $dislikeFormat =~ s/%count%/$countFormat/g;
  $dislikeFormat =~ s/%num%/%dislikeCount%/g;

  my $likeLabel = $params->{likelabel} // '%MAKETEXT{"I like this"}%';
  my $likedLabel = $params->{likedlabel} // $likeLabel;
  my $thisLikeLabel = $myLike > 0?$likedLabel:$likeLabel;
  $thisLikeLabel = $thisLikeLabel?"<span class='jqLikeLabel'>$thisLikeLabel</span>":"";

  my $dislikeLabel = $params->{dislikelabel} // '%MAKETEXT{"I don&#39;t like this"}%';
  my $dislikedLabel = $params->{dislikelabel} // $dislikeLabel;
  my $thisDislikeLabel = $myDislike > 0?$dislikedLabel:$dislikeLabel;
  $thisDislikeLabel = $thisDislikeLabel?"<span class='jqLikeLabel'>$thisDislikeLabel</span>":"";

  my $showLabel = Foswiki::Func::isTrue($params->{showlabel}, 1);
  unless ($showLabel) {
    $likeLabel = "";
    $likedLabel = "";
    $thisLikeLabel = "";
    $dislikeLabel = "";
    $dislikedLabel = "";
    $thisDislikeLabel = "";
  }

  my $likeIcon = $params->{likeicon} // 'fa-thumbs-up';
  my $dislikeIcon = $params->{dislikeicon} // 'fa-thumbs-down';

  $likeIcon = $likeIcon?"%JQICON{\"$likeIcon\" class=\"%iconClass%\"}%":"";
  $dislikeIcon = $dislikeIcon?"%JQICON{\"$dislikeIcon\" class=\"%iconClass%\"}%":"";

  my $showIcon = Foswiki::Func::isTrue($params->{showicon}, 1);
  unless ($showIcon) {
    $likeIcon = "";
    $dislikeIcon = "";
  }

  my $metaType = $params->{"metatype"} || '';
  my $metaId = $params->{"metaid"} || '';

  my @html5Params = ();
  push @html5Params, "data-web='$theWeb'";
  push @html5Params, "data-topic='$theTopic'";
  push @html5Params, "data-meta-type='$metaType'" if $metaType;
  push @html5Params, "data-meta-id='$metaId'" if $metaId;
  push @html5Params, "data-like-label='%ENCODE{$likeLabel}%'" if $likeLabel;
  push @html5Params, "data-liked-label='%ENCODE{$likedLabel}%'" if $likedLabel;
  push @html5Params, "data-dislike-label='%ENCODE{$dislikeLabel}%'" if $dislikeLabel;
  push @html5Params, "data-disliked-label='%ENCODE{$dislikedLabel}%'" if $dislikedLabel;
  push @html5Params, "data-likes='$likeCount'";
  push @html5Params, "data-dislikes='$dislikeCount'";
  push @html5Params, "data-selected-class='%selectionClass%'";
  my $html5Params = join(" ",@html5Params);

  my $class = $params->{class} // "";
 
  $result =~ s/%like%/$likeFormat/g;
  $result =~ s/%dislike%/$dislikeFormat/g;
  $result =~ s/%params%/$html5Params/g;

  $result =~ s/%likeLabel%/$likeLabel/g;
  $result =~ s/%likedLabel%/$likedLabel/g;
  $result =~ s/%dislikeLabel%/$dislikeLabel/g;
  $result =~ s/%dislikedLabel%/$dislikedLabel/g;
  $result =~ s/%thisLikeLabel%/$thisLikeLabel/g;
  $result =~ s/%thisDislikeLabel%/$thisDislikeLabel/g;
  $result =~ s/%likeIcon%/$likeIcon/g;
  $result =~ s/%dislikeIcon%/$dislikeIcon/g;
  $result =~ s/%likeCount%/$likeCount/g;
  $result =~ s/%dislikeCount%/$dislikeCount/g;
  $result =~ s/%likeSelected%/$likeSelected/g;
  $result =~ s/%dislikeSelected%/$dislikeSelected/g;
  $result =~ s/%editable%/$editable/g;
  $result =~ s/%web%/$theWeb/g;
  $result =~ s/%topic%/$theTopic/g;
  $result =~ s/%metaType%/$metaType/g;
  $result =~ s/%metaId%/$metaId/g;
  $result =~ s/%class%/$class/g;

  my $theme = $this->getTheme($params->{"theme"});
  foreach my $key (qw(wrapperClass buttonClass buttonText iconClass counterClass selectionClass)) {
    my $val = $theme->{$key} || '';
    $result =~ s/%$key%/$val/g;
  }

  # hack ui
  $result =~ s/ui-button-text-icon-primary/ui-button-text-only/g
    unless $showIcon;
  
  my $header = $params->{header} || '';
  my $footer = $params->{footer} || '';

  Foswiki::Plugins::JQueryPlugin::createPlugin("like");

  return Foswiki::Func::decodeFormatTokens($header.$result.$footer);
}

###############################################################################
sub getTheme {
  my ($this, $name) = @_;

  $name ||= 'default',
  return $this->{themes}{$name} || $this->{themes}{default};
}

###############################################################################
sub jsonRpcVote {
  my ($this, $session, $request) = @_;

  my $web = $session->{webName};
  my $topic = $session->{topicName};

  $web =~ s/\//./g;

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist") 
    unless Foswiki::Func::topicExists($web, $topic);

  my $userName = Foswiki::Func::getWikiName();

  if (Foswiki::Func::isAnAdmin()) {
    my $override = $request->param("username");
    $userName = $override if defined $override;
  }

  my $metaType = $request->param("meta_type") || '';
  my $metaId = $request->param("meta_id") || '';

  my $like = $request->param("like") || 0;
  my $dislike= $request->param("dislike") || 0;

  writeDebug("called jsonRpcVote(), topic=$web.$topic, userName=$userName, like=$like, dislike=$dislike");

  $this->initDatabase;

  $this->like({
    web => $web,
    topic => $topic,
    metaType => $metaType,
    metaId => $metaId,
    userName => $userName,
    like => $like,
    dislike => $dislike,
  });

  # trigger solr indexer
  if ($Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
    require Foswiki::Plugins::SolrPlugin;
    my $indexer = Foswiki::Plugins::SolrPlugin::getIndexer();
    $indexer->indexTopic($web, $topic);
  }

  # trigger dbcache indexer
  if ($Foswiki::cfg{Plugins}{DBCachePlugin}{Enabled}) {
    require Foswiki::Plugins::DBCachePlugin;
    my $db = Foswiki::Plugins::DBCachePlugin::getDB($web);
    my $obj = $db->fastget($topic);
    $obj->set(".cache_time",0); # enforce a refresh
    $db->loadTopic($web, $topic);
  }

  my ($likes, $dislikes) = $this->getLikes($web, $topic, $metaType, $metaId);

  return {
    likes => $likes,
    dislikes => $dislikes,
  };
}

###############################################################################
sub like {
  my ($this, $record) = @_;

  my $sth = $this->getStatementHandler("insert_like");
  $sth->execute(
    # web, topic, meta_type, meta_id, username, like, dislike, timestamp
    $record->{web},
    $record->{topic},
    $record->{metaType},
    $record->{metaId},
    $record->{userName} ||  Foswiki::Func::getWikiName(),
    $record->{like}?1:0,
    $record->{dislike}?1:0,
    $record->{timestamp} || time(),
  );

}

###############################################################################
sub getLikes {
  my ($this, $web, $topic, $type, $id) = @_;

  $type ||= '';
  $id ||= '';

  my $sth = $this->getStatementHandler("select_likes");
  my ($like, $dislike) = $this->{dbh}->selectrow_array($sth, undef, $web, $topic, $type, $id);

  $like ||= 0;
  $dislike ||= 0;

  return ($like, $dislike);
}

###############################################################################
sub getLikeOfUser {
  my ($this, $web, $topic, $type, $id, $wikiName) = @_;

  $type ||= '';
  $id ||= '';
  $wikiName ||= Foswiki::Func::getWikiName();

  my $sth = $this->getStatementHandler("select_like_of_user");
  my ($like, $dislike) = $this->{dbh}->selectrow_array($sth, undef, $web, $topic, $type, $id, $wikiName);

  $like ||= 0;
  $dislike ||= 0;

  return ($like, $dislike);
}

##############################################################################
sub solrIndexTopicHandler {
  my ($this, $indexer, $doc, $web, $topic, $meta, $text) = @_;

  $this->initDatabase;
  my $sth = $this->getStatementHandler("select_likes");
  my ($like, $dislike, $totalLike) = $this->{dbh}->selectrow_array($sth, undef, $web, $topic, "", "");

  #print STDERR "like=$like, dislike=$dislike, totalLike=$totalLike\n";

  $doc->add_fields(
    'field_like_i' => $like,
    'field_dislike_i' => $dislike,
    'field_total_like_i' => $totalLike,
  );
}

##############################################################################
sub dbcacheIndexTopicHandler {
  my ($this, $db, $obj, $web, $topic, $meta, $text) = @_;

  $this->initDatabase;
  my $sth = $this->getStatementHandler("select_likes");
  my ($like, $dislike, $totalLike) = $this->{dbh}->selectrow_array($sth, undef, $web, $topic, "", "");

  #print STDERR "like=$like, dislike=$dislike, totalLike=$totalLike\n";
  $obj->set("likes", $like);
  $obj->set("dislikes", $dislike);
  $obj->set("totallikes", $totalLike);
}

1;
