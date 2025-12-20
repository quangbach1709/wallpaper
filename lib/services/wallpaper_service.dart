import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

/// Enum for wallpaper location options
enum WallpaperLocation { homeScreen, lockScreen, both }

/// Model class representing a Bing image
class BingImage {
  final String url;
  final String title;
  final String copyright;
  final String startDate;

  BingImage({
    required this.url,
    required this.title,
    required this.copyright,
    required this.startDate,
  });

  factory BingImage.fromJson(Map<String, dynamic> json) {
    // Construct full URL from the relative path
    final String urlPath = json['url'] ?? '';
    final String fullUrl = 'https://www.bing.com$urlPath';

    return BingImage(
      url: fullUrl,
      title: json['title'] ?? '',
      copyright: json['copyright'] ?? '',
      startDate: json['startdate'] ?? '',
    );
  }
}

/// Service class for handling wallpaper operations
class WallpaperService {
  static const String _bingApiBaseUrl =
      'https://www.bing.com/HPImageArchive.aspx';

  /// Fetches Bing images from the API
  /// [count] - Number of images to fetch (1-8)
  static Future<List<BingImage>> fetchBingImages({int count = 1}) async {
    try {
      final uri = Uri.parse(
        '$_bingApiBaseUrl?format=js&idx=0&n=$count&mkt=en-US',
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> images = data['images'] ?? [];

        return images
            .map((imageJson) => BingImage.fromJson(imageJson))
            .toList();
      } else {
        throw Exception('Failed to fetch Bing images: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching Bing images: $e');
    }
  }

  /// Downloads an image to the temporary directory
  /// Returns the file path of the downloaded image
  static Future<String> downloadImage(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName =
            'bing_wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
      // Silently fail - cleanup is best effort
      // ignore: avoid_print
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
  /// [location] - Where to set the wallpaper (home, lock, or both)
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
          // Set for both screens
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
  /// Used for background tasks (sets BOTH screens)
  static Future<bool> setWallpaperFromUrl(
    String imageUrl, {
    WallpaperLocation location = WallpaperLocation.both,
  }) async {
    String? filePath;

    try {
      // Step 1: Download image to temp directory
      filePath = await downloadImage(imageUrl);

      // Step 2: Set as wallpaper
      final result = await setWallpaper(filePath, location: location);

      return result;
    } catch (e) {
      rethrow;
    } finally {
      // Step 3: ALWAYS delete the temp file (crucial for storage management)
      if (filePath != null) {
        await deleteFile(filePath);
      }
    }
  }

  /// Sets wallpaper from a local file path with cleanup
  /// Used for manual selection with cropped image
  static Future<bool> setWallpaperFromFile(
    String filePath, {
    required WallpaperLocation location,
    List<String> filesToCleanup = const [],
  }) async {
    try {
      // Set as wallpaper
      final result = await setWallpaper(filePath, location: location);
      return result;
    } catch (e) {
      rethrow;
    } finally {
      // ALWAYS cleanup all temp files
      await deleteFiles(filesToCleanup);
    }
  }

  /// Background task entry point for WorkManager
  /// Fetches today's Bing image and sets it as wallpaper for BOTH screens
  static Future<bool> executeBackgroundTask() async {
    try {
      // Fetch the latest Bing image (just 1)
      final images = await fetchBingImages(count: 1);

      if (images.isEmpty) {
        throw Exception('No images returned from Bing API');
      }

      // Set the wallpaper for BOTH home and lock screens
      final result = await setWallpaperFromUrl(
        images.first.url,
        location: WallpaperLocation.both,
      );

      return result;
    } catch (e) {
      // ignore: avoid_print
      print('Background task failed: $e');
      return false;
    }
  }
}
