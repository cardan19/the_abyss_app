import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReplyItem {
  final String replierName;
  final String replierAvatar;
  final String replyText;
  final String myCommentText;
  final String threadTitle;
  final String threadUrl;
  final String timeAgo;
  final String activityText;
  final String postId;     // Disqus post ID of the child-post (reply)
  final int    cardIndex;  // DOM index of card--notification used for JS clicks

  _ReplyItem({
    required this.replierName,
    required this.replierAvatar,
    required this.replyText,
    required this.myCommentText,
    required this.threadTitle,
    required this.threadUrl,
    required this.timeAgo,
    required this.activityText,
    this.postId    = '',
    this.cardIndex = 0,
  });
}

class NotificationsScreen extends StatefulWidget {
  final void Function(String url) onNavigateToUrl;
  final bool isActive;

  const NotificationsScreen({
    super.key,
    required this.onNavigateToUrl,
    required this.isActive,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  InAppWebViewController? _hiddenWebController;

  bool _isLoading = false;
  bool _hasEverFetched = false;
  String _status = '';
  List<_ReplyItem> _allNotifs = [];
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
       // Clear the red badge when the Replies tab is accessed
       if (_tabController.index == 1 && !_hasViewedReplies) {
          setState(() {
             _hasViewedReplies = true;
          });
       }
    });

