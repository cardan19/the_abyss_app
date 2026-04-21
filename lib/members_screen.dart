import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────
class _Member {
  final String id;
  final String name;
  final String username;
  final String avatar;
  final String profileUrl;
  final bool isMod;
  int numPosts = 0;
  int numLikes = 0;
  bool statsLoaded = false;

  _Member({
    required this.id,
    required this.name,
    required this.username,
    required this.avatar,
    required this.profileUrl,
    required this.isMod,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'avatar': avatar,
        'profileUrl': profileUrl,
        'isMod': isMod,
        'numPosts': numPosts,
        'numLikes': numLikes,
        'statsLoaded': statsLoaded,
      };

  factory _Member.fromJson(Map<String, dynamic> json) {
    var m = _Member(
      id: json['id'] as String,
      name: json['name'] as String,
      username: json['username'] as String,
      avatar: json['avatar'] as String,
      profileUrl: json['profileUrl'] as String,
      isMod: json['isMod'] as bool,
    );
    m.numPosts = json['numPosts'] as int? ?? 0;
    m.numLikes = json['numLikes'] as int? ?? 0;
    m.statsLoaded = json['statsLoaded'] as bool? ?? false;
    return m;
  }
}

// ─────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────
String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
  return '$n';
}

// ─────────────────────────────────────────────────────────
// In-app profile viewer page
// ─────────────────────────────────────────────────────────
class _ProfilePage extends StatelessWidget {
  final String name;
  final String url;

  const _ProfilePage({required this.name, required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF100F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF100F17),
        foregroundColor: Colors.white,
        title: Text(name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white10),
        ),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          cacheEnabled: true,
          transparentBackground: true,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Sort options
enum _SortMode { name, likes, comments }

// Main screen
// ─────────────────────────────────────────────────────────
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  // Flat list of all Abyssians; split into mods/members in build()
  final List<_Member> _all = [];
  bool _isFetching = true;
  bool _hasError = false;
  String _status = 'Fetching moderators…';
  _SortMode _sortMode = _SortMode.name;
  int _generation = 0; // increments on each refresh to cancel stale bg work

  static const String _apiKey =
      'DVAp9sEWMjL7YK3lUCxJAb3PNGOyF0Eu1tN7Vcxm4fopHBpMbc9oBiV6GEo6wLg8';
  static const String _forum = 'chat-room-9';
  static const int _abyssianBadgeId = 1999;

  // Private-account Abyssians whose badges are hidden by the Disqus API.
  // Add usernames here whenever a known Abyssian doesn't show up.
  static const List<String> _privateAbyssians = [
    'alyys_yzz',
  ];

  @override
  void initState() {
    super.initState();
    _start();
  }

