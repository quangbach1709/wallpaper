import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_cropper/image_cropper.dart';

import 'services/wallpaper_service.dart';

// WorkManager task name
const String dailyWallpaperTask = 'dailyWallpaperTask';

/// Custom cache manager with strict limits to prevent app bloating
class WallpaperCacheManager {
  static const key = 'unsplashWallpaperCache';
  static CacheManager instance = CacheManager(
    Config(key, stalePeriod: const Duration(days: 2), maxNrOfCacheObjects: 50),
  );
}

/// Callback dispatcher for WorkManager (must be top-level function)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case dailyWallpaperTask:
        // Background task sets wallpaper for BOTH screens using Unsplash
        return await WallpaperService.executeBackgroundTask();
      default:
        return Future.value(true);
    }
  });
}

/// Calculate initial delay to run task at 6:00 AM
Duration calculateInitialDelay() {
  final now = DateTime.now();
  var scheduledTime = DateTime(now.year, now.month, now.day, 6, 0, 0);

  // If 6 AM has already passed today, schedule for tomorrow
  if (now.isAfter(scheduledTime)) {
    scheduledTime = scheduledTime.add(const Duration(days: 1));
  }

  return scheduledTime.difference(now);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize WorkManager
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // Register periodic task for daily wallpaper change at 6 AM
  await Workmanager().registerPeriodicTask(
    'dailyWallpaper',
    dailyWallpaperTask,
    initialDelay: calculateInitialDelay(),
    frequency: const Duration(hours: 24),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  runApp(const WallpaperApp());
}

class WallpaperApp extends StatelessWidget {
  const WallpaperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wallpaper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F23),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const WallpaperGalleryPage(),
    );
  }
}

class WallpaperGalleryPage extends StatefulWidget {
  const WallpaperGalleryPage({super.key});

  @override
  State<WallpaperGalleryPage> createState() => _WallpaperGalleryPageState();
}

class _WallpaperGalleryPageState extends State<WallpaperGalleryPage> {
  List<UnsplashImage> _images = [];
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchImages();
  }

  Future<void> _fetchImages({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final images = await WallpaperService.fetchTrendingWallpapers(
        count: 30,
        forceRefresh: forceRefresh,
      );
      setState(() {
        _images = images;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Force refresh for pull-to-refresh
  Future<void> _onRefresh() async {
    await _fetchImages(forceRefresh: true);
  }

  /// Handle image tap: Download -> Crop -> Show Options
  Future<void> _handleImageTap(UnsplashImage image) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    String? originalFilePath;
    String? croppedFilePath;

    try {
      // Step 1: Download image to temp (use regular for faster download)
      _showLoadingDialog('Downloading image...');
      originalFilePath = await WallpaperService.downloadImage(image.regularUrl);
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Step 2: Get device screen ratio for cropper
      final screenSize = MediaQuery.of(context).size;
      final aspectRatioX = screenSize.width;
      final aspectRatioY = screenSize.height;

      // Step 3: Open image cropper
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: originalFilePath,
        aspectRatio: CropAspectRatio(
          ratioX: aspectRatioX,
          ratioY: aspectRatioY,
        ),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Adjust Wallpaper',
            toolbarColor: const Color(0xFF1A1A3E),
            toolbarWidgetColor: Colors.white,
            backgroundColor: const Color(0xFF0F0F23),
            activeControlsWidgetColor: const Color(0xFF6366F1),
            cropFrameColor: const Color(0xFF6366F1),
            cropGridColor: Colors.white30,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
        ],
      );

      if (!mounted) return;

      // User cancelled cropping
      if (croppedFile == null) {
        await WallpaperService.deleteFile(originalFilePath);
        setState(() => _isProcessing = false);
        return;
      }

      croppedFilePath = croppedFile.path;

      // Step 4: Show wallpaper location options
      final selectedLocation = await _showWallpaperOptionsSheet();

      if (selectedLocation == null) {
        // User cancelled - cleanup files
        await WallpaperService.deleteFiles([originalFilePath, croppedFilePath]);
        setState(() => _isProcessing = false);
        return;
      }

      // Step 5: Set wallpaper with selected location
      _showLoadingDialog('Setting wallpaper...');
      final success = await WallpaperService.setWallpaperFromFile(
        croppedFilePath,
        location: selectedLocation,
        filesToCleanup: [originalFilePath, croppedFilePath],
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Show result
      _showResultSnackBar(success);
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        _showErrorSnackBar(e.toString());
      }
      // Cleanup on error
      if (originalFilePath != null) {
        await WallpaperService.deleteFile(originalFilePath);
      }
      if (croppedFilePath != null) {
        await WallpaperService.deleteFile(croppedFilePath);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A3E),
          content: Row(
            children: [
              const CircularProgressIndicator(color: Color(0xFF6366F1)),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<WallpaperLocation?> _showWallpaperOptionsSheet() async {
    return showModalBottomSheet<WallpaperLocation>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A3E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Set Wallpaper',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose where to apply this wallpaper',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            // Home Screen Button
            _buildOptionButton(
              icon: Icons.home_rounded,
              label: 'Set Home Screen',
              onTap: () => Navigator.pop(context, WallpaperLocation.homeScreen),
            ),
            const SizedBox(height: 12),
            // Lock Screen Button
            _buildOptionButton(
              icon: Icons.lock_rounded,
              label: 'Set Lock Screen',
              onTap: () => Navigator.pop(context, WallpaperLocation.lockScreen),
            ),
            const SizedBox(height: 12),
            // Both Screens Button
            _buildOptionButton(
              icon: Icons.phone_android_rounded,
              label: 'Set Both',
              isPrimary: true,
              onTap: () => Navigator.pop(context, WallpaperLocation.both),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? const Color(0xFF6366F1)
              : const Color(0xFF2D2D5A),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: isPrimary ? 4 : 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _showResultSnackBar(bool success) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '✓ Wallpaper set successfully!'
                : '✗ Failed to set wallpaper',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }

  void _showErrorSnackBar(String error) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Trending Wallpapers',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isProcessing ? null : _fetchImages,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0F23), Color(0xFF1A1A3E), Color(0xFF0F0F23)],
          ),
        ),
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 3),
            SizedBox(height: 16),
            Text(
              'Loading trending wallpapers...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load wallpapers',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchImages,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.trending_up,
                      size: 16,
                      color: Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_images.length} Popular',
                      style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                'Pull down to refresh',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: const Color(0xFF6366F1),
            backgroundColor: const Color(0xFF1A1A3E),
            child: GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.6, // Portrait aspect ratio for tall images
              ),
              itemCount: _images.length,
              itemBuilder: (context, index) {
                return _buildImageCard(_images[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageCard(UnsplashImage image) {
    return GestureDetector(
      onTap: () => _handleImageTap(image),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: image.thumbUrl,
                cacheManager: WallpaperCacheManager.instance,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[900],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[900],
                  child: const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 40,
                  ),
                ),
              ),
              // Gradient overlay for text readability
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    image.photographerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              // Processing overlay
              if (_isProcessing) Container(color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }
}
