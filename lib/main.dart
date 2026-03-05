import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:quick_actions/quick_actions.dart';

import 'utils/notification_helper.dart';
import 'services/wallpaper_service.dart';
import 'screens/settings_screen.dart';
import 'screens/image_detail_screen.dart';

/// Custom cache manager with strict limits to prevent app bloating
class WallpaperCacheManager {
  static const key = 'unsplashWallpaperCache';
  static CacheManager instance = CacheManager(
    Config(key, stalePeriod: const Duration(days: 2), maxNrOfCacheObjects: 50),
  );
}

/// Task name for force update from shortcut
const String forceUpdateTaskName = 'force_update_wallpaper_task';
const String forceUpdateTaskId = 'force_update_wallpaper_id';

/// Callback dispatcher for WorkManager (must be top-level function)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case dailyWallpaperTaskName:
      case forceUpdateTaskName:
        // Both scheduled and force-update tasks use same logic
        return await WallpaperService.executeBackgroundTask();
      default:
        return Future.value(true);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize WorkManager
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // Initialize Notifications
  await NotificationHelper.initialize();

  // Load saved settings and schedule accordingly
  final settings = await ScheduleHelper.loadSettings();
  final isAutoActive = settings['isAutoActive'] ?? true;
  final hour = settings['hour'] ?? 6;
  final minute = settings['minute'] ?? 0;

  if (isAutoActive) {
    await ScheduleHelper.scheduleBackgroundTask(hour, minute);
  }

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
  // ── State ────────────────────────────────────────────────────────────────
  List<UnsplashImage> wallpapers = [];
  int currentPage = 1;
  bool _isLoading = true;
  bool isLoadingMore = false;
  bool _isProcessing = false;
  String? _error;

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fetchInitialImages();
    _initQuickActions();
  }

  // ── Quick Actions ────────────────────────────────────────────────────────
  void _initQuickActions() {
    const quickActions = QuickActions();

    // Register shortcut items
    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(
        type: 'action_change_wallpaper',
        localizedTitle: 'Change Wallpaper Now',
        icon: 'ic_launcher',
      ),
    ]);

    // Handle shortcut action - "Hit and Run" strategy
    quickActions.initialize((String shortcutType) {
      if (shortcutType == 'action_change_wallpaper') {
        _handleQuickActionChangeWallpaper();
      }
    });
  }

  Future<void> _handleQuickActionChangeWallpaper() async {
    // Register a one-off background task
    await Workmanager().registerOneOffTask(
      forceUpdateTaskId,
      forceUpdateTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
    );

    // Close the app immediately - "Hit and Run"
    SystemNavigator.pop();
  }

  // ── Data Fetching ────────────────────────────────────────────────────────

  /// Initial load (page 1, may serve from cache).
  Future<void> _fetchInitialImages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final images = await WallpaperService.fetchWallpapers(
        page: 1,
        count: 30,
      );
      setState(() {
        wallpapers = images;
        currentPage = 1;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Pull-to-refresh: reset to page 1, force a fresh network call.
  Future<void> _handleRefresh() async {
    setState(() {
      currentPage = 1;
      wallpapers = [];
      _error = null;
    });

    try {
      final images = await WallpaperService.fetchWallpapers(
        page: 1,
        count: 30,
        forceRefresh: true,
      );
      setState(() {
        wallpapers = images;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  /// Load More: fetch the next page and append results.
  Future<void> _handleLoadMore() async {
    if (isLoadingMore) return;

    setState(() {
      isLoadingMore = true;
    });

    try {
      currentPage++;
      final newImages = await WallpaperService.fetchWallpapers(
        page: currentPage,
        count: 30,
      );
      setState(() {
        wallpapers = [...wallpapers, ...newImages];
        isLoadingMore = false;
      });
    } catch (e) {
      // Roll back the page increment so a retry will request the same page.
      currentPage--;
      setState(() {
        isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load more: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void _handleImageTap(UnsplashImage image) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ImageDetailScreen(image: image)),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

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
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
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

    if (_error != null && wallpapers.isEmpty) {
      return Center(
        child: SingleChildScrollView(
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
                onPressed: _fetchInitialImages,
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
        // ── Header bar ──────────────────────────────────────────────────
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
                      '${wallpapers.length} Popular',
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

        // ── Gallery + Load More ──────────────────────────────────────────
        Expanded(
          child: RefreshIndicator(
            onRefresh: _handleRefresh,
            color: const Color(0xFF6366F1),
            backgroundColor: const Color(0xFF1A1A3E),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Grid of wallpaper cards
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.6,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildImageCard(wallpapers[index]),
                      childCount: wallpapers.length,
                    ),
                  ),
                ),

                // Load More footer
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 48,
                    ),
                    child: isLoadingMore
                        ? const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Color(0xFF6366F1),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _handleLoadMore,
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('Load More Wallpapers'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
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
                imageUrl: image.regularUrl,
                cacheManager: WallpaperCacheManager.instance,
                fit: BoxFit.cover,
                memCacheWidth: 500,
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
