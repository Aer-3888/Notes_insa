import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../components/app_drawer.dart';
import '../background_tasks.dart';

// Settings screen for background fetch configuration.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _fetchIntervalKey = 'background_fetch_interval';
  static const String _fetchEnabledKey = 'background_fetch_enabled';

  final List<int> _availableIntervals = [1, 5, 15, 30, 60];
  int _selectedInterval = 15;
  bool _isLoading = true;
  bool _fetchEnabled = true;

  // Load stored settings.
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedInterval = prefs.getInt(_fetchIntervalKey);
      final savedEnabled = prefs.getBool(_fetchEnabledKey) ?? true;

      setState(() {
        if (savedInterval != null &&
            _availableIntervals.contains(savedInterval)) {
          _selectedInterval = savedInterval;
        }
        _fetchEnabled = savedEnabled;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Save selected interval and restart background tasks.
  Future<void> _saveInterval(int interval) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_fetchIntervalKey, interval);

      setState(() {
        _selectedInterval = interval;
      });

      await stopBackgroundTasks();
      await initBackgroundTasks();
      await _loadSettings();
    } catch (_) {
      // Fail silently
    }
  }

  // Toggle background fetch on/off.
  Future<void> _toggleFetchEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_fetchEnabledKey, enabled);

      setState(() {
        _fetchEnabled = enabled;
      });

      if (enabled) {
        await initBackgroundTasks();
      } else {
        await stopBackgroundTasks();
      }
    } catch (_) {
      // Fail silently
    }
  }

  String _getIntervalLabel(int minutes) {
    if (minutes == 1) return '1 minute';
    if (minutes < 60) return '$minutes minutes';
    final hours = minutes ~/ 60;
    return '$hours hour${hours > 1 ? 's' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(selected: DrawerItem.settings),
      appBar: AppBar(
        toolbarHeight: 84,
        elevation: 4,
        automaticallyImplyLeading: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF283593), Color(0xFF5C6BC0)],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(left: 6.0),
            child: IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Background Fetch Interval',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'How often to check for new grades',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.85,
                              child: Switch(
                                value: _fetchEnabled,
                                onChanged: _toggleFetchEnabled,
                                activeThumbColor: Colors.green,
                                activeTrackColor: Colors.green.shade200,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Opacity(
                          opacity: _fetchEnabled ? 1.0 : 0.4,
                          child: IgnorePointer(
                            ignoring: !_fetchEnabled,
                            child: Column(
                              children: [
                                ..._availableIntervals.map((interval) {
                                  final isSelected =
                                      _selectedInterval == interval;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: InkWell(
                                      onTap: () => _saveInterval(interval),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.indigo.shade50
                                              : Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? Colors.indigo.shade700
                                                : Colors.grey.shade300,
                                            width: isSelected ? 2 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _getIntervalLabel(interval),
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                  color: isSelected
                                                      ? Colors.indigo.shade900
                                                      : Colors.grey.shade700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