  // ─── Orchestrator ─────────────────────────────────────
  Future<void> _start({bool forceRefresh = false}) async {
    final gen = ++_generation; // any older bg work will see a mismatch & stop
    
    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheStr = prefs.getString('membersCache');
        final cacheTime = prefs.getInt('membersCacheTime');
        if (cacheStr != null && cacheTime != null) {
          final ageMs = DateTime.now().millisecondsSinceEpoch - cacheTime;
          if (ageMs < 43200000) { // 12 hours = 43,200,000 ms 
            final list = jsonDecode(cacheStr) as List;
            final cached = list.map((e) => _Member.fromJson(e as Map<String, dynamic>)).toList();
            // Reject partial caches (e.g. from rate-limited sessions)
            if (cached.length >= 5 && mounted) {
              setState(() {
                _all.clear();
                _all.addAll(cached);
                _isFetching = false;
                _hasError = false;
                _status = '';
              });
              return; // Cache hit: skip API fetch entirely
            }
          }
        }
      } catch (_) {} // fallthrough to network fetch on error
    }

    setState(() {
      _all.clear();
      _isFetching = true;
      _hasError = false;
      _status = 'Fetching moderators…';
    });

    try {
      // Step 1 – get official mods list (fast, single call) + show mods immediately
      final modIds = await _fetchMods();

      // Step 2 – stream Abyssians page by page
      _setStatus('Loading members…');
      await _streamAbyssians();

      // Step 2.5 – inject private-account Abyssians the API can't detect
      await _injectPrivateAbyssians(modIds);

      // Step 3 – load stats in background (no loading indicator)
      if (mounted) setState(() => _isFetching = false);
      _loadStatsBackground(gen);
    } catch (e) {
      debugPrint('MembersScreen: $e');
      if (mounted) setState(() { _isFetching = false; _hasError = true; });
    }
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  // ─── Step 1: Fetch moderators WITH full user data ──────
  Future<Set<String>> _fetchMods() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    final ids = <String>{};

    try {
      final url =
          'https://disqus.com/api/3.0/forums/listModerators.json'
          '?forum=$_forum&api_key=$_apiKey';
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final data = json.decode(body) as Map<String, dynamic>;

      if (data['code'] == 0) {
        final mods = <_Member>[];
        for (final entry in data['response'] as List) {
          final user = entry['user'] as Map<String, dynamic>?;
          if (user == null) continue;
          final userId = user['id']?.toString() ?? '';
          if (userId.isEmpty) continue;

          final rawName = (user['name'] as String?)?.trim() ?? '';
          mods.add(_Member(
            id: userId,
            name: rawName.isNotEmpty ? rawName : (user['username'] ?? ''),
            username: user['username'] ?? '',
            avatar: user['avatar']?['small']?['cache'] ?? '',
            profileUrl: user['profileUrl'] ?? '',
            isMod: true,
          ));
          ids.add(userId);
        }

        // Sort mods A→Z and show them immediately
        mods.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (mounted) setState(() => _all.addAll(mods));
      }
    } finally {
      client.close();
    }

    return ids;
  }

  // ─── Step 2: Stream Abyssians, render per page ─────────
  Future<void> _streamAbyssians() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    String? cursor;
    bool hasMore = true;
    int page = 1;

    try {
      while (hasMore) {
        _setStatus('Loading members… (page $page)');

        String url =
            'https://disqus.com/api/3.0/forums/listUsers.json'
            '?forum=$_forum&api_key=$_apiKey&limit=100';
        if (cursor != null) url += '&cursor=$cursor';

        final req = await client.getUrl(Uri.parse(url));
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        final data = json.decode(body) as Map<String, dynamic>;

        if (data['code'] != 0) break;

        // Build a set of IDs already added (mods + previous pages)
        final existingIds = _all.map((m) => m.id).toSet();

        final newBatch = <_Member>[];
        for (final user in data['response'] as List) {
          final badges = (user['badges'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          if (!badges.any((b) => b['id'] == _abyssianBadgeId)) continue;

          final userId = user['id'].toString();
          // Skip if already added (avoids duplicating mods)
          if (existingIds.contains(userId)) continue;

          final rawName = (user['name'] as String?)?.trim() ?? '';
          newBatch.add(_Member(
            id: userId,
            name: rawName.isNotEmpty ? rawName : (user['username'] ?? ''),
            username: user['username'] ?? '',
            avatar: user['avatar']?['small']?['cache'] ?? '',
            profileUrl: user['profileUrl'] ?? '',
            isMod: false, // mods already handled in step 1
          ));
        }

        if (newBatch.isNotEmpty && mounted) {
          setState(() => _all.addAll(newBatch));
        }

        final cur = data['cursor'] as Map<String, dynamic>;
        hasMore = cur['more'] == true;
        if (hasMore) cursor = cur['next'] as String?;
        page++;
      }
      // Save cache after all stats finish loading
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('membersCache', jsonEncode(_all.map((m) => m.toJson()).toList()));
        await prefs.setInt('membersCacheTime', DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    } finally {
      client.close();
    }
  }

  // ─── Step 2.5: Inject private-account Abyssians ────────
  Future<void> _injectPrivateAbyssians(Set<String> modIds) async {
    if (_privateAbyssians.isEmpty) return;
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      final existingIds = _all.map((m) => m.id).toSet();

      for (final username in _privateAbyssians) {
        try {
          final url =
              'https://disqus.com/api/3.0/users/details.json'
              '?user:username=$username&api_key=$_apiKey';
          final req = await client.getUrl(Uri.parse(url));
          final res = await req.close();
          final body = await res.transform(utf8.decoder).join();
          final data = json.decode(body) as Map<String, dynamic>;

          if (data['code'] == 0) {
            final u = data['response'] as Map<String, dynamic>;
            final userId = u['id']?.toString() ?? '';
            if (userId.isEmpty || existingIds.contains(userId)) continue;

            final rawName = (u['name'] as String?)?.trim() ?? '';
            final member = _Member(
              id: userId,
              name: rawName.isNotEmpty ? rawName : username,
              username: u['username'] ?? username,
              avatar: u['avatar']?['small']?['cache'] ?? '',
              profileUrl: u['profileUrl'] ?? '',
              isMod: modIds.contains(userId),
            );
            // Inject pre-loaded stats since we already have the details
            member.numPosts = (u['numPosts'] as num?)?.toInt() ?? 0;
            member.numLikes = (u['numLikesReceived'] as num?)?.toInt() ?? 0;
            member.statsLoaded = true;

            existingIds.add(userId);
            if (mounted) setState(() => _all.add(member));
          }
        } catch (_) {}
      }
      // Save cache after all stats finish loading
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('membersCache', jsonEncode(_all.map((m) => m.toJson()).toList()));
        await prefs.setInt('membersCacheTime', DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    } finally {
      client.close();
    }
  }

  // ─── Step 3: Background stats ─────────────────────────
  Future<void> _loadStatsBackground(int gen) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    // Snapshot taken now – private Abyssians already have statsLoaded = true
    final snapshot = List<_Member>.from(_all);

    try {
      for (int i = 0; i < snapshot.length; i += 5) {
        // Stop if user hit refresh (generation changed) or widget gone
        if (_generation != gen || !mounted) break;

        final batch = snapshot.sublist(i, (i + 5).clamp(0, snapshot.length));
        await Future.wait(batch.map((m) async {
          if (m.statsLoaded) return; // already loaded (e.g. private Abyssians)
          try {
            final url =
                'https://disqus.com/api/3.0/users/details.json'
                '?user=${m.id}&api_key=$_apiKey';
            final req = await client.getUrl(Uri.parse(url));
            final res = await req.close();
            final body = await res.transform(utf8.decoder).join();
            final data = json.decode(body) as Map<String, dynamic>;
            if (data['code'] == 0) {
              final r = data['response'] as Map<String, dynamic>;
              m.numPosts = (r['numPosts'] as num?)?.toInt() ?? 0;
              m.numLikes = (r['numLikesReceived'] as num?)?.toInt() ?? 0;
              m.statsLoaded = true;
              if (mounted && _generation == gen) setState(() {});
            }
          } catch (_) {}
        }));
      }
      // Save cache after all stats finish loading
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('membersCache', jsonEncode(_all.map((m) => m.toJson()).toList()));
        await prefs.setInt('membersCacheTime', DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    } finally {
      client.close();
    }
  }

  // ─────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Sort and split inline so it's always fresh
    // ── Sort based on _sortMode ─────────────────────────
    final sorted = List<_Member>.from(_all)..sort((a, b) {
      switch (_sortMode) {
        case _SortMode.likes:
          return b.numLikes.compareTo(a.numLikes);
        case _SortMode.comments:
          return b.numPosts.compareTo(a.numPosts);
        case _SortMode.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
    final mods = sorted.where((m) => m.isMod).toList();
    final members = sorted.where((m) => !m.isMod).toList();
    final total = mods.length + members.length;

    return Container(
      color: const Color(0xFF100F17),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.people_rounded,
                      color: Colors.purpleAccent, size: 26),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onLongPress: _isFetching ? null : () => _start(forceRefresh: true),
                    child: const Text('Members',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  if (total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.purpleAccent.withValues(alpha: 0.35)),
                      ),
                      child: Text('$total',
                          style: const TextStyle(
                              color: Colors.purpleAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    ),
                  IconButton(
                    icon: Icon(
                      _sortMode == _SortMode.name
                          ? Icons.sort_by_alpha_rounded
                          : _sortMode == _SortMode.likes
                              ? Icons.favorite_rounded
                              : Icons.chat_bubble_outline_rounded,
                      color: Colors.white54,
                      size: 22,
                    ),
                    tooltip: 'Sort by: ${_sortMode.name}',
                    onPressed: () {
                      setState(() {
                        _sortMode = _SortMode.values[
                            (_sortMode.index + 1) % _SortMode.values.length];
                      });
                    },
                  ),

                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                _isFetching ? _status : 'Abyssians of The Abyss community',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
            if (_isFetching)
              LinearProgressIndicator(
                backgroundColor: Colors.white10,
                color: Colors.purpleAccent.withValues(alpha: 0.7),
                minHeight: 2,
              ),
            const Divider(color: Colors.white10, height: 1),

            // ── Body ───────────────────────────────────────
            Expanded(
              child: _hasError
                  ? _buildError()
                  : _all.isEmpty && _isFetching
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Colors.purpleAccent))
                  : _all.isEmpty && !_isFetching
                      ? _buildRetry()
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            if (mods.isNotEmpty) ...[
                              _sectionHeader(Icons.shield_rounded,
                                  'Moderators', Colors.amberAccent),
                              ...mods.map(_buildTile),
                            ],
                            _sectionHeader(Icons.star_rounded,
                                'Abyssians', Colors.purpleAccent),
                            if (members.isEmpty && !_isFetching)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('No members yet',
                                    style:
                                        TextStyle(color: Colors.white38)),
                              )
                            else
                              ...members.map(_buildTile),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 52),
          const SizedBox(height: 12),
          const Text('Failed to load members',
              style: TextStyle(color: Colors.white54, fontSize: 15)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _start(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.purpleAccent,
              side: const BorderSide(color: Colors.purpleAccent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // Shown when list is empty after a completed fetch (e.g. API rate-limited)
  Widget _buildRetry() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white24, size: 52),
          const SizedBox(height: 12),
          const Text('No members loaded',
              style: TextStyle(color: Colors.white54, fontSize: 15)),
          const SizedBox(height: 6),
          const Text('Tap retry — the API may have been busy',
              style: TextStyle(color: Colors.white30, fontSize: 13)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _start(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.purpleAccent,
              side: const BorderSide(color: Colors.purpleAccent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }


  Widget _sectionHeader(IconData icon, String title, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Text(title.toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: color.withValues(alpha: 0.25))),
        ],
      ),
    );
  }

  Widget _buildTile(_Member m) {
    return InkWell(
      onTap: m.profileUrl.isNotEmpty
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      _ProfilePage(name: m.name, url: m.profileUrl),
                ),
              )
          : null,
      child: Container(
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF282436),
            backgroundImage:
                m.avatar.isNotEmpty ? NetworkImage(m.avatar) : null,
            child: m.avatar.isEmpty
                ? const Icon(Icons.person, color: Colors.white38)
                : null,
          ),
          title: Text(m.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15)),
          subtitle: Text('@${m.username}',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          trailing: m.statsLoaded
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded,
                        color: Colors.white38, size: 13),
                    const SizedBox(width: 3),
                    Text(_fmt(m.numPosts),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                    const SizedBox(width: 8),
                    const Icon(Icons.favorite_rounded,
                        color: Colors.pinkAccent, size: 13),
                    const SizedBox(width: 3),
                    Text(_fmt(m.numLikes),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                  ],
                )
              : const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white24,
                  ),
                ),
        ),
      ),
    );
  }
}
