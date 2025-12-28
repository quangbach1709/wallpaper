import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';
import 'package:workmanager/workmanager.dart';
import '../utils/notification_helper.dart';

/// Unsplash API Configuration
/// NOTE: No default key - user must enter their own key in Settings
const String _unsplashBaseUrl = 'https://api.unsplash.com';

/// SharedPreferences Keys
const String prefKeyIsAutoActive = 'is_auto_active';
const String prefKeyScheduledHour = 'scheduled_hour';
const String prefKeyScheduledMinute = 'scheduled_minute';
const String prefKeyCustomApiKey = 'custom_api_key';
const String prefKeyCachedWallpapers = 'cached_wallpapers_json';
const String prefKeyCachedTimestamp = 'cached_wallpapers_timestamp';

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

  /// Get the active API key (user must provide in Settings)
  static Future<String?> _getActiveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final customKey = prefs.getString(prefKeyCustomApiKey);
    if (customKey != null && customKey.trim().isNotEmpty) {
      return customKey.trim();
    }
    return null; // No key configured
  }

  /// Get headers with dynamic API key
  static Future<Map<String, String>> _getHeaders() async {
    final apiKey = await _getActiveApiKey();
    if (apiKey == null) {
      throw Exception(
        'No API key configured. Please add your Unsplash Access Key in Settings.',
      );
    }

    // Sanitize to prevent header injection/format errors
    // Limit length to 100 just in case and remove non-alphanumeric chars
    final sanitizedKey = apiKey.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '');
    if (sanitizedKey.isEmpty) {
      throw Exception('Invalid API Key format.');
    }

    return {'Authorization': 'Client-ID $sanitizedKey', 'Accept-Version': 'v1'};
  }

  /// Check if cache is valid (less than 60 minutes old)
  static Future<bool> _isCacheValid() async {
    final prefs = await SharedPreferences.getInstance();
    final timestampStr = prefs.getString(prefKeyCachedTimestamp);
    if (timestampStr == null) return false;

    final cachedTime = DateTime.tryParse(timestampStr);
    if (cachedTime == null) return false;

    final difference = DateTime.now().difference(cachedTime);
    return difference.inMinutes < cacheDurationMinutes;
  }

  /// Get cached wallpapers from SharedPreferences
  static Future<List<UnsplashImage>?> _getCachedWallpapers() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(prefKeyCachedWallpapers);
    if (cachedJson == null) return null;

    try {
      final List<dynamic> data = json.decode(cachedJson);
      return data.map((json) => UnsplashImage.fromJson(json)).toList();
    } catch (e) {
      return null;
    }
  }

  /// Save wallpapers to cache
  static Future<void> _cacheWallpapers(String jsonResponse) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKeyCachedWallpapers, jsonResponse);
    await prefs.setString(
      prefKeyCachedTimestamp,
      DateTime.now().toIso8601String(),
    );
  }

  /// Fetches trending portrait wallpapers for the gallery
  static Future<List<UnsplashImage>> fetchTrendingWallpapers({
    int count = 30,
    bool forceRefresh = false,
  }) async {
    // Check cache (unless force refresh)
    if (!forceRefresh) {
      final isValid = await _isCacheValid();
      if (isValid) {
        final cached = await _getCachedWallpapers();
        if (cached != null && cached.isNotEmpty) {
          return cached;
        }
      }
    }

    // Fetch from API
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$_unsplashBaseUrl/photos').replace(
        queryParameters: {
          'per_page': count.toString(),
          'order_by': 'popular',
          'orientation': 'portrait',
        },
      );

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        await _cacheWallpapers(response.body);
        final List<dynamic> data = json.decode(response.body);

        // Filter: Keep only TALL images (ratio > 1.2)
        // Ratio = Height / Width
        final filteredList = data.where((img) {
          final double h = (img['height'] as num).toDouble();
          final double w = (img['width'] as num).toDouble();
          return (h / w) > 1.2;
        }).toList();

        return filteredList
            .map((json) => UnsplashImage.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      // Fallback to cache on error
      final cached = await _getCachedWallpapers();
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      throw Exception('Error fetching wallpapers: $e');
    }
  }

  /// Fetches a random portrait wallpaper for background task
  static Future<UnsplashImage> fetchRandomWallpaper() async {
    try {
      final headers = await _getHeaders();
      // Request buffer of 10 images to ensure we find one with good ratio
      final uri = Uri.parse('$_unsplashBaseUrl/photos/random').replace(
        queryParameters: {
          'orientation': 'portrait',
          'query': 'nature,architecture,abstract',
          'count': '10',
        },
      );

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        // Find first image with ratio > 1.2
        final validImgJson = data.firstWhere((img) {
          final double h = (img['height'] as num).toDouble();
          final double w = (img['width'] as num).toDouble();
          return (h / w) > 1.2;
        }, orElse: () => null);

        if (validImgJson != null) {
          return UnsplashImage.fromJson(validImgJson);
        }

        // Fallback: If no strict portrait found, just take the first one
        if (data.isNotEmpty) {
          return UnsplashImage.fromJson(data.first);
        }

        throw Exception('No images returned from API');
      } else {
        throw Exception('Failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching random wallpaper: $e');
    }
  }

  /// Downloads an image to the temporary directory
  static Future<String> downloadImage(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName =
            'wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final filePath = '${tempDir.path}/$fileName';

        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        return filePath;
      } else {
        throw Exception('Failed to download: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error downloading image: $e');
    }
  }

  /// Deletes a file from storage
  static Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error deleting file: $e');
    }
  }

  /// Deletes multiple files from storage
  static Future<void> deleteFiles(List<String> filePaths) async {
    for (final path in filePaths) {
      await deleteFile(path);
    }
  }

  /// Sets wallpaper from a file path to specified location(s)
  static Future<bool> setWallpaper(
    String filePath, {
    WallpaperLocation location = WallpaperLocation.homeScreen,
  }) async {
    try {
      final wallpaperManager = WallpaperManagerFlutter();
      final file = File(filePath);

      switch (location) {
        case WallpaperLocation.homeScreen:
          return await wallpaperManager.setWallpaper(
            file,
            WallpaperManagerFlutter.homeScreen,
          );
        case WallpaperLocation.lockScreen:
          return await wallpaperManager.setWallpaper(
            file,
            WallpaperManagerFlutter.lockScreen,
          );
        case WallpaperLocation.both:
          final homeResult = await wallpaperManager.setWallpaper(
            file,
            WallpaperManagerFlutter.homeScreen,
          );
          final lockResult = await wallpaperManager.setWallpaper(
            file,
            WallpaperManagerFlutter.lockScreen,
          );
          return homeResult && lockResult;
      }
    } catch (e) {
      throw Exception('Error setting wallpaper: $e');
    }
  }

  /// Complete flow: Download -> Set Wallpaper -> Delete temp file
  static Future<bool> setWallpaperFromUrl(
    String imageUrl, {
    WallpaperLocation location = WallpaperLocation.both,
  }) async {
    String? filePath;
    try {
      filePath = await downloadImage(imageUrl);
      final result = await setWallpaper(filePath, location: location);
      return result;
    } catch (e) {
      rethrow;
    } finally {
      if (filePath != null) {
        await deleteFile(filePath);
      }
    }
  }

  /// Sets wallpaper from a local file path with cleanup
  static Future<bool> setWallpaperFromFile(
    String filePath, {
    required WallpaperLocation location,
    List<String> filesToCleanup = const [],
  }) async {
    try {
      final result = await setWallpaper(filePath, location: location);
      return result;
    } catch (e) {
      rethrow;
    } finally {
      await deleteFiles(filesToCleanup);
    }
  }

  /// Background task entry point for WorkManager
  static Future<bool> executeBackgroundTask() async {
    try {
      print('=== Background Task Started ===');

      // Ensure notifications are initialized in background isolate
      await NotificationHelper.initialize();
      print('Notifications initialized');

      print('Fetching random wallpaper...');
      final image = await fetchRandomWallpaper();
      print('Got image: ${image.id}');

      print('Setting wallpaper from URL...');
      final result = await setWallpaperFromUrl(
        image.fullUrl,
        location: WallpaperLocation.both,
      );
      print('Set wallpaper result: $result');

      if (result) {
        await NotificationHelper.showWallpaperUpdated();
        print('Notification sent!');
      }

      print('=== Background Task Completed Successfully ===');
      return result;
    } catch (e, stackTrace) {
      print('=== Background task failed ===');
      print('Error: $e');
      print('StackTrace: $stackTrace');
      return false;
    }
  }
}

