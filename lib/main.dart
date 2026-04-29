import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:collection';
import 'ad_blocker.dart';
import 'settings_screen.dart';
import 'members_screen.dart';
import 'notifications_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TheAbyssApp());
}

class TheAbyssApp extends StatelessWidget {
  const TheAbyssApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Abyss',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF1A1A1A),
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF16151E),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final GlobalKey webViewKey = GlobalKey();
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  InAppWebViewController? webViewController;
  late PullToRefreshController pullToRefreshController;

  double progress = 0;
  bool isLoadError = false;
  bool inChat = false;
  bool _isReloadingTheme = false;
  bool _isStartupSplashVisible = true;
  int _currentTabIndex = 0;
  String currentTheme = 'Abyss Black';
  String customThemeUrl = '';
  String localImagePath = '';
  int currentTextZoom = 100;
  String commentHighlight = 'default'; // 'default' | 'dark' | 'light'
  final Map<String, Uint8List> _modifiedCssCache = {};

  // Stores the latest-chat URL while the WebView hasn't been created yet.
  // Once onWebViewCreated fires, we consume this and navigate immediately.
  String? _pendingChatUrl;

  List<Map<String, String>> chatRooms = [];
  String _loggedInUsername = '';

  final WebUri initialUrl = WebUri('about:blank');

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _initChatStartup();

    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: Colors.transparent),
      onRefresh: () async {
        if (webViewController != null) {
          webViewController!.reload();
        } else {
          pullToRefreshController.endRefreshing();
        }
      },
    );
  }

  // ── Fast Startup ─────────────────────────────────────────────────────────────
  Future<void> _initChatStartup() async {
    // 1. Instantly load the last known chat room to skip the RSS network delay
    final prefs = await SharedPreferences.getInstance();
    final lastUrl = prefs.getString('lastChatRoomUrl');
    if (lastUrl != null && lastUrl.isNotEmpty) {
      if (webViewController != null) {
        webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(lastUrl)));
      } else {
        _pendingChatUrl = lastUrl;
      }
    }
    // 2. Fetch the RSS feed in the background to check for any NEW chat rooms
    _fetchChatRooms(cachedUrl: lastUrl);
  }

  // ── Chat room fetcher ────────────────────────────────────────────────────────
  Future<void> _fetchChatRooms({String? cachedUrl}) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(
          "https://thesigmas.blogspot.com/feeds/posts/default?alt=json&max-results=500"));
      final response = await request.close();
      final stringData = await response.transform(utf8.decoder).join();
      final data = json.decode(stringData);

      final entries = data['feed']['entry'] as List;
      final List<Map<String, String>> rooms = [];

      for (var entry in entries) {
        final title = entry['title']['\$t'] as String;
        final links = entry['link'] as List;
        String? url;

        for (var link in links) {
          if (link['rel'] == 'alternate') {
            url = link['href'];
            break;
          }
        }

        final lowered = title.toLowerCase();
        if ((lowered.contains("chat") ||
                lowered.contains("room") ||
                lowered.contains("hall of fame")) &&
            url != null) {
          final pubRaw = entry['published']?['\$t'] as String? ?? '';
          rooms.add({"title": title, "url": url, "date": _formatPublishedDate(pubRaw)});
        }
      }

      if (mounted) {
        setState(() { chatRooms = rooms; });
        if (rooms.isNotEmpty) {
          final url = rooms.first['url']!;
          // Cache the latest URL so next startup is instant
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('lastChatRoomUrl', url);

          // Only navigate if we didn't already load this exact URL from cache
          if (url != cachedUrl) {
            if (webViewController != null) {
              webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
            } else {
              _pendingChatUrl = url;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching chat rooms: $e");
    }
  }

  // ── Navigation handler ───────────────────────────────────────────────────────
  // Navigate directly to the notification URL (includes #comment-X fragment).
  // Disqus handles the anchor natively — no delayed injection needed.
  void _handleNavigateToUrl(String url) async {
    if (url.isEmpty) return;
    setState(() => _currentTabIndex = 0);
    await webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  String _formatPublishedDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return 'Unknown date';
    }
  }

  Future<void> _loadTheme() async {
    // Always clear the CSS cache so a changed highlight setting is applied
    // on the very next reload — not served stale from the in-memory cache.
    _modifiedCssCache.clear();

    final prefs = await SharedPreferences.getInstance();

    // Ensure a default Custom URL exists so the setting works if the user
    // later selects it, but do NOT force the theme to 'Custom URL' on a
    // fresh install — new users should start with the 'Abyss Black' default.
    String savedUrl = prefs.getString('customThemeUrl') ?? '';
    if (savedUrl.isEmpty) {
      savedUrl = 'https://wallpapersok.com/images/high/moon-phone-varieties-n4a209i7cv27s620.webp';
      await prefs.setString('customThemeUrl', savedUrl);
      // Note: intentionally NOT writing 'theme' key here so the default
      // remains 'Abyss Black' on a clean install.
    }

    if (mounted) {
      setState(() {
        currentTheme = prefs.getString('theme') ?? 'Abyss Black';
        customThemeUrl = savedUrl;
        localImagePath = prefs.getString('localImagePath') ?? '';
        currentTextZoom = prefs.getInt('textZoom') ?? 100;
        commentHighlight = prefs.getString('commentHighlight') ?? 'default';
      });

      if (webViewController != null) {
        setState(() { _isReloadingTheme = true; });
        await webViewController!.setSettings(settings: _buildWebViewSettings());
        await _injectUserScriptsDynamically(webViewController!);
        webViewController!.reload();

        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && _isReloadingTheme) {
            setState(() { _isReloadingTheme = false; });
          }
        });
      }
    }
  }

  // ── User scripts ─────────────────────────────────────────────────────────────
  Future<void> _injectUserScriptsDynamically(InAppWebViewController controller) async {
    await controller.removeAllUserScripts();

    final String backgroundStripCSS = currentTheme == 'Abyss Black'
        ? ''
        : '''
            body, html, .bg-photo, .body-fauxcolumn-outer, #page-wrapper,
            .content-outer, .content-inner, .sect-auth-outer {
                background: transparent !important;
                background-color: transparent !important;
                background-image: none !important;
            }
            body > * { background-color: transparent !important; }
        ''';

    if (backgroundStripCSS.isNotEmpty) {
      await controller.addUserScript(userScript: UserScript(
        source: '''
            var bgStyle = document.createElement('style');
            bgStyle.id = 'flutter-theme-override';
            bgStyle.type = 'text/css';
            bgStyle.innerHTML = `$backgroundStripCSS`;
            document.documentElement.appendChild(bgStyle);
        ''',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ));
    }

    // ── Disqus passive-listener patch ─────────────────────────────────────────
    // Must run BEFORE Disqus registers its own scroll/touch listeners.
    // Passive listeners allow the browser to begin scrolling immediately
    // without waiting for JS — eliminates the "sticky scroll" jank.
    // Applied to ALL frames (forMainFrameOnly: false) so it also covers
    // the cross-origin Disqus iframe.
    const String passiveListenerPatchJS = '''
      (function() {
        if (window.__abyssPassivePatch) return;
        window.__abyssPassivePatch = true;
        var orig = EventTarget.prototype.addEventListener;
        EventTarget.prototype.addEventListener = function(type, fn, opts) {
          if (type === 'touchstart' || type === 'touchmove' ||
              type === 'wheel'      || type === 'scroll') {
            if (typeof opts === 'object' && opts !== null) {
              opts = Object.assign({}, opts, { passive: true });
            } else {
              opts = { passive: true, capture: !!opts };
            }
          }
          return orig.call(this, type, fn, opts);
        };
      })();
    ''';
    await controller.addUserScript(userScript: UserScript(
      source: passiveListenerPatchJS,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    ));

    // ── Disqus performance CSS + lazy images ──────────────────────────────────
    // Injected at document-end so the DOM is available for querySelectorAll.
    // Also targets all frames.
    const String disqusPerformanceJS = r'''
      (function() {
        if (window.__abyssPerfInjected) return;
        window.__abyssPerfInjected = true;

        // ── Performance CSS ────────────────────────────────────────────────
        var s = document.createElement('style');
        s.textContent = [
          /* Hide link-preview cards — the single biggest scroll perf win.
             Every URL in a comment triggers a separate network fetch + render. */
          '.post-attachment,.post-attachment-meta,.media-toggle { display:none!important; }',
          /* Hide Disqus promoted / sponsored posts */
          '.promoted-post,.promoted-post-ad,[data-role="promoted-post"] { display:none!important; }',
          /* Virtual-scroll hint: skip GPU painting for off-screen comments */
          '.post { content-visibility:auto; contain-intrinsic-size:0 120px; }',
          /* Kill all CSS transitions inside Disqus — removes jank frames */
          '.post *,.post-list,.thread-list { transition:none!important; animation:none!important; }',
        ].join('\n');
        document.head && document.head.appendChild(s);

        // ── Lazy-load images ──────────────────────────────────────────────
        document.querySelectorAll('img').forEach(function(img) {
          if (!img.loading)  img.loading  = 'lazy';
          if (!img.decoding) img.decoding = 'async';
        });

        // Also lazy-load any images Disqus injects after initial render
        var imgObserver = new MutationObserver(function(mutations) {
          mutations.forEach(function(m) {
            m.addedNodes.forEach(function(node) {
              if (node.nodeType !== 1) return;
              var imgs = node.nodeName === 'IMG'
                ? [node]
                : node.querySelectorAll ? node.querySelectorAll('img') : [];
              imgs.forEach(function(img) {
                if (!img.loading)  img.loading  = 'lazy';
                if (!img.decoding) img.decoding = 'async';
              });
            });
          });
        });
        imgObserver.observe(document.body || document.documentElement,
          { childList: true, subtree: true });
      })();
    ''';
    await controller.addUserScript(userScript: UserScript(
      source: disqusPerformanceJS,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      forMainFrameOnly: false,
    ));

    // Custom fast-scroll thumb
    final String fastScrollerJS = '''
      (function() {
        if (document.getElementById('custom-fast-scroller')) return;
        var style = document.createElement('style');
        style.innerHTML = `
          #custom-fast-scroller {
            position: fixed; top: 20%; right: 2px; width: 14px; height: 60%;
            background: rgba(40, 36, 54, 0.5); border-radius: 7px; z-index: 9999999;
            touch-action: none; border: 1px solid rgba(255,255,255,0.1);
          }
          #custom-fast-scroller-thumb {
            position: absolute; top: 0; left: 0; width: 14px; height: 70px;
            background: rgba(224,64,251,0.8); border-radius: 7px;
            box-shadow: 0 0 10px rgba(224,64,251,0.8); transition: background 0.1s;
          }
          #custom-fast-scroller-thumb:active { background: rgba(255,255,255,0.9); }
        `;
        document.head.appendChild(style);
        var track = document.createElement('div');
        track.id = 'custom-fast-scroller';
        var thumb = document.createElement('div');
        thumb.id = 'custom-fast-scroller-thumb';
        track.appendChild(thumb);
        document.body.appendChild(track);
        var isDragging = false, startY = 0, startTop = 0;
        function getTrackHeight() { return track.clientHeight - thumb.clientHeight; }
        function getScrollRange() { return document.documentElement.scrollHeight - window.innerHeight; }
        function updateThumbPosition() {
          var sr = getScrollRange();
          if (sr <= 0) return;
          thumb.style.top = (window.scrollY / sr * getTrackHeight()) + 'px';
        }
        window.addEventListener('scroll', updateThumbPosition, { passive: true });
        thumb.addEventListener('touchstart', function(e) {
          isDragging = true; startY = e.touches[0].clientY;
          startTop = parseFloat(thumb.style.top) || 0; e.preventDefault();
        }, { passive: false });
        window.addEventListener('touchmove', function(e) {
          if (!isDragging) return;
          var dy = e.touches[0].clientY - startY;
          var newTop = Math.max(0, Math.min(getTrackHeight(), startTop + dy));
          thumb.style.top = newTop + 'px';
          window.scrollTo(0, newTop / getTrackHeight() * getScrollRange());
          e.preventDefault();
        }, { passive: false });
        window.addEventListener('touchend', function() { isDragging = false; });
        updateThumbPosition();
      })();
    ''';

    await controller.addUserScript(userScript: UserScript(
      source: fastScrollerJS,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      forMainFrameOnly: true,
    ));

    // Detect logged-in Disqus username via postMessage (the only cross-origin channel)
    const String usernameExtractorJS = '''
      (function() {
         var sent = false;
         var report = function(u) {
           if (sent || !u) return; sent = true;
           window.flutter_inappwebview.callHandler('onDisqusUser', u);
         };
         window.addEventListener('message', function(evt) {
           if (!evt.origin || evt.origin.indexOf('disqus.com') === -1) return;
           try {
             var d = (typeof evt.data === 'string') ? JSON.parse(evt.data) : evt.data;
             if (!d) return;
             var u = (d.obj && d.obj.currentUser) || (d.data && d.data.currentUser) || d.currentUser;
             if (u && u.username) { report(u.username); return; }
             if (d.name === 'login' && d.obj && d.obj.username) { report(d.obj.username); return; }
             if (d.verb === 'login' && d.noun && d.noun.username) { report(d.noun.username); }
           } catch(_) {}
         });
         var tryGlobal = function() {
           try {
             var s = window.DISQUS && window.DISQUS.session;
             if (s && s.user && s.user.username) { report(s.user.username); return; }
           } catch(_) {}
         };
         setTimeout(tryGlobal, 4000);
         setTimeout(tryGlobal, 9000);
      })();
    ''';
    await controller.addUserScript(userScript: UserScript(
      source: usernameExtractorJS,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      forMainFrameOnly: true,
    ));

    // Note: comment highlight CSS is injected via shouldInterceptRequest
    // (network-layer CSS interception) which is the only reliable way to
    // reach Disqus's cross-origin iframe on Android. See the WebView widget.
  }

  // ── Theme decoration ─────────────────────────────────────────────────────────
  BoxDecoration _buildBackgroundDecoration() {
    if (currentTheme == 'Silk Red') {
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF5A0000), Color(0xFF1A0000), Colors.black],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      );
    } else if (currentTheme == 'Midnight Purple') {
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF420075), Color(0xFF16002A), Colors.black],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      );
    } else if (currentTheme == 'Deep Ocean') {
      return const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF00224D), Color(0xFF000B1A), Colors.black],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      );
    } else if (currentTheme == 'Custom URL' && customThemeUrl.isNotEmpty) {
      return BoxDecoration(
        color: Colors.black,
        image: DecorationImage(image: NetworkImage(customThemeUrl), fit: BoxFit.cover),
      );
    } else if (currentTheme == 'Local Image' && localImagePath.isNotEmpty) {
      final file = File(localImagePath);
      if (file.existsSync()) {
        return BoxDecoration(
          color: Colors.black,
          image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
        );
      }
    }
    return const BoxDecoration(color: Colors.black);
  }

  InAppWebViewSettings _buildWebViewSettings() {
    return InAppWebViewSettings(
      textZoom: currentTextZoom,
      disableHorizontalScroll: true,
      verticalScrollBarEnabled: true,
      overScrollMode: OverScrollMode.NEVER,
      transparentBackground: true,
      javaScriptEnabled: true,
      cacheEnabled: true,
      hardwareAcceleration: true,
      databaseEnabled: true,
      useShouldOverrideUrlLoading: true,
      useShouldInterceptRequest: true, // always enabled; CSS injection is guarded inside the callback
      mediaPlaybackRequiresUserGesture: true,
      contentBlockers: AdBlocker.contentBlockers,
      supportMultipleWindows: true,
      javaScriptCanOpenWindowsAutomatically: true,
      thirdPartyCookiesEnabled: true,
      domStorageEnabled: true,
      allowsInlineMediaPlayback: true,
      userAgent: "",
      preferredContentMode: UserPreferredContentMode.RECOMMENDED,
      useWideViewPort: true,
      loadWithOverviewMode: true,
    );
  }

  Future<bool> _goBack() async {
    if (scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
      return false;
    }
    if (webViewController != null && await webViewController!.canGoBack()) {
      webViewController!.goBack();
      return false;
    }
    return true;
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _goBack() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        key: scaffoldKey,
        drawer: Drawer(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 60, bottom: 20, left: 20, right: 20),
                color: const Color(0xFF100F17),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.chat_bubble_outline, color: Colors.purpleAccent, size: 32),
                    SizedBox(height: 12),
                    Text('Past Chatrooms',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Archive of all your chats',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
              if (chatRooms.isEmpty)
                const Expanded(child: Center(child: CircularProgressIndicator(color: Colors.purpleAccent))),
              if (chatRooms.isNotEmpty)
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: chatRooms.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final room = chatRooms[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        title: Text(room['title']!,
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.info_outline_rounded, color: Colors.white30, size: 19),
                              tooltip: 'When was this created?',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: const Color(0xFF1C1B27),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: Text(room['title']!,
                                        style: const TextStyle(color: Colors.white, fontSize: 15)),
                                    content: Row(children: [
                                      const Icon(Icons.calendar_month_outlined,
                                          color: Colors.purpleAccent, size: 20),
                                      const SizedBox(width: 8),
                                      Text('Created in: ${room['date']}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                    ]),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Close',
                                            style: TextStyle(color: Colors.purpleAccent)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, color: Colors.white38, size: 22),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(room['url']!)));
                        },
                      );
                    },
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.white70),
                title: const Text('Settings', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SettingsScreen(onThemeChanged: _loadTheme)));
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
        body: IndexedStack(
          index: _currentTabIndex,
          children: [
            // ── Tab 0: Chat WebView ──────────────────────────────────────────
            Container(
              decoration: _buildBackgroundDecoration(),
              child: SafeArea(
                child: Stack(
                  children: [
                    AnimatedOpacity(
                      opacity: _isReloadingTheme ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: RepaintBoundary(
                        child: InAppWebView(
                          key: webViewKey,
                          initialUrlRequest: URLRequest(url: initialUrl),
                          pullToRefreshController: pullToRefreshController,
                          initialUserScripts: UnmodifiableListView<UserScript>([]),
                          initialSettings: _buildWebViewSettings(),
                          onWebViewCreated: (controller) async {
                            webViewController = controller;
                            await _injectUserScriptsDynamically(controller);

                            // If _fetchChatRooms completed before the WebView was
                            // ready, it stored the URL in _pendingChatUrl. Navigate now.
                            if (_pendingChatUrl != null) {
                              controller.loadUrl(
                                urlRequest: URLRequest(url: WebUri(_pendingChatUrl!)),
                              );
                              _pendingChatUrl = null;
                            }

                            controller.addJavaScriptHandler(
                              handlerName: 'onDisqusUser',
                              callback: (args) async {
                                if (args.isEmpty) return;
                                final name = args[0].toString().trim();
                                if (name.isNotEmpty && name != _loggedInUsername) {
                                  if (mounted) setState(() => _loggedInUsername = name);
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setString('disqusUsername', name);
                                }
                              },
                            );
                          },
                          onLoadStart: (controller, url) {
                            setState(() { progress = 0; isLoadError = false; });
                          },
                          onLoadStop: (controller, url) async {
                            pullToRefreshController.endRefreshing();
                            setState(() { progress = 1.0; });

                            if (url != null && url.toString() != 'about:blank') {
                              setState(() { _isStartupSplashVisible = false; });
                            }

                            await Future.delayed(const Duration(milliseconds: 400));
                            if (mounted) {
                              setState(() {
                                _isReloadingTheme = false;
                              });
                            }
                          },
                          onUpdateVisitedHistory: (controller, url, androidIsReload) {
                            if (url != null) {
                              setState(() {
                                inChat = url.toString().toLowerCase().contains('chat');
                              });
                            }
                          },
                          onProgressChanged: (controller, progress) {
                            if (progress == 100) pullToRefreshController.endRefreshing();
                            setState(() { this.progress = progress / 100; });
                          },
                          onReceivedError: (controller, request, error) {
                            if (request.isForMainFrame == false) return;
                            pullToRefreshController.endRefreshing();
                            setState(() { isLoadError = true; _isReloadingTheme = false; });
                          },
                          onRenderProcessGone: (controller, detail) async {
                            // On low-end devices Android's OOM killer can terminate the
                            // WebView renderer process when Disqus's heavy JS runs out
                            // of memory. This silently blanks the page. Reload to recover.
                            debugPrint('WebView renderer crashed (OOM?): $detail — reloading');
                            if (mounted) {
                              setState(() { isLoadError = false; _isReloadingTheme = false; });
                            }
                            await Future.delayed(const Duration(milliseconds: 800));
                            await controller.reload();
                          },
                          shouldOverrideUrlLoading: (controller, navigationAction) async {
                            var uri = navigationAction.request.url;
                            if (uri == null) return NavigationActionPolicy.CANCEL;

                            if (!["http", "https", "file", "chrome", "data",
                                "javascript", "about"].contains(uri.scheme)) {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                                return NavigationActionPolicy.CANCEL;
                              }
                            }

                            if (uri.scheme == 'http' || uri.scheme == 'https') {
                              final host = uri.host.toLowerCase();
                              if (host.contains('blogspot.com') ||
                                  host.contains('disqus.com') ||
                                  host.contains('disq.us') ||
                                  host.contains('google.com') ||
                                  host.contains('twitter.com') ||
                                  host.contains('facebook.com')) {
                                return NavigationActionPolicy.ALLOW;
                              } else {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                                return NavigationActionPolicy.CANCEL;
                              }
                            }
                            return NavigationActionPolicy.ALLOW;
                          },
                          shouldInterceptRequest: (controller, request) async {
                            // ── Comment highlight injection ──────────────────────────────
                            // Android's WebViewClient.onPageFinished only fires for the
                            // main frame, so UserScript with forMainFrameOnly:false cannot
                            // reach the cross-origin Disqus iframe.
                            // Instead, we intercept Disqus CDN CSS files at the network
                            // layer and append our highlight CSS to them before the browser
                            // sees the response. Works for every frame, any origin.
                            if (commentHighlight != 'default') {
                              final url = request.url.toString();
                              if (url.contains('c.disquscdn.com') && url.contains('.css')) {
                                // Return cached version if available
                                if (_modifiedCssCache.containsKey(url)) {
                                  return WebResourceResponse(
                                    contentType: 'text/css; charset=utf-8',
                                    statusCode: 200,
                                    reasonPhrase: 'OK',
                                    // no-cache: browser must re-request on every
                                    // page load so shouldInterceptRequest always
                                    // fires and we can re-inject our highlight CSS
                                    headers: {
                                      'Content-Type': 'text/css; charset=utf-8',
                                      'Cache-Control': 'no-cache, no-store, must-revalidate',
                                      'Pragma': 'no-cache',
                                    },
                                    data: _modifiedCssCache[url],
                                  );
                                }
                                // Fetch original CSS and append highlight rules
                                try {
                                  final client = HttpClient();
                                  final req = await client.getUrl(Uri.parse(url));
                                  req.headers.set('Accept', 'text/css,*/*');
                                  final res = await req.close().timeout(const Duration(seconds: 8));
                                  final bytes = await res
                                      .fold<List<int>>([], (buf, chunk) => buf..addAll(chunk));
                                  final origCss = utf8.decode(bytes, allowMalformed: true);

                                  final hlBg = commentHighlight == 'dark'
                                      ? 'rgba(0,0,0,0.78)'
                                      : 'rgba(255,255,255,0.86)';
                                  final hlFg = commentHighlight == 'dark'
                                      ? '#ffffff'
                                      : '#111111';

                                  final extraCss = '''
/* === Abyss comment highlight === */
.post-message{background-color:$hlBg!important;border-radius:6px!important;padding:6px 10px!important;}
.post-message p,.post-message span,.post-message a{color:$hlFg!important;background:transparent!important;}
''';
                                  final combined =
                                      Uint8List.fromList(utf8.encode(origCss + extraCss));
                                  _modifiedCssCache[url] = combined;  // cache it
                                  client.close();

                                  return WebResourceResponse(
                                    contentType: 'text/css; charset=utf-8',
                                    statusCode: 200,
                                    reasonPhrase: 'OK',
                                    headers: {
                                      'Content-Type': 'text/css; charset=utf-8',
                                      'Cache-Control': 'no-cache, no-store, must-revalidate',
                                      'Pragma': 'no-cache',
                                    },
                                    data: combined,
                                  );
                                } catch (_) {
                                  // On any error let the browser load it normally
                                }
                              }
                            }
                            return null; // allow normal loading
                          },
                          onCreateWindow: (controller, createWindowAction) async {
                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: EdgeInsets.zero,
                                child: SafeArea(
                                  child: Column(children: [
                                    AppBar(
                                      title: const Text('Login'),
                                      backgroundColor: const Color(0xFF1A1A1A),
                                      leading: IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                    Expanded(
                                      child: InAppWebView(
                                        windowId: createWindowAction.windowId,
                                        initialSettings: InAppWebViewSettings(
                                          javaScriptEnabled: true,
                                          thirdPartyCookiesEnabled: true,
                                          domStorageEnabled: true,
                                        ),
                                        onCloseWindow: (controller) {
                                          if (Navigator.canPop(context)) Navigator.pop(context);
                                        },
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            );
                            return true;
                          },
                        ),
                      ),
                    ),


                    // Navigation menu button (only in chat rooms)
                    if (inChat)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: FloatingActionButton(
                          mini: true,
                          elevation: 4,
                          backgroundColor: const Color(0xFF282436).withValues(alpha: 0.9),
                          foregroundColor: Colors.white,
                          child: const Icon(Icons.menu),
                          onPressed: () => scaffoldKey.currentState?.openDrawer(),
                        ),
                      ),

                    // Page load progress bar
                    if (progress < 1.0)
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.transparent,
                          color: Colors.purpleAccent,
                        ),
                      ),

                    // Error overlay
                    if (isLoadError)
                      Container(
                        color: Colors.black87,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
                              const SizedBox(height: 16),
                              const Text('Failed to load page. Please check your connection.',
                                  style: TextStyle(color: Colors.white, fontSize: 16)),
                              const SizedBox(height: 24),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.purpleAccent),
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                ),
                                onPressed: () {
                                  webViewController?.reload();
                                  setState(() { isLoadError = false; });
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ── SPLASH OVERLAY ──────────────────────────────────────────
                    IgnorePointer(
                      ignoring: !_isStartupSplashVisible,
                      child: AnimatedOpacity(
                        opacity: _isStartupSplashVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        child: Container(
                          color: Colors.black, // Dark background behind the GIF
                          child: SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            child: Image.asset(
                              'assets/abyss.gif',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Tab 1: Members ───────────────────────────────────────────────
            const MembersScreen(),

            // ── Tab 2: Notifications ─────────────────────────────────────────
            NotificationsScreen(
              onNavigateToUrl: _handleNavigateToUrl,
              isActive: _currentTabIndex == 2,
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF100F17),
            border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentTabIndex,
            onTap: (index) => setState(() => _currentTabIndex = index),
            backgroundColor: const Color(0xFF100F17),
            selectedItemColor: Colors.purpleAccent,
            unselectedItemColor: Colors.white38,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                activeIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Chat',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.people_outline_rounded),
                activeIcon: Icon(Icons.people_rounded),
                label: 'Members',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.notifications_none_rounded),
                activeIcon: Icon(Icons.notifications_rounded),
                label: 'Notifications',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
