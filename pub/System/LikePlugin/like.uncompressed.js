/*
 * jQuery like plugin 0.02
 *
 * Copyright (c) 2015 Michael Daum http://michaeldaumconsulting.com
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */

;(function($, window, document) {

  // default options
  var defaults = { };

  // constructor 
  function Like(elem, opts) { 
    var self = this;

    self.elem = $(elem); 

    // gather opts 
    self.opts = $.extend({}, defaults, self.elem.data(), opts); 
    self.init(); 
  } 

  // init
  Like.prototype.init = function () { 
    var self = this;

    self.likeButton = self.elem.find(".jqLikeButton");
    self.dislikeButton = self.elem.find(".jqDislikeButton");
    self.likes = self.opts.likes;
    self.dislikes = self.opts.dislikes;

    self.likeButton.on("click", function() {
      if (self.likeButton.is(".selected")) {
        self.vote(0);
      } else {
        self.vote(1);
      }
      return false;
    });

    self.dislikeButton.on("click", function() {
      if (self.dislikeButton.is(".selected")) {
        self.vote(0);
      } else {
        self.vote(-1);
      }
      return false;
    });

    $(document).on("change.likes", function(ev, opts) {
      if (typeof(opts) !== 'undefined') {
        if (opts.web === self.opts.web &&
            opts.topic === self.opts.topic &&
            opts.metaType === self.opts.metaType &&
            opts.metaId === self.opts.metaId) {
          self.update(opts.likes, opts.dislikes);
        }
      }
    });
  }; 

  // record vote 
  Like.prototype.vote = function(flag) {
    var self = this;
    flag = parseInt(flag, 10);
    self.hideMessages();
    $.jsonRpc(foswiki.getScriptUrl("jsonrpc"), {
      namespace: "LikePlugin",
      method: "vote",
      params: {
        topic: self.opts.web+'.'+self.opts.topic,
        metaType: self.opts.metaType,
        metaId: self.opts.metaId,
        like: flag>0?1:0,
        dislike: flag<0?1:0
      },
      beforeSend: function() {
        if (!self.elem.data("blockUI.isBlocked")) {
          self.elem.block({message:''});
        }
      },
      success: function(json, textStatus, xhr) {
        self.elem.unblock();
        self.elem.trigger("change.likes", {
          web: self.opts.web,
          topic: self.opts.topic,
          metaType: self.opts.metaType,
          metaId: self.opts.metaId,
          likes: json.result.likes,
          dislikes: json.result.dislikes
        });
      },
      error: function(json, textStatus, xhr) {
        self.elem.unblock();
        self.showMessage("error", json.error.message);
        console.error(json.error.message);
      }
    });
  };

  // update 
  Like.prototype.update = function(likes, dislikes) {
    var self = this,
        likeLabelElem = self.likeButton.find(".jqLikeLabel"),
        dislikeLabelElem = self.dislikeButton.find(".jqLikeLabel");

    self.likeButton.removeClass(self.opts.selectedClass);
    self.dislikeButton.removeClass(self.opts.selectedClass);
    likeLabelElem.html(decodeURIComponent(self.opts.likeLabel));
    dislikeLabelElem.html(decodeURIComponent(self.opts.dislikeLabel));

    if (self.likes < likes) {
      self.likeButton.addClass(self.opts.selectedClass);
      likeLabelElem.html(decodeURIComponent(self.opts.likedLabel));
    } 

    if (self.dislikes < dislikes) {
      self.dislikeButton.addClass(self.opts.selectedClass);
      dislikeLabelElem.html(decodeURIComponent(self.opts.dislikedLabel));
    }

    self.likeButton.find(".jqLikeCount").text(likes);
    self.dislikeButton.find(".jqLikeCount").text(dislikes);

    self.likes = likes;
    self.dislikes = dislikes;
  };

  // messaging
  Like.prototype.showMessage = function(type, msg, title) {
    $.pnotify({
      title: title,
      text: msg,
      hide: (type === "error" ? false : true),
      type: type,
      sticker: false,
      closer_hover: false,
      delay: (type === "error" ? 8000 : 2000)
    });
  };

  Like.prototype.hideMessages = function() {
    $.pnotify_remove_all();
  };

  // make it a jquery plugin
  $.fn.like = function (opts) { 
    return this.each(function () { 
      if (!$.data(this, "_like")) { 
        $.data(this, "_like", new Like(this, opts)); 
      } 
    }); 
  } 

  // Enable declarative widget instanziation 
  $(".jqLike.editable:not(.jqLikeInited)").livequery(function() {
    $(this).addClass("jqLikeInited").like();
  });

})(jQuery, window, document);
