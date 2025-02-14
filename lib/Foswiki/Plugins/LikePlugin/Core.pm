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

package Foswiki::Plugins::LikePlugin::Core;

=begin TML

---+ package Foswiki::Plugins::LikePlugin::Core

Core of the plugin. There can only be one.

=cut

use strict;
use warnings;

use Foswiki::Plugins::LikePlugin ();
use Foswiki::DBI ();
use Foswiki::Func ();
use Error qw(:try);
use Encode ();
use DBI ();

use constant TRACE => 0; # toggle me

our %SQL_TEMPLATES = (
  'insert_like' => <<'HERE',
      replace into LikePlugin_likes
        (web, topic, meta_type, meta_id, username, like_count, dislike_count, timestamp) values 
        (?, ?, ?, ?, ?, ?, ?, ?)
HERE

  'select_like_of_user' => <<'HERE',
      select like_count, dislike_count from LikePlugin_likes where 
        web = ? and 
        topic = ? and 
        meta_type = ? and
        meta_id = ? and
        username = ?
HERE
  'select_likes' => <<'HERE',
      select sum(like_count), sum(dislike_count), sum(like_count)-sum(dislike_count) from LikePlugin_likes where
        web = ? and 
        topic = ? and 
        meta_type = ? and
        meta_id = ? 
HERE
  'rename_meta' => <<'HERE',
      update LikePlugin_likes 
        set meta_id = ?, web = ?, topic = ?  where 
        web = ? and
        topic = ? and 
        meta_type = ? and
        meta_id = ? 
HERE
  'rename_topic' => <<'HERE',
      update LikePlugin_likes 
        set web = ?, topic = ?  where 
        web = ? and
        topic = ? 
HERE
);

=begin TML

---++ ClassMethod new() -> $core

constructor for a Core object

=cut

