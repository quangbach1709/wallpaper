import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'services/wallpaper_service.dart';

// WorkManager task name
const String dailyWallpaperTask = 'dailyWallpaperTask';

/// Custom cache manager with strict limits to prevent app bloating
class BingImageCacheManager {
  static const key = 'bingImageCache';
  static CacheManager instance = CacheManager(
    Config(key, stalePeriod: const Duration(days: 2), maxNrOfCacheObjects: 10),
  );
}

/// Callback dispatcher for WorkManager (must be top-level function)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case dailyWallpaperTask:
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

  runApp(const BingWallpaperApp());
}

class BingWallpaperApp extends StatelessWidget {
  const BingWallpaperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bing Wallpaper',
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
  List<BingImage> _images = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchImages();
  }

  Future<void> _fetchImages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final images = await WallpaperService.fetchBingImages(count: 8);
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

  void _showImagePreview(BingImage image) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ImagePreviewSheet(image: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Bing Wallpapers',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchImages,
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
              'Loading beautiful images...',
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
                'Failed to load images',
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            'Recent ${_images.length} days',
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.7,
            ),
            itemCount: _images.length,
            itemBuilder: (context, index) {
              return _buildImageCard(_images[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildImageCard(BingImage image) {
    return GestureDetector(
      onTap: () => _showImagePreview(image),
      child: Hero(
        tag: image.url,
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
                  imageUrl: image.url,
                  cacheManager: BingImageCacheManager.instance,
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
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      image.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for image preview and wallpaper setting
class ImagePreviewSheet extends StatefulWidget {
  final BingImage image;

  const ImagePreviewSheet({super.key, required this.image});

  @override
  State<ImagePreviewSheet> createState() => _ImagePreviewSheetState();
}

class _ImagePreviewSheetState extends State<ImagePreviewSheet> {
  bool _isSettingWallpaper = false;

  Future<void> _setWallpaper() async {
    setState(() => _isSettingWallpaper = true);

    try {
      final success = await WallpaperService.setWallpaperFromUrl(
        widget.image.url,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '✓ Wallpaper set successfully!'
                  : '✗ Failed to set wallpaper',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSettingWallpaper = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A3E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Image preview
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Hero(
                    tag: widget.image.url,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: CachedNetworkImage(
                        imageUrl: widget.image.url,
                        cacheManager: BingImageCacheManager.instance,
                        fit: BoxFit.contain,
                        placeholder: (context, url) =>
                            const Center(child: CircularProgressIndicator()),
                        errorWidget: (context, url, error) =>
                            const Center(child: Icon(Icons.error, size: 48)),
                      ),
                    ),
                  ),
                ),
              ),
              // Image info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Text(
                      widget.image.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.image.copyright,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              // Set wallpaper button
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSettingWallpaper ? null : _setWallpaper,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    child: _isSettingWallpaper
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wallpaper, size: 24),
                              SizedBox(width: 12),
                              Text(
                                'Set as Wallpaper',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
