import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

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

  /// Sets the home screen wallpaper from a file path
  static Future<bool> setWallpaper(String filePath) async {
    try {
      final wallpaperManager = WallpaperManagerFlutter();
      final result = await wallpaperManager.setWallpaper(
        File(filePath),
        WallpaperManagerFlutter.homeScreen,
      );
      return result;
    } catch (e) {
      throw Exception('Error setting wallpaper: $e');
    }
  }

  /// Complete flow: Download -> Set Wallpaper -> Delete temp file
  /// This is the main method used by both background tasks and manual selection
  static Future<bool> setWallpaperFromUrl(String imageUrl) async {
    String? filePath;

    try {
      // Step 1: Download image to temp directory
      filePath = await downloadImage(imageUrl);

      // Step 2: Set as wallpaper
      final result = await setWallpaper(filePath);

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

  /// Background task entry point for WorkManager
  /// Fetches today's Bing image and sets it as wallpaper
  static Future<bool> executeBackgroundTask() async {
    try {
      // Fetch the latest Bing image (just 1)
      final images = await fetchBingImages(count: 1);

      if (images.isEmpty) {
        throw Exception('No images returned from Bing API');
      }

      // Set the wallpaper using the complete flow
      final result = await setWallpaperFromUrl(images.first.url);

      return result;
    } catch (e) {
      // ignore: avoid_print
      print('Background task failed: $e');
      return false;
    }
  }
}
