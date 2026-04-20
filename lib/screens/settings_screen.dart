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
  bool isAutoActive = true;
  int scheduledHour = 6;
  int scheduledMinute = 0;
  String customApiKey = '';
  int wallpaperLocation = 3; // 1: Home, 2: Lock, 3: Both
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final settings = await ScheduleHelper.loadSettings();
    setState(() {
      isAutoActive = settings['isAutoActive'];
      scheduledHour = settings['hour'];
      scheduledMinute = settings['minute'];
      customApiKey = settings['customApiKey'];
      wallpaperLocation = settings['wallpaperLocation'];
      _isLoading = false;
    });
  }

  Future<void> _updateSchedule() async {
    if (isAutoActive) {
      await ScheduleHelper.scheduleBackgroundTask(scheduledHour, scheduledMinute);
    } else {
      await ScheduleHelper.cancelBackgroundTask();
    }
  }

  Future<void> _saveSettings() async {
    await ScheduleHelper.saveSettings(
      isAutoActive: isAutoActive,
      hour: scheduledHour,
      minute: scheduledMinute,
      customApiKey: customApiKey,
      wallpaperLocation: wallpaperLocation,
    );
    await _updateSchedule();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF6366F1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F23),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F23),
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Automation'),
            const SizedBox(height: 12),
            _buildAutoToggleCard(),
            const SizedBox(height: 16),
            if (isAutoActive) _buildTimePickerCard(),
            const SizedBox(height: 16),
            _buildLocationPickerCard(),
            const SizedBox(height: 32),
            _buildSectionTitle('API Configuration'),
            const SizedBox(height: 12),
            _buildApiKeyCard(),
            const SizedBox(height: 32),
            _buildSectionTitle('About'),
            const SizedBox(height: 12),
            _buildAboutCard(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildAutoToggleCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        value: isAutoActive,
        onChanged: (val) {
          setState(() => isAutoActive = val);
          _saveSettings();
        },
        title: const Text(
          'Enable Auto-Change',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Set a daily wallpaper automatically',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        activeThumbColor: const Color(0xFF6366F1),
        activeColor: const Color(0xFF6366F1).withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildTimePickerCard() {
    final time = TimeOfDay(hour: scheduledHour, minute: scheduledMinute);
    final formattedTime = DateFormat.jm().format(
      DateTime(2024, 1, 1, scheduledHour, scheduledMinute),
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.access_time, color: Color(0xFF818CF8)),
        ),
        title: const Text(
          'Daily Schedule',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Set every day at $formattedTime',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: time,
            builder: (context, child) {
              return Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFF6366F1),
                    onPrimary: Colors.white,
                    surface: Color(0xFF1A1A3E),
                    onSurface: Colors.white,
                  ),
                ),
                child: child!,
              );
            },
          );
          if (picked != null) {
            setState(() {
              scheduledHour = picked.hour;
              scheduledMinute = picked.minute;
            });
            _saveSettings();
            _showSnackBar('✓ Schedule updated to $formattedTime');
          }
        },
      ),
    );
  }

  Widget _buildLocationPickerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.layers, color: Colors.white54, size: 20),
              SizedBox(width: 8),
              Text(
                'Wallpaper Location',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildChoiceChip('Home', 1),
              const SizedBox(width: 8),
              _buildChoiceChip('Lock', 2),
              const SizedBox(width: 8),
              _buildChoiceChip('Both', 3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(String label, int value) {
    final isSelected = wallpaperLocation == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => wallpaperLocation = value);
          _saveSettings();
        }
      },
      selectedColor: const Color(0xFF6366F1),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white54,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: const Color(0xFF0F0F23),
      checkmarkColor: Colors.white,
    );
  }

  Widget _buildApiKeyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Unsplash Access Key',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Required to fetch high-quality images from Unsplash.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: TextEditingController(text: customApiKey),
            onChanged: (val) => customApiKey = val,
            onSubmitted: (val) {
              customApiKey = val;
              _saveSettings();
              _showSnackBar('✓ API Key saved');
            },
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Enter your access key...',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: const Color(0xFF0F0F23),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Best of Day',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The app uses a deterministic strategy to pick one high-quality "Featured" wallpaper for every day of the month.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text(
            'All images are portrait-optimized for mobile devices and provided by the Unsplash community.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
