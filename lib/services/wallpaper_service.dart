import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';
import 'package:workmanager/workmanager.dart';
import '../utils/notification_helper.dart';

/// Unsplash API Configuration
const String _unsplashBaseUrl = 'https://api.unsplash.com';

/// SharedPreferences Keys
const String prefKeyIsAutoActive = 'is_auto_active';
const String prefKeyScheduledHour = 'scheduled_hour';
const String prefKeyScheduledMinute = 'scheduled_minute';
const String prefKeyCustomApiKey = 'custom_api_key';
const String prefKeyCachedWallpapers = 'cached_wallpapers_json';
const String prefKeyCachedTimestamp = 'cached_wallpapers_timestamp';
const String prefKeyWallpaperLocation = 'auto_wallpaper_location';

/// WorkManager task name
const String dailyWallpaperTaskName = 'dailyWallpaperTask';
const String dailyWallpaperTaskId = 'dailyWallpaper';

/// Cache Configuration
const int cacheDurationMinutes = 60;

/// Enum for wallpaper location options
enum WallpaperLocation { homeScreen, lockScreen, both }

/// Model class representing an Unsplash image
class UnsplashImage {
  final String id;
  final String regularUrl;
  final String fullUrl;
  final String thumbUrl;
  final String? description;
  final String photographerName;
  final int width;
  final int height;

  UnsplashImage({
    required this.id,
    required this.regularUrl,
    required this.fullUrl,
    required this.thumbUrl,
    this.description,
    required this.photographerName,
    required this.width,
    required this.height,
  });

  factory UnsplashImage.fromJson(Map<String, dynamic> json) {
    final urls = json['urls'] as Map<String, dynamic>;
    final user = json['user'] as Map<String, dynamic>;

    return UnsplashImage(
      id: json['id'] ?? '',
      regularUrl: urls['regular'] ?? '',
      fullUrl: urls['full'] ?? '',
      thumbUrl: urls['thumb'] ?? '',
      description: json['description'] ?? json['alt_description'],
      photographerName: user['name'] ?? 'Unknown',
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'urls': {'regular': regularUrl, 'full': fullUrl, 'thumb': thumbUrl},
    'description': description,
    'user': {'name': photographerName},
    'width': width,
    'height': height,
  };

  String get displayTitle => description ?? 'Photo by $photographerName';
}

/// Service class for handling wallpaper operations with Unsplash API
class WallpaperService {
  /// Check if API key is configured
  static Future<bool> hasApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final customKey = prefs.getString(prefKeyCustomApiKey);
    return customKey != null && customKey.trim().isNotEmpty;
  }

