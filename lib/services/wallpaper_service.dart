import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

/// Unsplash API Configuration
const String unsplashAccessKey = '8j6bFdAOUOn4PI-ABF169gGccTlH_p-Uu4SIHUt7tfc';
const String _unsplashBaseUrl = 'https://api.unsplash.com';

/// Cache Configuration
const String _cacheKeyWallpapers = 'cached_wallpapers_json';
const String _cacheKeyTimestamp = 'cached_wallpapers_timestamp';
const int _cacheDurationMinutes = 60; // 60 minutes cache validity

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

  /// Convert to JSON for caching
  Map<String, dynamic> toJson() => {
    'id': id,
    'urls': {'regular': regularUrl, 'full': fullUrl, 'thumb': thumbUrl},
    'description': description,
    'user': {'name': photographerName},
    'width': width,
    'height': height,
  };

  /// Get display title (description or photographer credit)
  String get displayTitle => description ?? 'Photo by $photographerName';
}

/// Service class for handling wallpaper operations with Unsplash API
class WallpaperService {
  /// Common headers for Unsplash API
  static Map<String, String> get _headers => {
    'Authorization': 'Client-ID $unsplashAccessKey',
    'Accept-Version': 'v1',
  };

  /// Check if cache is valid (less than 60 minutes old)
  static Future<bool> _isCacheValid() async {
    final prefs = await SharedPreferences.getInstance();
    final timestampStr = prefs.getString(_cacheKeyTimestamp);

    if (timestampStr == null) return false;

    final cachedTime = DateTime.tryParse(timestampStr);
    if (cachedTime == null) return false;

    final difference = DateTime.now().difference(cachedTime);
    return difference.inMinutes < _cacheDurationMinutes;
  }

  /// Get cached wallpapers from SharedPreferences
  static Future<List<UnsplashImage>?> _getCachedWallpapers() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(_cacheKeyWallpapers);

    if (cachedJson == null) return null;

    try {
      final List<dynamic> data = json.decode(cachedJson);
      return data.map((json) => UnsplashImage.fromJson(json)).toList();
    } catch (e) {
      // Invalid cache, return null
      return null;
    }
  }

  /// Save wallpapers to cache
  static Future<void> _cacheWallpapers(String jsonResponse) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKeyWallpapers, jsonResponse);
    await prefs.setString(_cacheKeyTimestamp, DateTime.now().toIso8601String());
  }

  /// Fetches trending portrait wallpapers for the gallery
  /// [count] - Number of images to fetch (default 30)
  /// [forceRefresh] - If true, bypass cache and fetch fresh data
  static Future<List<UnsplashImage>> fetchTrendingWallpapers({
    int count = 30,
    bool forceRefresh = false,
  }) async {
    // Step 1: Check cache (unless force refresh)
    if (!forceRefresh) {
      final isValid = await _isCacheValid();
      if (isValid) {
        final cached = await _getCachedWallpapers();
        if (cached != null && cached.isNotEmpty) {
          // Cache hit - return cached data
          return cached;
        }
      }
    }

    // Step 2: Cache miss or force refresh - fetch from API
    try {
      final uri = Uri.parse(
        '$_unsplashBaseUrl/photos?per_page=$count&order_by=popular&orientation=portrait',
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        // Save to cache
        await _cacheWallpapers(response.body);

        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => UnsplashImage.fromJson(json)).toList();
      } else {
        throw Exception(
          'Failed to fetch wallpapers: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      // On error, try to return cached data as fallback
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
      final uri = Uri.parse(
        '$_unsplashBaseUrl/photos/random?orientation=portrait&query=nature,architecture,abstract&count=1',
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        // Response is an array when count=1
        if (data is List && data.isNotEmpty) {
          return UnsplashImage.fromJson(data.first);
        } else if (data is Map<String, dynamic>) {
          return UnsplashImage.fromJson(data);
        }
        throw Exception('Invalid response format');
      } else {
        throw Exception(
          'Failed to fetch random wallpaper: ${response.statusCode}',
        );
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
        throw Exception('Failed to download image: ${response.statusCode}');
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
      final image = await fetchRandomWallpaper();
      final result = await setWallpaperFromUrl(
        image.fullUrl,
        location: WallpaperLocation.both,
      );
      return result;
    } catch (e) {
      print('Background task failed: $e');
      return false;
    }
  }
}