    if (widget.isActive && !_hasEverFetched && _hiddenWebController != null) {
      _startFetch();
    }
  }

  @override
  void didUpdateWidget(NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_hasEverFetched && !_isLoading) {
      _startFetch();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  bool _isLoadingMore = false;
  bool _hasViewedReplies = false;

  void _startFetch() {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasEverFetched = true;
      _status = 'Syncing notifications...';
      _allNotifs.clear();
    });
    // The hidden WebView will automatically start loading and trigger onLoadStop
    _hiddenWebController?.loadUrl(
        urlRequest: URLRequest(url: WebUri('https://disqus.com/home/notifications/')));
  }

  Future<void> _loadMore() async {
    if (_hiddenWebController == null || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    // Read actual DOM count (strip JSON quotes flutter_inappwebview sometimes adds)
    final rawCount = await _hiddenWebController!.evaluateJavascript(
      source: "document.querySelectorAll('div.card--notification').length.toString();",
    );
    final int beforeCount =
        int.tryParse(rawCount?.toString().replaceAll('"', '') ?? '0') ?? 0;

    // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ RAF-based smooth scroll Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
    // Problem with scrollTo(): it's instant and may not animate through every
    // IntersectionObserver threshold that Disqus uses.
    //
    // This script:
    //  1. Walks UP from the last notification card to find the actual scrollable
    //     container (Disqus wraps its list in overflow:auto, not window).
    //  2. Resets scrollTop to 0 so the sentinel re-enters the viewport from scratch.
    //  3. Animates scrollTop to max via requestAnimationFrame over 2.5 s, firing
    //     a scroll event every frame Ã¢â‚¬â€ IntersectionObserver CANNOT miss the threshold.
    // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
    const String rafScrollJS = r'''
      (function() {
        var cards = document.querySelectorAll('div.card--notification');
        var scroller = document.documentElement;
        if (cards.length > 0) {
          var el = cards[cards.length - 1].parentNode;
          while (el && el !== document.documentElement) {
            if (el.scrollHeight > el.clientHeight + 50) { scroller = el; break; }
            el = el.parentNode;
          }
        }
        // Reset to top
        scroller.scrollTop = 0;
        try { window.scrollTo(0, 0); } catch(e) {}

        // Smooth RAF animation to bottom
        var startTime = null;
        var endPos = scroller.scrollHeight + 5000;
        var dur = 2500;
        function step(ts) {
          if (!startTime) startTime = ts;
          var t = Math.min((ts - startTime) / dur, 1);
          var eased = t < 0.5 ? 2*t*t : -1+(4-2*t)*t;
          var pos = endPos * eased;
          scroller.scrollTop = pos;
          try { window.scrollTo(0, pos); } catch(e) {}
          scroller.dispatchEvent(new Event('scroll', { bubbles: true }));
          window.dispatchEvent(new Event('scroll', { bubbles: true }));
          if (t < 1) requestAnimationFrame(step);
        }
        requestAnimationFrame(step);
      })();
    ''';

    // Fire JS RAF scroll + native scroll for belt-and-suspenders
    await _hiddenWebController!.evaluateJavascript(source: rafScrollJS);
    try {
      await _hiddenWebController!.scrollTo(x: 0, y: 0, animated: false);
      await Future.delayed(const Duration(milliseconds: 200));
      await _hiddenWebController!.scrollTo(x: 0, y: 9999999, animated: true);
    } catch (_) {}

    bool _done = false;
    int elapsed = 0;

    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_done) { timer.cancel(); return; }
      elapsed += 500;

      // Re-trigger every 5 s in case the first animation didn't reach the sentinel
      if (elapsed % 5000 == 0) {
        await _hiddenWebController!.evaluateJavascript(source: rafScrollJS);
        try { await _hiddenWebController!.scrollTo(x: 0, y: 9999999, animated: true); } catch (_) {}
      }

      try {
        final s = await _hiddenWebController!.evaluateJavascript(
          source: "document.querySelectorAll('div.card--notification').length.toString();",
        );
        final newCount =
            int.tryParse(s?.toString().replaceAll('"', '') ?? '$beforeCount') ?? beforeCount;

        if (newCount > beforeCount) {
          _done = true;
          timer.cancel();
          await _extractData(_hiddenWebController!);
          if (mounted) setState(() => _isLoadingMore = false);
          return;
        }
      } catch (_) {}

      if (elapsed >= 15000) {
        _done = true;
        timer.cancel();
        if (mounted) {
          setState(() => _isLoadingMore = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No more notifications found',
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.black87,
            duration: Duration(seconds: 2),
          ));
        }
      }
    });
  }


  void _handleLoadStop(InAppWebViewController controller, WebUri? url) {
    if (url.toString() != 'https://disqus.com/home/notifications/') return;
    
    // Start polling the DOM until notifications appear
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        final countStr = await controller.evaluateJavascript(source: "document.querySelectorAll('div.card--notification').length.toString();");
        final count = int.tryParse(countStr?.toString() ?? '0') ?? 0;
        
        if (count > 0) {
          timer.cancel();
          _extractData(controller);
        } else if (timer.tick > 20) { // 10 seconds timeout
           timer.cancel();
           
           final bodyText = await controller.evaluateJavascript(source: "document.body.innerText") ?? '';
           if (bodyText.toString().toLowerCase().contains('login') || bodyText.toString().toLowerCase().contains('sign in')) {
              if (mounted) setState(() {
                _isLoading = false;
                _status = 'Please sign in to Disqus in the Chat tab first.';
              });
           } else {
              if (mounted) setState(() {
                _isLoading = false;
                _status = 'No notifications found.';
              });
           }
        }
      } catch (e) {
        timer.cancel();
      }
    });
  }

  // extractData ...


  Future<void> _extractData(InAppWebViewController controller) async {
    const script = '''
      (function() {
        var items = [];
        var cards = document.querySelectorAll('div.card--notification');
        cards.forEach(function(item, idx) {
          try {
            var reasonDiv = item.querySelector('.card__reason');
            var actText = reasonDiv ? reasonDiv.innerText.replace(/\\n/g, ' ').replace(/\\s+/g, ' ').trim() : '';
            var timeText = item.querySelector('.card__reason .time') ? item.querySelector('.card__reason .time').innerText : '';
            
            var threadTitle = '';
            var threadUrl = '';

            var threadLink = item.querySelector('.card__reason a.name-thread') || item.querySelector('.card__reason a[data-role="article-link"]');
            if (threadLink) {
               threadTitle = threadLink.innerText;
               threadUrl = threadLink.href;
            }

            var directLink = item.querySelector('a.view-comment') || item.querySelector('a[data-link-name="timestamp"]');
            if (directLink && directLink.href) threadUrl = directLink.href;
            
            var myComment = '';
            var parentPost = item.querySelector('[data-role="parent-post"] .card-comment-truncated');
            if (parentPost) myComment = parentPost.innerText;
            
            var replyText = '';
            var replyPost = item.querySelector('[data-role="child-post"] .comment-message') || item.querySelector('[data-role="child-post"] .card-comment-truncated');
            if (replyPost) replyText = replyPost.innerText;
            
            if (!replyText && !myComment) {
                var singlePost = item.querySelector('.card-comment-truncated');
                if (singlePost) myComment = singlePost.innerText;
            }
            
            var replierName = '';
            var replierAvatar = '';
            var avatarImg = item.querySelector('[data-role="child-post"] .avatar img') || item.querySelector('.card__reason img');
            if (avatarImg) { replierAvatar = avatarImg.src; replierName = avatarImg.alt || ''; }
            
            var nameLink = item.querySelector('[data-role="child-post"] header.comment-header a.name') || item.querySelector('.card__reason a.name');
            if (nameLink && !replierName) replierName = nameLink.innerText;

            // Extract Disqus post ID â€” most reliable source is the
            // fragment identifier in the view-comment / reply link href.
            // Format: ...#comment-6865658811  or  ...#reply-6865658811
            var postId = '';
            var viewLink = item.querySelector('a.view-comment') ||
                           item.querySelector('a.reply');
            if (viewLink && viewLink.href) {
              var match = viewLink.href.match(/#(?:comment|reply)-(\d+)/);
              if (match) postId = match[1];
            }
            // Fallback: data-post-id attribute on any child
            if (!postId) {
              var el = item.querySelector('[data-post-id]');
              if (el) postId = el.getAttribute('data-post-id');
            }

            if (actText.indexOf(timeText) !== -1 && timeText !== '') actText = actText.replace(timeText, '').trim();
            if (replierName && actText.indexOf(replierName) === 0) actText = actText.substring(replierName.length).trim();
            
            items.push({
              replierName: replierName.trim(),
              replierAvatar: replierAvatar,
              replyText: replyText.trim(),
              myCommentText: myComment.trim(),
              threadTitle: threadTitle.trim(),
              threadUrl: threadUrl,
              timeAgo: timeText.trim(),
              activityText: actText.trim(),
              postId: postId,
              cardIndex: idx
            });
          } catch(e) {}
        });
        return JSON.stringify(items);
      })();
    ''';

    try {
      final jsonStr = await controller.evaluateJavascript(source: script);
      if (jsonStr != null && jsonStr is String) {
        final List decoded = jsonDecode(jsonStr);
        final list = decoded.map((e) => _ReplyItem(
          replierName: e['replierName'] ?? 'Someone',
          replierAvatar: e['replierAvatar'] ?? '',
          replyText: e['replyText'] ?? '',
          myCommentText: e['myCommentText'] ?? '',
          threadTitle: e['threadTitle'] ?? '',
          threadUrl: e['threadUrl'] ?? '',
          timeAgo: e['timeAgo'] ?? '',
          activityText: e['activityText'] ?? '',
          postId: e['postId']?.toString() ?? '',
          cardIndex: (e['cardIndex'] as num?)?.toInt() ?? 0,
        )).toList();

        if (mounted) {
          setState(() {
            _allNotifs = list;
            _isLoading = false;
            _status = '';
            
            // Bring the red badge back if new items are fetched and we aren't looking at Replies
            if (_tabController.index != 1) {
               _hasViewedReplies = false;
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _status = 'Check your internet connection and try again.';
        });
      }
    }
  }


  Widget _buildCard(_ReplyItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1B27),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Ã¢â€â‚¬Ã¢â€â‚¬ Header: avatar  |  name + activity  |  time Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: Colors.deepPurple.shade900,
                  backgroundImage: item.replierAvatar.isNotEmpty &&
                          item.replierAvatar.startsWith('http')
                      ? NetworkImage(item.replierAvatar)
                      : null,
                  child: item.replierAvatar.isEmpty
                      ? Text(
                          item.replierName.isNotEmpty
                              ? item.replierName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14))
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 13.5),
                          children: [
                            TextSpan(
                              text: item.replierName.isEmpty
                                  ? 'Someone'
                                  : item.replierName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: item.activityText.isNotEmpty
                                  ? item.activityText
                                  : 'replied to you',
                              style:
                                  const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(item.timeAgo,
                          style: const TextStyle(
                              color: Colors.white30, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),

            // Ã¢â€â‚¬Ã¢â€â‚¬ Your original comment (left-border block) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
            if (item.myCommentText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(6),
                      bottomRight: Radius.circular(6)),
                  border: Border(
                      left: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 3)),
                ),
                child: Text(item.myCommentText,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],

            // Ã¢â€â‚¬Ã¢â€â‚¬ Their reply (purple-tinted box) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
            if (item.replyText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.purpleAccent.withValues(alpha: 0.22)),
                ),
                child: Text(item.replyText,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis),
              ),
            ],

            // Footer: thread title (left) | View button (right)
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.forum_rounded, size: 13, color: Colors.white30),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    item.threadTitle.isNotEmpty ? item.threadTitle : 'Go to discussion',
                    style: const TextStyle(
                        color: Colors.purpleAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.threadUrl.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => widget.onNavigateToUrl(item.threadUrl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Colors.purpleAccent, Colors.deepPurple]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('View', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final replies = _allNotifs.where((n) => n.activityText.toLowerCase().contains('repl')).toList();

    return Container(
      color: const Color(0xFF100F17),
      child: SafeArea(
        child: Stack(
          children: [
            // Ã¢â€â‚¬Ã¢â€â‚¬ Hidden WebView (on-screen, behind the UI) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
            // MUST be on-screen so Android delivers IntersectionObserver
            // callbacks. At -5000,-5000 Android pauses the WebView's rendering
            // entirely which kills infinite scroll. The Column UI stacked on
            // top covers it completely. IgnorePointer blocks all touch events.
            IgnorePointer(
              child: SizedBox(
                width: 400,
                height: 700,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri('https://disqus.com/home/notifications/')),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    cacheEnabled: true,
                    transparentBackground: true,
                    mediaPlaybackRequiresUserGesture: false,
                  ),
                  onWebViewCreated: (c) async {
                    _hiddenWebController = c;

                    // Called by MutationObserver in _loadMore the moment
                    // Disqus inserts new notification cards into the DOM.
                    c.addJavaScriptHandler(
                      handlerName: 'onMoreNotifsLoaded',
                      callback: (args) async {
                        if (!_isLoadingMore) return;
                        await _extractData(c);
                        if (mounted) setState(() => _isLoadingMore = false);
                      },
                    );

                    if (!_hasEverFetched) {
                      // Pre-load: start fetching as soon as WebView is ready
                      // if the user was previously logged in â€” so notifications
                      // are ready by the time they open the tab.
                      final prefs = await SharedPreferences.getInstance();
                      final savedUsername = prefs.getString('disqusUsername') ?? '';
                      final isLoggedIn = savedUsername.isNotEmpty;

                      if (isLoggedIn) {
                        // Store username for display in reply sheet
                      }

                      // Fetch if tab is active OR user is already logged in
                      if (widget.isActive || isLoggedIn) {
                        _startFetch();
                      }
                    }
                  },
                  onLoadStop: _handleLoadStop,
                ),
              ),
            ),

            // Solid background Ã¢â‚¬â€ completely hides the WebView behind the UI.
            // Without this the WebView bleeds through (Column has no bg by default).
            Positioned.fill(child: const ColoredBox(color: Color(0xFF100F17))),

            // Ã¢â€â‚¬Ã¢â€â‚¬ Native UI Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
            Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 10, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_rounded, color: Colors.purpleAccent, size: 26),
                      const SizedBox(width: 10),
                      const Text('Notifications',
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 22),
                        onPressed: _isLoading ? null : _startFetch,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Tabs
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1B27),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        gradient: const LinearGradient(colors: [Colors.purpleAccent, Colors.deepPurple]),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white38,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      tabs: [
                        const Tab(text: 'Most Recent'),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Replies'),
                              if (replies.isNotEmpty && !_hasViewedReplies) ...[
                                const SizedBox(width: 5),
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Loading
                if (_isLoading)
                  const LinearProgressIndicator(color: Colors.purpleAccent, backgroundColor: Colors.transparent),

                // Content
                Expanded(
                  child: _isLoading && _allNotifs.isEmpty
                      ? Center(child: Text(_status, style: const TextStyle(color: Colors.white54, fontSize: 14)))
                      : _allNotifs.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.mark_chat_read_rounded, size: 64, color: Colors.white.withValues(alpha: 0.12)),
                                  const SizedBox(height: 16),
                                  Text(_status.isNotEmpty ? _status : 'No notifications yet',
                                      style: const TextStyle(color: Colors.white54, fontSize: 15)),
                                ],
                              ),
                            )
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                ListView.builder(
                                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                                  itemCount: _allNotifs.length + (_allNotifs.length >= 10 ? 1 : 0),
                                  itemBuilder: (_, i) {
                                    if (i == _allNotifs.length) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF1C1B27),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.white.withOpacity(0.06))),
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                          ),
                                          onPressed: _isLoadingMore ? null : _loadMore,
                                          child: _isLoadingMore 
                                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purpleAccent))
                                            : const Text('Load More', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
                                        ),
                                      );
                                    }
                                    return _buildCard(_allNotifs[i]);
                                  },
                                ),
                                ListView.builder(
                                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                                  itemCount: replies.length + (_allNotifs.length >= 10 ? 1 : 0),
                                  itemBuilder: (_, i) {
                                    if (i == replies.length) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF1C1B27),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.white.withOpacity(0.06))),
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                          ),
                                          onPressed: _isLoadingMore ? null : _loadMore,
                                          child: _isLoadingMore 
                                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purpleAccent))
                                            : const Text('Load More', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
                                        ),
                                      );
                                    }
                                    return _buildCard(replies[i]);
                                  },
                                ),
                              ],
                            ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

