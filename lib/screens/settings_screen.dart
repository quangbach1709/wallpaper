import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/wallpaper_service.dart';
import '../utils/notification_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isAutoActive = true;
  int _scheduledHour = 6;
  int _scheduledMinute = 0;
  String _customApiKey = '';
  bool _obscureApiKey = true;
  int _wallpaperLocation = 3;

  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await ScheduleHelper.loadSettings();
    setState(() {
      _isAutoActive = settings['isAutoActive'] ?? true;
      _scheduledHour = settings['hour'] ?? 6;
      _scheduledMinute = settings['minute'] ?? 0;
      _customApiKey = settings['customApiKey'] ?? '';
      _wallpaperLocation = settings['wallpaperLocation'] ?? 3;
      _apiKeyController.text = _customApiKey;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await ScheduleHelper.saveSettings(
      isAutoActive: _isAutoActive,
      hour: _scheduledHour,
      minute: _scheduledMinute,
      customApiKey: _customApiKey,
      wallpaperLocation: _wallpaperLocation,
    );
  }

  Future<void> _toggleAutoChange(bool value) async {
    setState(() => _isAutoActive = value);
    await _saveSettings();

    if (value) {
      // Enable: request permission and schedule the task
      await NotificationHelper.requestPermissions();

      await ScheduleHelper.scheduleBackgroundTask(
        _scheduledHour,
        _scheduledMinute,
      );
      _showSnackBar('Auto-change enabled for ${_formatTime()}');
    } else {
      // Disable: cancel the task
      await ScheduleHelper.cancelBackgroundTask();
      _showSnackBar('Auto-change disabled');
    }
  }

  Future<void> _pickTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _scheduledHour, minute: _scheduledMinute),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6366F1),
              surface: Color(0xFF1A1A3E),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime != null) {
      setState(() {
        _scheduledHour = pickedTime.hour;
        _scheduledMinute = pickedTime.minute;
      });
      await _saveSettings();

      // Reschedule if auto is active
      if (_isAutoActive) {
        await ScheduleHelper.scheduleBackgroundTask(
          _scheduledHour,
          _scheduledMinute,
        );
        _showSnackBar('Rescheduled for ${_formatTime()}');
      }
    }
  }

  void _onApiKeyChanged(String value) {
    _customApiKey = value.trim();
  }

  Future<void> _testBackgroundTask() async {
    if (_isLoading) return;

    if (_customApiKey.isEmpty) {
      _showSnackBar('⚠️ Please verify API Key first', isWarning: true);
      return;
    }

    setState(() => _isLoading = true);
    _showSnackBar('Testing background task... (Check both screens)');

    try {
      final success = await WallpaperService.executeBackgroundTask();
      if (success) {
        _showSnackBar('✓ Background task executed successfully!');
      } else {
        _showSnackBar(
          '✗ Background task failed. Check logs/connection.',
          isWarning: true,
        );
      }
    } catch (e) {
      _showSnackBar('Error: $e', isWarning: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveApiKey() async {
    // Validate API Key: Alphanumeric, reasonable length (Unsplash keys are ~43-50 chars usually, but we'll accept 20+)
    final validKeyRegex = RegExp(r'^[a-zA-Z0-9\-_]{20,}$');
    if (_customApiKey.isNotEmpty && !validKeyRegex.hasMatch(_customApiKey)) {
      _showSnackBar(
        '⚠️ Invalid API Key format. Cleaning up...',
        isWarning: true,
      );
      setState(() {
        _customApiKey = '';
        _apiKeyController.clear();
      });
      await _saveSettings(); // Save empty to clear garbage
      return;
    }

    await _saveSettings();
    if (_customApiKey.isEmpty) {
      _showSnackBar(
        '⚠️ API key is required to load wallpapers',
        isWarning: true,
      );
    } else {
      _showSnackBar('✓ API key saved successfully');
    }
  }

  String _formatTime() {
    final time = DateTime(2000, 1, 1, _scheduledHour, _scheduledMinute);
    return DateFormat('hh:mm a').format(time);
  }

  void _showSnackBar(String message, {bool isWarning = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: isWarning ? Colors.orange : const Color(0xFF6366F1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0F0F23),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0F23), Color(0xFF1A1A3E), Color(0xFF0F0F23)],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionHeader('Auto-Change Wallpaper'),
                  _buildAutoChangeCard(),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Wallpaper History'),
                  _buildHistoryCard(),
                  const SizedBox(height: 24),
                  _buildSectionHeader('API Configuration'),
                  _buildApiKeyCard(),
                  const SizedBox(height: 24),
                  _buildInfoCard(),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF6366F1),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildAutoChangeCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Toggle
          SwitchListTile(
            title: const Text(
              'Enable Auto-Change',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              _isAutoActive
                  ? 'Wallpaper changes daily at ${_formatTime()}'
                  : 'Automatic wallpaper change is disabled',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            value: _isAutoActive,
            onChanged: _toggleAutoChange,
            activeColor: const Color(0xFF6366F1),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
          ),
          // Divider
          if (_isAutoActive)
            const Divider(
              color: Colors.white12,
              height: 1,
              indent: 16,
              endIndent: 16,
            ),
          // Time Picker
          if (_isAutoActive)
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  color: Color(0xFF6366F1),
                ),
              ),
              title: const Text(
                'Change Time',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                _formatTime(),
                style: const TextStyle(color: Colors.white60),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: _pickTime,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
            ),
          // Test Button
          if (_isAutoActive) ...[
            const Divider(
              color: Colors.white12,
              height: 1,
              indent: 16,
              endIndent: 16,
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.phone_android_rounded,
                  color: Color(0xFF6366F1),
                ),
              ),
              title: const Text(
                'Auto-Update Location',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: const Text(
                'Which screen to update automatically',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              trailing: DropdownButton<int>(
                value: _wallpaperLocation,
                dropdownColor: const Color(0xFF1A1A3E),
                underline: const SizedBox.shrink(),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Home Screen Only')),
                  DropdownMenuItem(value: 2, child: Text('Lock Screen Only')),
                  DropdownMenuItem(value: 3, child: Text('Both Screens')),
                ],
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() => _wallpaperLocation = value);
                  await _saveSettings();
                },
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
            ),
            const Divider(
              color: Colors.white12,
              height: 1,
              indent: 16,
              endIndent: 16,
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.build_circle_outlined,
                  color: Colors.orange,
                ),
              ),
              title: const Text(
                'Test Background Task Now',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: const Text(
                'Immediately trigger wallpaper change',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              onTap: _testBackgroundTask,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _clearWallpaperHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A3E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear Wallpaper History?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will reset the history and allow previously used wallpapers to appear again.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await WallpaperService.clearWallpaperHistory();
      _showSnackBar('✓ Wallpaper history cleared');
    }
  }

  Widget _buildHistoryCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.history, color: Colors.redAccent),
        ),
        title: const Text(
          'Clear Wallpaper History',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        subtitle: const Text(
          'Allow previously used wallpapers to appear again',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: _clearWallpaperHistory,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Widget _buildApiKeyCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3E),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Unsplash Access Key (Required)',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _customApiKey.isEmpty
                ? '⚠️ You must enter your Unsplash API key to use this app.'
                : '✓ API key is configured',
            style: TextStyle(
              color: _customApiKey.isEmpty ? Colors.orange : Colors.green,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Get your free key at unsplash.com/developers',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            onChanged: _onApiKeyChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter your access key here',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF0F0F23),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF6366F1),
                  width: 2,
                ),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white38,
                    ),
                    onPressed: () {
                      setState(() => _obscureApiKey = !_obscureApiKey);
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.save_rounded,
                      color: Color(0xFF6366F1),
                    ),
                    onPressed: _saveApiKey,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFF6366F1), size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Wallpapers are cached for 60 minutes. Pull down on the gallery to force refresh.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