sub new {
  my $class = shift;

  my $this = bless({
    themes => $Foswiki::cfg{LikePlugin}{Themes} || {
      default => {
        wrapperClass => "jqLikeDefault",
        selectionClass => "selected",
      },
      flat => {
        wrapperClass => "jqLikeDefault jqLikeFlat",
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

  return $this;
}

=begin TML

---++ ObjectMethod finish() 

deconstruct this object

=cut

sub finish {
  my $this = shift;

  if ($this->{_sths}) {
    foreach my $sth (values %{$this->{_sths}}) {
      $sth->finish;
    }
  }

  undef $this->{_sths};
  undef $this->{_db};
}

=begin TML

---++ ObjectMethod db() - $db

create db based on dbi schema

=cut

sub db {
  my $this = shift;

  $this->{_db} = Foswiki::DBI::loadSchema("Foswiki::Plugins::LikePlugin::Schema")
    unless $this->{_db};

  return $this->{_db};
}

=begin TML

---++ ObjectMethod getStatementHandler($id) -> $sth

get sql statement handler for the stored templates 

=cut

sub getStatementHandler {
  my ($this, $id) = @_;

  my $sth = $this->{_sths}{$id};

  unless (defined $sth) {
    my $statement = $SQL_TEMPLATES{$id};

    throw Error::Simple("unknown statement id '$id'") unless $statement;

    $sth = $this->{_sths}{$id} = $this->db->handler->prepare_cached($statement);
  }

  return $sth;
}

=begin TML

---++ ObjectMethod LIKE($session, $params, $topic, $web) -> $string

implements the =%LIKE= macro

=cut

sub LIKE {
  my ($this, $session, $params, $topic, $web) = @_;

  #_writeDebug("called LIKE()");

  my ($theWeb, $theTopic) = Foswiki::Func::normalizeWebTopicName($params->{web} || $web, $params->{_DEFAULT} || $params->{topic} || $topic);
  my $metaType = $params->{type};
  my $metaId = $params->{id};
  my $hideNull = Foswiki::Func::isTrue($params->{hidenull}, 0);

  my ($likeCount, $dislikeCount) = $this->getLikes($theWeb, $theTopic, $metaType, $metaId);
  return "" if $hideNull && !$likeCount && !$dislikeCount;

  my $context = Foswiki::Func::getContext();
  my $editable = (Foswiki::Func::isTrue($params->{editable}, 1) && !$context->{static} && $context->{authenticated})?"editable":"";

  my $myLike = 0;
  my $myDislike = 0;

  ($myLike, $myDislike) = $this->getLikeOfUser($theWeb, $theTopic, $metaType, $metaId)
    if $editable;

  my $likeSelected = ($myLike > 0)?'%selectionClass%':'';
  my $dislikeSelected = ($myDislike > 0)?'%selectionClass%':'';

  my $result = $params->{format} // "<div class='jqLike %class% %wrapperClass% %editable%' %params%>%like%%dislike%</div>";

  my $showCount = Foswiki::Func::isTrue($params->{showcount}, 1);
  my $countFormat = $showCount?"<span class='jqLikeCount %counterClass%'>%num%</span>":"";

  my $tooltip = $params->{tooltip} // $session->i18n->maketext("Click to vote");
  $tooltip = $editable?"title='$tooltip'":"";

  my $likeFormat = $params->{likeformat} // "<div class='jqLikeButton %buttonClass% %likeSelected%'><span class='jqLikeButtonText %buttonText%'><a href='#' %tooltip%>%likeIcon%%thisLikeLabel%</a>%count%</span></div>";
  $likeFormat =~ s/%count%/$countFormat/g;
  $likeFormat =~ s/%num%/%likeCount%/g;
  $likeFormat =~ s/%tooltip%/$tooltip/g;

  my $showDislike = Foswiki::Func::isTrue($params->{showdislike}, 1);
  my $dislikeFormat = $showDislike?$params->{dislikeformat} // "<div class='jqDislikeButton %buttonClass% %dislikeSelected%'><span class='jqLikeButtonText %buttonText%'><a href='#' %tooltip%'>%dislikeIcon%%thisDislikeLabel%</a>%count%</span></div>":"";
  $dislikeFormat =~ s/%count%/$countFormat/g;
  $dislikeFormat =~ s/%num%/%dislikeCount%/g;
  $dislikeFormat =~ s/%tooltip%/$tooltip/g;

  my $likeLabel = $params->{likelabel} // $session->i18n->maketext("I like this");
  my $likedLabel = $params->{likedlabel} // $likeLabel;
  my $thisLikeLabel = $myLike > 0?$likedLabel:$likeLabel;
  $thisLikeLabel = $thisLikeLabel?"<span class='jqLikeLabel'>$thisLikeLabel</span>":"";

  my $dislikeLabel = $showDislike?$params->{dislikelabel} // $session->i18n->maketext("I don&#39;t like this"):"";
  my $dislikedLabel = $showDislike?$params->{dislikelabel} // $dislikeLabel:"";
  my $thisDislikeLabel = $myDislike > 0?$dislikedLabel:$dislikeLabel;
  $thisDislikeLabel = $showDislike?($thisDislikeLabel?"<span class='jqLikeLabel'>$thisDislikeLabel</span>":""):"";

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

  my $likeIconFormat = $params->{likeiconformat} // "%JQICON{\"$likeIcon\" class=\"%iconClass%\"}%";
  $likeIcon = $likeIcon?$likeIconFormat:"";

  my $dislikeIconFormat = $params->{dislikeiconformat} // "%JQICON{\"$dislikeIcon\" class=\"%iconClass%\"}%";
  $dislikeIcon = $dislikeIcon?$dislikeIconFormat:"";

  my $showIcon = Foswiki::Func::isTrue($params->{showicon}, 1);
  unless ($showIcon) {
    $likeIcon = "";
    $dislikeIcon = "";
  }

  my @html5Params = ();
  push @html5Params, "data-web='$theWeb'";
  push @html5Params, "data-topic='$theTopic'";
  push @html5Params, "data-meta-type='$metaType'" if $metaType;
  push @html5Params, "data-meta-id='$metaId'" if $metaId;
  push @html5Params, "data-like-label='"._urlEncode($likeLabel)."'" if $likeLabel;
  push @html5Params, "data-liked-label='"._urlEncode($likedLabel)."'" if $likedLabel;
  push @html5Params, "data-dislike-label='"._urlEncode($dislikeLabel)."'" if $dislikeLabel;
  push @html5Params, "data-disliked-label='"._urlEncode($dislikedLabel)."'" if $dislikedLabel;
  push @html5Params, "data-likes='$likeCount'";
  push @html5Params, "data-dislikes='$dislikeCount'";
  push @html5Params, "data-selected-class='%selectionClass%'";
  my $html5Params = join(" ",@html5Params);

  my $class = $params->{class} // "";

  my $totalLikes = $likeCount - $dislikeCount;
 
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
  $result =~ s/%totalLikeCount%/$totalLikes/g;
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
    my $val = $params->{lc($key)} || $theme->{$key} || '';
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

=begin TML

---++ ObjectMethod getTheme($name) -> $record

returns the theme description for the given name 

=cut

sub getTheme {
  my ($this, $name) = @_;

  $name ||= 'default';
  return $this->{themes}{$name} || $this->{themes}{default};
}

=begin TML

---++ ObjectMethod jsonRpcVote($session, $request) -> $responseJson

JSON-RPC handler for the vote method

=cut

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

  my $metaType = $request->param("type") || '';
  my $metaId = $request->param("id") || '';

  my $like = $request->param("like") || 0;
  my $dislike= $request->param("dislike") || 0;

  _writeDebug("called jsonRpcVote(), topic=$web.$topic, userName=$userName, like=$like, dislike=$dislike");

  my ($likes, $dislikes) = $this->like({
    web => $web,
    topic => $topic,
    metaType => $metaType,
    metaId => $metaId,
    userName => $userName,
    like => $like,
    dislike => $dislike,
  });

  if ($Foswiki::cfg{Plugins}{WebSocketPlugin}{Enabled}) {
    # trigger event
    my $clientId= $request->param("clientId") || 'server';
    require Foswiki::Plugins::WebSocketPlugin;
    Foswiki::Plugins::WebSocketPlugin::publish("$web.$topic", {
      type => "like",
      clientId => $clientId,
      data => {
        like => int($like),
        dislike => int($dislike),
        metaType => $metaType,
        metaId => $metaId,
      }
    });
  } else {
    # trigger solr indexer ourselves
    if ($Foswiki::cfg{Plugins}{SolrPlugin} && $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
      require Foswiki::Plugins::SolrPlugin;
      my $indexer = Foswiki::Plugins::SolrPlugin::getIndexer();
      $indexer->indexTopic($web, $topic);
    }
  }

  # trigger dbcache indexer
  if ($Foswiki::cfg{Plugins}{DBCachePlugin}{Enabled}) {
    require Foswiki::Plugins::DBCachePlugin;
    my $db = Foswiki::Plugins::DBCachePlugin::getDB($web);
    my $obj = $db->fastget($topic);
    $obj->set(".cache_time",0); # enforce a refresh
    $db->loadTopic($web, $topic);
  }

  # log event
  $session->logger->log( {
    level    => 'info',
    action   => $like?'like':'dislike',
    webTopic => "$web.$topic",
    extra    => "total likes=".($likes - $dislikes),
  });

  return {
    likes => $likes,
    dislikes => $dislikes,
  };
}

=begin TML

---++ ObjectMethod like($record) -> ($likes, $dislikes)

adds a like record to the db and returns an array of likes, dislikes counter

=cut

sub like {
  my ($this, $record) = @_;

  my $sth = $this->getStatementHandler("insert_like");

  $record->{userName} ||=  Foswiki::Func::getWikiName();
  $record->{timestamp} ||= time();

  $record->{like} = $record->{like}?1:0;
  $record->{dislike} = $record->{dislike}?1:0;

  $sth->execute(
    # web, topic, meta_type, meta_id, username, like, dislike, timestamp
    $record->{web},
    $record->{topic},
    $record->{metaType},
    $record->{metaId},
    $record->{userName},
    $record->{like},
    $record->{dislike},
    $record->{timestamp},
  );

  my ($likes, $dislikes) = $this->getLikes($record->{web}, $record->{topic}, $record->{metaType}, $record->{metaId});

  # call after like handlers
  my %seen;
  foreach my $sub (@Foswiki::Plugins::LikePlugin::knownAfterLikeHandler) {
    next if $seen{$sub};
    &$sub($record->{web}, $record->{topic}, $record->{metaType}, $record->{metaId}, $record->{userName}, $likes, $dislikes);
    $seen{$sub} = 1;
  }

  return ($likes, $dislikes);
}

=begin TML

---++ ObjectMethod getLikes($web, $topic, $type, $id) -> ($likes, $dislikes)

returns an array of two counters likes and dislikes

=cut

sub getLikes {
  my ($this, $web, $topic, $type, $id) = @_;

  $type ||= '';
  $id ||= '';
  $web =~ s/\//./g;

  my $sth = $this->getStatementHandler("select_likes");
  my ($like, $dislike) = $this->db->handler->selectrow_array($sth, undef, $web, $topic, $type, $id);

  $like ||= 0;
  $dislike ||= 0;

  return ($like, $dislike);
}

=begin TML

---++ ObjectMethod getLikeOfUser($web, $topic, $type, $id, $wikiName) -> ($likes, $dislikes)

return the likes of a given user

=cut

sub getLikeOfUser {
  my ($this, $web, $topic, $type, $id, $wikiName) = @_;

  $type ||= '';
  $id ||= '';
  $wikiName ||= Foswiki::Func::getWikiName();
  $web =~ s/\//./g;

  my $sth = $this->getStatementHandler("select_like_of_user");
  my ($likes, $dislikes) = $this->db->handler->selectrow_array($sth, undef, $web, $topic, $type, $id, $wikiName);

  $likes ||= 0;
  $dislikes ||= 0;

  return ($likes, $dislikes);
}

=begin TML

---++ ObjectMethod solrIndexTopicHandler($indexer, $doc, $web, $topic, $meta, $text) 

solr handler adding likes to the index

=cut

sub solrIndexTopicHandler {
  my ($this, $indexer, $doc, $web, $topic, $meta, $text) = @_;

  $web =~ s/\//./g;

  my $sth = $this->getStatementHandler("select_likes");
  my ($likes, $dislikes, $totalLikes) = $this->db->handler->selectrow_array($sth, undef, $web, $topic, "", "");

  $likes ||= 0;
  $dislikes ||= 0;
  $totalLikes ||= 0;

  #print STDERR "likes=$likes, dislikes=$dislikes, totalLikes=$totalLikes\n";

  $doc->add_fields(
    'likes' => $likes,
    'dislikes' => $dislikes,
    'total_likes' => $totalLikes,
  );
}

=begin TML

---++ ObjectMethod dbcacheIndexTopicHandler($db, $obj, $web, $topic, $meta, $text) 

dbcache handler adding likes to the dbcache

=cut

sub dbcacheIndexTopicHandler {
  my ($this, $db, $obj, $web, $topic, $meta, $text) = @_;

  $web =~ s/\//./g;

  my $sth = $this->getStatementHandler("select_likes");
  my ($likes, $dislikes, $totalLikes) = $this->db->handler->selectrow_array($sth, undef, $web, $topic, "", "");

  $likes ||= 0;
  $dislikes ||= 0;
  $totalLikes ||= 0;

  #print STDERR "web=$web, topic=$topic, like=$likes, dislike=$dislikes, totalLike=$totalLikes\n";

  $obj->set("likes", $likes);
  $obj->set("dislikes", $dislikes);
  $obj->set("total_likes", $totalLikes);
}

=begin TML

---++ ObjectMethod afterRenameHandler($oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) 

this handler is called whenever an object on Foswiki is renamed. the callback will then maintain the database
records associated with this object and rename the records accordingly

=cut

sub afterRenameHandler {
  my ($this, $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

  _writeDebug("called afterRenameHandler($oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment)");

  if ($oldAttachment && $newAttachment) {
    _writeDebug("rename attachment");
    my $sth = $this->getStatementHandler("rename_meta");
    $sth->execute(
      $newAttachment, $newWeb, $newTopic,
      $oldWeb, $oldTopic, "FILEATTACHMENT", $oldAttachment
    );
  } else {
    my $sth = $this->getStatementHandler("rename_topic");
    $sth->execute(
        $newWeb, $newTopic, 
        $oldWeb, $oldTopic
    );
  }
}

# static helper

sub _urlEncode {
  my $text = shift;

  $text = Encode::encode($Foswiki::cfg{Site}{CharSet}, $text);
  $text =~ s{([^0-9a-zA-Z-_.:~!*#/])}{sprintf('%%%02x',ord($1))}ge;

  return $text;
}

sub _writeDebug {
  return unless TRACE;
  print STDERR "LikePlugin::Core - $_[0]\n";
}

1;
