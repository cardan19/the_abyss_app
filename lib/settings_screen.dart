import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class SettingsScreen extends StatefulWidget {
  final Future<void> Function() onThemeChanged;

  const SettingsScreen({super.key, required this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String selectedTheme = 'Abyss Black';
  String customUrl = '';
  int textZoom = 100;
  String _commentHighlight = 'default'; // 'default' | 'dark' | 'light'

  final TextEditingController _urlController = TextEditingController();

  final List<String> themeOptions = [
    'Abyss Black',
    'Silk Red',
    'Midnight Purple',
    'Deep Ocean',
    'Custom URL',
    'Local Image'
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      String savedTheme = prefs.getString('theme') ?? 'Abyss Black';
      if (savedTheme == 'Original Theme (Mods)' || !themeOptions.contains(savedTheme)) {
        savedTheme = 'Abyss Black';
      }
      selectedTheme = savedTheme;
      textZoom = prefs.getInt('textZoom') ?? 100;
      customUrl = prefs.getString('customThemeUrl') ?? 'https://wallpapersok.com/images/high/moon-phone-varieties-n4a209i7cv27s620.webp';
      _urlController.text = customUrl;
      _commentHighlight = prefs.getString('commentHighlight') ?? 'default';
    });
  }

  Future<void> _saveTheme(String theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', theme);
    setState(() {
      selectedTheme = theme;
    });
    widget.onThemeChanged();
  }

  Future<void> _saveTextZoom(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('textZoom', value.toInt());
    widget.onThemeChanged();
  }

  Future<void> _saveCommentHighlight(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('commentHighlight', value);
    setState(() => _commentHighlight = value);
    widget.onThemeChanged();
  }

  Future<void> _saveCustomUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customThemeUrl', url);
    setState(() {
      customUrl = url;
    });
    widget.onThemeChanged();
  }

  Future<void> _pickLocalImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final directory = await getApplicationDocumentsDirectory();
      final String savedPath = '${directory.path}/custom_bg_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(image.path).copy(savedPath);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme', 'Local Image');
      await prefs.setString('localImagePath', savedPath);

      setState(() {
        selectedTheme = 'Local Image';
      });
      widget.onThemeChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0C12),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text('App Preferences', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        children: [
          _buildSectionHeader(Icons.text_increase_rounded, 'Chat Interface Scaling'),
          const SizedBox(height: 12),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Global Font Size', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text('$textZoom%', style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.purpleAccent,
                    inactiveTrackColor: const Color(0xFF282436),
                    thumbColor: Colors.white,
                    overlayColor: Colors.purpleAccent.withValues(alpha: 0.2),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: textZoom.toDouble(),
                    min: 50,
                    max: 200,
                    divisions: 15,
                    onChanged: (value) {
                      setState(() {
                        textZoom = value.toInt();
                      });
                    },
                    onChangeEnd: _saveTextZoom,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          _buildSectionHeader(Icons.wallpaper_rounded, 'Global Background Overlay'),
          const SizedBox(height: 12),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose Active Theme', style: TextStyle(color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1A27),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selectedTheme,
                      dropdownColor: const Color(0xFF282436),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.purpleAccent),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          _saveTheme(newValue);
                        }
                      },
                      items: themeOptions.map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                if (selectedTheme == 'Custom URL') ...[
                  const SizedBox(height: 24),
                  const Text('Image Direct URL', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1C1A27),
                      hintText: 'e.g. https://imgur.com/...png',
                      hintStyle: const TextStyle(color: Colors.white30),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.purpleAccent)),
                    ),
                    onSubmitted: _saveCustomUrl,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purpleAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _saveCustomUrl(_urlController.text),
                      child: const Text('Apply Target URL', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],

                if (selectedTheme == 'Local Image') ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.purpleAccent, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.photo_library_rounded, size: 22),
                      label: const Text('Pick Image From Gallery', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      onPressed: _pickLocalImage,
                    ),
                  ),
                ]
              ],
            ),
          ),

          const SizedBox(height: 32),

          _buildSectionHeader(Icons.format_color_fill_rounded, 'Comment Text Highlight'),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Adds a colour behind comment text — helps readability over busy backgrounds.',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            child: Row(
              children: [
                _hlOption('default', 'Default', null),
                const SizedBox(width: 10),
                _hlOption('dark',    'Dark',    Colors.black),
                const SizedBox(width: 10),
                _hlOption('light',   'Light',   Colors.white),
              ],
            ),
          ),

          const Center(
            child: Text('Version 1.0.0+1\nAdvanced Customization',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: Colors.purpleAccent, size: 22),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _hlOption(String value, String label, Color? swatch) {
    final bool selected = _commentHighlight == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _saveCommentHighlight(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? Colors.purpleAccent.withValues(alpha: 0.15)
                : const Color(0xFF1C1A27),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.purpleAccent : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26, height: 26,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 'default' gets a half-black / half-white gradient
                  gradient: swatch == null
                      ? const LinearGradient(
                          colors: [Colors.black, Colors.white],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                  color: swatch,
                  border: Border.all(color: Colors.white30, width: 1),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.purpleAccent : Colors.white70,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131219),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: child,
      ),
    );
  }
}