/// Helper class for WorkManager scheduling
class ScheduleHelper {
  /// Calculate initial delay to target a specific hour:minute
  static Duration calculateDelay(int hour, int minute) {
    final now = DateTime.now();
    var scheduledTime = DateTime(now.year, now.month, now.day, hour, minute, 0);

    // If target time has passed today, schedule for tomorrow
    if (now.isAfter(scheduledTime)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    return scheduledTime.difference(now);
  }

  /// Schedule the background task at specified time
  static Future<void> scheduleBackgroundTask(int hour, int minute) async {
    // Cancel existing task first
    await Workmanager().cancelByUniqueName(dailyWallpaperTaskId);

    // Calculate delay
    final delay = calculateDelay(hour, minute);

    // Register new periodic task
    await Workmanager().registerPeriodicTask(
      dailyWallpaperTaskId,
      dailyWallpaperTaskName,
      initialDelay: delay,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// Cancel the background task
  static Future<void> cancelBackgroundTask() async {
    await Workmanager().cancelByUniqueName(dailyWallpaperTaskId);
  }

  /// Load saved schedule settings
  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'isAutoActive': prefs.getBool(prefKeyIsAutoActive) ?? true,
      'hour': prefs.getInt(prefKeyScheduledHour) ?? 6,
      'minute': prefs.getInt(prefKeyScheduledMinute) ?? 0,
      'customApiKey': prefs.getString(prefKeyCustomApiKey) ?? '',
    };
  }

  /// Save schedule settings
  static Future<void> saveSettings({
    required bool isAutoActive,
    required int hour,
    required int minute,
    String? customApiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKeyIsAutoActive, isAutoActive);
    await prefs.setInt(prefKeyScheduledHour, hour);
    await prefs.setInt(prefKeyScheduledMinute, minute);
    if (customApiKey != null) {
      await prefs.setString(prefKeyCustomApiKey, customApiKey);
    }
  }
}
