import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

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

class ModProfile {
  final String role;
  final String age;
  final String gender;
  final String discord;
  ModProfile({required this.role, required this.age, required this.gender, required this.discord});
}

// ─── CSV parsing helpers ───────────────────────────────────
/// Splits a CSV body into non-empty lines, handling both \r\n and \n.
List<String> _csvLines(String body) =>
    body.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();

/// Parses one CSV row correctly — handles quoted fields that may contain
/// commas (e.g. display names like "Smith, John") or embedded quotes.
List<String> _csvRow(String line) {
  final fields = <String>[];
  final buf = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      // Two consecutive quotes inside a quoted field → literal quote char
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == ',' && !inQuotes) {
      fields.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  fields.add(buf.toString().trim());
  return fields;
}

/// Returns the index of the first header that matches any of [names]
/// (case-insensitive). Returns -1 if not found.
int _csvCol(List<String> headers, List<String> names) {
  final lc = names.map((n) => n.toLowerCase()).toSet();
  for (int i = 0; i < headers.length; i++) {
    if (lc.contains(headers[i].toLowerCase())) return i;
  }
  return -1;
}

/// Safely reads index [i] from a row, returning '' when out of bounds.
String _csvVal(List<String> row, int i) => i >= 0 && i < row.length ? row[i] : '';

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
  final Map<String, ModProfile> _modProfiles = {};
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
              // AWAIT the sheet fetch so profile data is always ready
              // before the user can tap a mod tile. Without await, there
              // is a race: the user taps before _modProfiles is populated
              // and gets redirected to Disqus instead of the profile card.
              await _fetchLiveProfiles();
              if (mounted) setState(() {});
              return; // Cache hit: skip Disqus API fetch
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
      // Run mods fetch and sheet fetch concurrently — saves ~1-2s
      final results = await Future.wait([
        _fetchMods(),
        _fetchLiveProfiles(),
      ]);
      final modIds = results[0] as Set<String>;

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
            avatar: user['avatar']?['large']?['cache'] ?? '',
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

  // ─── Step 1.5: Fetch Live Moderator Profiles from Google Sheets ──────
  Future<void> _fetchLiveProfiles() async {
    const csvUrl =
        'https://docs.google.com/spreadsheets/d/e/2PACX-1vTTjb619UDSm9GDLzwh2GII5YqN_UB6IqryyLO_RSjsbUM9E1QAYLJi_qSphTnSp-Q86CwXXYTB_6UC/pub?output=csv';
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    _modProfiles.clear(); // remove stale entries from previous fetch
    try {
      final req = await client.getUrl(Uri.parse(csvUrl));
      final res = await req.close();

      // Bail out early on HTTP errors (prevents silently parsing error pages)
      if (res.statusCode != HttpStatus.ok) {
        debugPrint('Live profiles: HTTP ${res.statusCode}');
        return;
      }

      final body = await res.transform(utf8.decoder).join();
      final lines = _csvLines(body);  // handles \r\n correctly
      if (lines.length < 2) return;

      // Detect column positions from the header row so order doesn't matter
      final headers = _csvRow(lines[0]);
      final colName    = _csvCol(headers, ['username', 'name']);
      final colRole    = _csvCol(headers, ['role']);
      final colAge     = _csvCol(headers, ['age']);
      final colGender  = _csvCol(headers, ['gender']);
      final colDiscord = _csvCol(headers, ['discord', '@discord', 'discordtag']);

      if (colName < 0) {
        debugPrint('Live profiles: no Username column found in sheet');
        return;
      }

      for (int i = 1; i < lines.length; i++) {
        final row = _csvRow(lines[i]);
        final key = _csvVal(row, colName);
        if (key.isEmpty) continue;

        // Store under lower-case key so lookup is case-insensitive
        _modProfiles[key.toLowerCase()] = ModProfile(
          role:    _csvVal(row, colRole),
          age:     _csvVal(row, colAge),
          gender:  _csvVal(row, colGender),
          discord: _csvVal(row, colDiscord),
        );
      }
      debugPrint('Live profiles loaded: ${_modProfiles.length} entries');
    } catch (e) {
      debugPrint('Failed to load live profiles: $e');
    } finally {
      client.close();
    }
  }

  /// Looks up a custom profile for [m] trying both the Disqus username
  /// and display name (case-insensitive). Returns null if not in the sheet.
  ModProfile? _findModProfile(_Member m) {
    return _modProfiles[m.username.toLowerCase()]
        ?? _modProfiles[m.name.toLowerCase()];
  }

  /// Returns true if the member should appear under MODERATORS.
  /// Uses Disqus API isMod flag OR Google Sheet presence as the source of truth.
  /// This ensures sheet-listed mods always appear in the Moderators section,
  /// even if the Disqus listModerators API missed them.
  bool _isEffectiveMod(_Member m) =>
      m.isMod || _findModProfile(m) != null;

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
            avatar: user['avatar']?['large']?['cache'] ?? '',
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
              avatar: u['avatar']?['large']?['cache'] ?? '',
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
    final mods    = sorted.where(_isEffectiveMod).toList();
    final members = sorted.where((m) => !_isEffectiveMod(m)).toList();
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
    // Case-insensitive lookup — tries Disqus username then display name
    final sheetProfile = _findModProfile(m);

    // Everyone gets the profile card.
    // If they have a row in the sheet → show their real info.
    // If not in the sheet yet → show '--' for every field.
    final effectiveProfile = sheetProfile ??
        ModProfile(role: '--', age: '--', gender: '--', discord: '--');

    return InkWell(
      onTap: () => _showCustomProfile(m, effectiveProfile),
      child: Container(
        decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: SizedBox(
            width: 44,
            height: 44,
            child: m.avatar.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      m.avatar,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => const CircleAvatar(
                        radius: 22,
                        backgroundColor: Color(0xFF282436),
                        child: Icon(Icons.person, color: Colors.white38),
                      ),
                    ),
                  )
                : const CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(0xFF282436),
                    child: Icon(Icons.person, color: Colors.white38),
                  ),
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


  void _showCustomProfile(_Member m, ModProfile p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF16151D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(bottom: 30, top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              
              // Avatar
              SizedBox(
                width: 92,
                height: 92,
                child: m.avatar.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          m.avatar,
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => const CircleAvatar(
                            radius: 46,
                            backgroundColor: Color(0xFF282436),
                            child: Icon(Icons.person, size: 40, color: Colors.white38),
                          ),
                        ),
                      )
                    : const CircleAvatar(
                        radius: 46,
                        backgroundColor: Color(0xFF282436),
                        child: Icon(Icons.person, size: 40, color: Colors.white38),
                      ),
              ),
              const SizedBox(height: 16),
              
              // Name and Username
              Text(m.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('@${m.username}', style: const TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 16),
              
              // Role Badge
              if (p.role.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    p.role.toUpperCase(),
                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
                  ),
                ),
                
              const SizedBox(height: 24),
              
              // Details Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (p.age.isNotEmpty)
                      _buildProfileDetail(Icons.cake_rounded, 'Age', p.age),
                    if (p.gender.isNotEmpty)
                      _buildProfileDetail(Icons.person_outline_rounded, 'Gender', p.gender),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Discord Tag Button
              if (p.discord.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    children: [
                      const Icon(Icons.discord, color: Color(0xFF5865F2), size: 14),
                      const SizedBox(width: 6),
                      const Text(
                        'DISCORD',
                        style: TextStyle(
                          color: Color(0xFF5865F2),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Material(
                    color: const Color(0xFF5865F2).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: p.discord));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Discord tag copied to clipboard!'),
                            backgroundColor: Colors.purpleAccent,
                            duration: Duration(seconds: 2),
                          ),
                        );
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF5865F2).withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.alternate_email_rounded, color: Color(0xFF5865F2), size: 24),
                            const SizedBox(width: 12),
                            Text(p.discord, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                            const Spacer(),
                            const Icon(Icons.copy_rounded, color: Colors.white54, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ], // end discord spread list
                
              const SizedBox(height: 20),
              
              // View Full Profile Button
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  if (m.profileUrl.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => _ProfilePage(name: m.name, url: m.profileUrl)),
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.white54),
                label: const Text('View Full Disqus Profile', style: TextStyle(color: Colors.white54)),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileDetail(IconData icon, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.purpleAccent, size: 28),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
      ],
    );
  }
}