  /// Get the active API key
  static Future<String?> _getActiveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final customKey = prefs.getString(prefKeyCustomApiKey);
    return (customKey != null && customKey.trim().isNotEmpty) ? customKey.trim() : null;
  }

  /// Get headers with dynamic API key
  static Future<Map<String, String>> _getHeaders() async {
    final apiKey = await _getActiveApiKey();
    if (apiKey == null) {
      throw Exception('No API key configured. Please add your Unsplash Access Key in Settings.');
    }
    return {'Authorization': 'Client-ID $apiKey', 'Accept-Version': 'v1'};
  }

  /// Check if cache is valid
  static Future<bool> _isCacheValid() async {
    final prefs = await SharedPreferences.getInstance();
    final timestampStr = prefs.getString(prefKeyCachedTimestamp);
    if (timestampStr == null) return false;
    final cachedTime = DateTime.tryParse(timestampStr);
    if (cachedTime == null) return false;
    return DateTime.now().difference(cachedTime).inMinutes < cacheDurationMinutes;
  }

  /// Get cached wallpapers
  static Future<List<UnsplashImage>?> _getCachedWallpapers() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(prefKeyCachedWallpapers);
    if (cachedJson == null) return null;
    try {
      final List<dynamic> data = json.decode(cachedJson);
      return data.map((j) => UnsplashImage.fromJson(j)).toList();
    } catch (e) {
      return null;
    }
  }

  /// Save to cache
  static Future<void> _cacheWallpapers(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKeyCachedWallpapers, json.encode(data));
    await prefs.setString(prefKeyCachedTimestamp, DateTime.now().toIso8601String());
  }

  /// Fetches mobile-optimized wallpapers for the gallery
  static Future<List<UnsplashImage>> fetchWallpapers({
    int page = 1,
    int count = 30,
    bool forceRefresh = false,
  }) async {
    if (page == 1 && !forceRefresh) {
      final isValid = await _isCacheValid();
      if (isValid) {
        final cached = await _getCachedWallpapers();
        if (cached != null && cached.isNotEmpty) return cached;
      }
    }

    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$_unsplashBaseUrl/search/photos').replace(
        queryParameters: {
          'query': 'wallpaper mobile phone',
          'per_page': count.toString(),
          'order_by': 'latest',
          'orientation': 'portrait',
          'page': page.toString(),
        },
      );

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> results = data['results'] ?? [];

        final filteredList = results.where((img) {
          final double h = (img['height'] as num).toDouble();
          final double w = (img['width'] as num).toDouble();
          return w > 0 && (h / w) > 1.2;
        }).toList();

        if (page == 1) {
          await _cacheWallpapers(filteredList);
        }

        return filteredList.map((json) => UnsplashImage.fromJson(json)).toList();
      } else {
        throw Exception('Failed: ${response.statusCode}');
      }
    } catch (e) {
      if (page == 1) {
        final cached = await _getCachedWallpapers();
        if (cached != null && cached.isNotEmpty) return cached;
      }
      throw Exception('Error fetching wallpapers: $e');
    }
  }

  /// Best of the day picker
  static Future<UnsplashImage> fetchRandomWallpaper() async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$_unsplashBaseUrl/photos').replace(
        queryParameters: {
          'orientation': 'portrait',
          'per_page': '31',
          'order_by': 'popular',
        },
      );

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final mobileOptimized = data.where((img) {
          final double h = (img['height'] as num).toDouble();
          final double w = (img['width'] as num).toDouble();
          return (h / w) > 1.2;
        }).toList();

        if (mobileOptimized.isNotEmpty) {
          final day = DateTime.now().day;
          final index = day % mobileOptimized.length;
          return UnsplashImage.fromJson(mobileOptimized[index]);
        }
        throw Exception('No featured mobile images found');
      } else {
        throw Exception('Failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error picking best of the day: $e');
    }
  }

  static Future<String> downloadImage(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      } else {
        throw Exception('Download failed');
      }
    } catch (e) {
      throw Exception('Error downloading: $e');
    }
  }

  static Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (e) { /* ignore */ }
  }

  static Future<bool> setWallpaper(String filePath, {WallpaperLocation location = WallpaperLocation.homeScreen}) async {
    try {
      final wm = WallpaperManagerFlutter();
      final file = File(filePath);
      switch (location) {
        case WallpaperLocation.homeScreen:
          return await wm.setWallpaper(file, WallpaperManagerFlutter.homeScreen);
        case WallpaperLocation.lockScreen:
          return await wm.setWallpaper(file, WallpaperManagerFlutter.lockScreen);
        case WallpaperLocation.both:
          // Setting both sequentially with a small delay can help the system process changes better in background
          final h = await wm.setWallpaper(file, WallpaperManagerFlutter.homeScreen);
          await Future.delayed(const Duration(milliseconds: 500));
          final l = await wm.setWallpaper(file, WallpaperManagerFlutter.lockScreen);
          return h && l;
      }
    } catch (e) {
      throw Exception('Set failed: $e');
    }
  }

  static Future<bool> setWallpaperFromUrl(String imageUrl, {WallpaperLocation location = WallpaperLocation.both}) async {
    String? filePath;
    try {
      filePath = await downloadImage(imageUrl);
      return await setWallpaper(filePath, location: location);
    } finally {
      if (filePath != null) await deleteFile(filePath);
    }
  }

  static Future<bool> executeBackgroundTask() async {
    try {
      await NotificationHelper.initialize();
      final image = await fetchRandomWallpaper();
      final prefs = await SharedPreferences.getInstance();
      final locInt = prefs.getInt(prefKeyWallpaperLocation) ?? 3;
      final location = locInt == 1 ? WallpaperLocation.homeScreen : locInt == 2 ? WallpaperLocation.lockScreen : WallpaperLocation.both;
      
      // Use regularUrl for background tasks to ensure system has enough memory to update all UI caches (like folder blur)
      final success = await setWallpaperFromUrl(image.regularUrl, location: location);
      if (success) await NotificationHelper.showWallpaperUpdated();
      return true;
    } catch (e) {
      return false;
    }
  }
}

class ScheduleHelper {
  static Duration calculateDelay(int hour, int minute) {
    final now = DateTime.now();
    var scheduledTime = DateTime(now.year, now.month, now.day, hour, minute, 0);
    if (now.isAfter(scheduledTime)) scheduledTime = scheduledTime.add(const Duration(days: 1));
    return scheduledTime.difference(now);
  }

  static Future<void> scheduleBackgroundTask(int hour, int minute) async {
    await Workmanager().cancelAll();
    final delay = calculateDelay(hour, minute);
    await Workmanager().registerPeriodicTask(
      dailyWallpaperTaskId,
      dailyWallpaperTaskName,
      initialDelay: delay,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  static Future<void> cancelBackgroundTask() async {
    await Workmanager().cancelByUniqueName(dailyWallpaperTaskId);
  }

  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'isAutoActive': prefs.getBool(prefKeyIsAutoActive) ?? true,
      'hour': prefs.getInt(prefKeyScheduledHour) ?? 6,
      'minute': prefs.getInt(prefKeyScheduledMinute) ?? 0,
      'customApiKey': prefs.getString(prefKeyCustomApiKey) ?? '',
      'wallpaperLocation': prefs.getInt(prefKeyWallpaperLocation) ?? 3,
    };
  }

  static Future<void> saveSettings({
    required bool isAutoActive,
    required int hour,
    required int minute,
    String? customApiKey,
    int? wallpaperLocation,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKeyIsAutoActive, isAutoActive);
    await prefs.setInt(prefKeyScheduledHour, hour);
    await prefs.setInt(prefKeyScheduledMinute, minute);
    if (customApiKey != null) await prefs.setString(prefKeyCustomApiKey, customApiKey);
    if (wallpaperLocation != null) await prefs.setInt(prefKeyWallpaperLocation, wallpaperLocation);
  }
}
