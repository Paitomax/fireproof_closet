import 'package:firebase_storage/firebase_storage.dart';
import 'package:fireproof_closet/src/util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../fireproof_closet.dart';
import 'constants.dart';

part 'cached_data.g.dart';

/// Data saved in a format compatible with isar database
@HiveType(typeId: 169)
class CachedData {
  CachedData(this.storageRefFullPath, this.bytes, this.cacheCreated, this.cacheExpires);

  /// The full path of the [Reference] storage item
  @HiveField(0)
  final String storageRefFullPath;

  /// The bytes stored
  @HiveField(1)
  final Uint8List bytes;

  /// Cache created
  @HiveField(2)
  final DateTime cacheCreated;

  /// Cache expires
  @HiveField(3)
  final DateTime cacheExpires;

  @override
  String toString() {
    return "CachedData: fullPath: $storageRefFullPath, size: ${(bytes.lengthInBytes / 1000).toStringAsFixed(2)} kb, created: $cacheCreated, expires: $cacheExpires";
  }

  /// Get Bytes consumable by the FireproofImage ImageProvider from cache
  /// Returns null if they are not in the cache
  static Future<Uint8List?> getFromCache(String url) async {
    LazyBox<CachedData> box = Hive.lazyBox<CachedData>(kDatabaseName);

    final CachedData? cachedData = await box.get(url);

    if (cachedData == null) {
      return null;
    }

    // If we are past the expiration date
    DateTime now = DateTime.now();
    if (now.isAfter(cachedData.cacheExpires)) {
      return null;
    }

    // Return as Uint8List
    return cachedData.bytes;
  }

  /// Check if Cached
  static bool isCached(String url) {
    LazyBox<CachedData> box = Hive.lazyBox<CachedData>(kDatabaseName);

    bool cached = box.containsKey(url);

    return cached;
  }

  /// Remove cached image
  static Future<void> removeFromCache(String url) {
    LazyBox<CachedData> box = Hive.lazyBox<CachedData>(kDatabaseName);
    return box.delete(url);
  }

  /// Cache Now
  /// Caches an already downloaded Firebase Storage reference
  /// and its bytes for future use.
  static Future<void> saveToPersistentCache({
    required String url,
    required Uint8List bytes,
    Duration cacheDuration = kDefaultDuration,
  }) async {
    LazyBox<CachedData> box = Hive.lazyBox<CachedData>(kDatabaseName);

    // Create cacheCreated datetime
    DateTime now = DateTime.now();

    // Create an expiration from the duration
    DateTime expires = now.add(cacheDuration);

    // Construct the entire cache object
    CachedData cachedData = CachedData(url, bytes, now, expires);

    // Write the data
    await box.put(url, cachedData);

    return;
  }

  /// Download And Cache
  static Future<void> downloadAndCache({
    required BuildContext? context,
    required String url,
    required Duration cacheDuration,
    required bool breakCache,
  }) async {
    try {
      // breakCache == false and file is already cached, return early because there is nothing to do
      if (!breakCache && isCached(url)) {
        return;
      }

      final storageRef = getRefFromUrl(Uri.parse(url));

      // Download the image from Firebase Storage based on the reference
      final Uint8List? bytes = await storageRef.getData();

      if (bytes == null) {
        throw Exception("downloadAndCache() failed for ${storageRef.fullPath}.");
      }

      // Save it to locale persistent cache (overwrites existing data)
      saveToPersistentCache(url: url, bytes: bytes, cacheDuration: cacheDuration);

      // Create the image provider for [ImageCache] hot memory
      FireproofImageProvider imageProvider = FireproofImageProvider(url: url, breakCache: true);

      // Evict the provider from [ImageCache] hot memory
      await imageProvider.evict();

      // Load it into the [ImageCache] hot memory cache system
      if (context != null && context.mounted) {
        precacheImage(imageProvider, context);
      }

      // debugPrint(
      //     "CACHE STATUS: ${await imageProvider.obtainCacheStatus(configuration: ImageConfiguration.empty)}");

      return;
    } catch (e) {
      rethrow;
    }
  }

  /// Clear Cache
  /// Deletes all cached items from the cache
  static Future<void> clearCache() async {
    LazyBox<CachedData> box = Hive.lazyBox<CachedData>(kDatabaseName);
    await box.deleteAll(box.keys);

    // For each key clear from the hot [ImageCache]
    List<Future> evictFutures = box.keys.map((key) {
      // Any image provider, does not have to be "real"
      FireproofImageProvider imageProvider = FireproofImageProvider(url: key);
      return imageProvider.evict();
    }).toList();

    // Wait for the clearing to be done
    await Future.wait(evictFutures);

    imageCache.clear();
    imageCache.clearLiveImages();

    return;
  }

  /// Cache Status
  /// Details about the cache
  static Future<void> cacheStatus() async {
    LazyBox<CachedData> box = Hive.lazyBox<CachedData>(kDatabaseName);
    var keys = box.keys;

    debugPrint("Number of cached items in persistence: ${keys.length}");

    List<Future<CachedData?>> futures = keys.map((item) {
      return box.get(item);
    }).toList();

    List<CachedData?> items = await Future.wait<CachedData?>(futures);

    int totalCacheFileSize = 0;

    for (var item in items) {
      if (item != null) {
        totalCacheFileSize += item.bytes.lengthInBytes;
      }
    }

    debugPrint("Total persistent cache size ${(totalCacheFileSize / 1000 / 1000).toStringAsFixed(4)} MB");

    // For each key clear from the hot [ImageCache]
    List<Future<ImageCacheStatus?>> aliveFutures = box.keys.map((key) {
      FireproofImageProvider imageProvider = FireproofImageProvider(url: key);
      return imageProvider.obtainCacheStatus(configuration: ImageConfiguration.empty);
    }).toList();

    // Wait for the futures to be done
    List<ImageCacheStatus?> statuses = await Future.wait(aliveFutures);

    List<ImageCacheStatus?> alive = statuses.where((e) => e?.live == true).toList();

    debugPrint("Total items in ImageCache hot memory: ${alive.length}");
  }

  /// Print Cache Items
  /// Print all of the items currently in cache
  static void printCacheItems() async {
    LazyBox<CachedData> box = Hive.lazyBox<CachedData>(kDatabaseName);
    var keys = box.keys;

    List<Future<CachedData?>> futures = keys.map((item) {
      return box.get(item);
    }).toList();

    List<CachedData?> items = await Future.wait<CachedData?>(futures);

    int count = 0;

    debugPrint("=====================\nAll cached items:");
    for (var item in items) {
      if (item != null) {
        debugPrint("$count ${item.toString()}");
        count++;
      }
    }
    debugPrint("End of cached items.\n=====================");
  }
}
