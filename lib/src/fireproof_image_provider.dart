import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:fireproof_closet/src/constants.dart';
import 'package:fireproof_closet/src/util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'cached_data.dart';

/// Loads from cloud or cache a given Firebase Storage [Reference] as Uint8List
///
/// This is essentially a different network downloading implementation of [FireproofImageProvider]
/// tailored to Firebase Storage
@immutable
class FireproofImageProvider extends ImageProvider<FireproofImageProvider> {
  /// Creates an object that decodes a [Uint8List] buffer as an image.
  ///
  /// The arguments must not be null.
  const FireproofImageProvider({
    required this.url,
    this.cacheDuration = kDefaultDuration,
    this.cache = true,
    this.breakCache = false,
    this.scale = 1.0,
    this.maxSize = 104857600,
  });

  /// Firebase Storage [Reference]
  final String url;

  /// Max size of getData() item before an exception is thrown (defaults to 104.9MB)
  final int maxSize;

  /// Cache Duration (will fetch from the Firebase Storage if duration is exceeded).
  /// Defaults to 5 minutes.
  final Duration cacheDuration;

  /// Whether to cache the image when it is loaded
  final bool cache;

  /// Break Cache to force a fresh download
  final bool breakCache;

  /// The scale to place in the [ImageInfo] object of the image.
  ///
  /// See also:
  ///
  ///  * [ImageInfo.scale], which gives more information on how this scale is
  ///    applied.
  final double scale;

  @override
  Future<FireproofImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<FireproofImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadBuffer(
      FireproofImageProvider key, DecoderBufferCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: "FireproofImage($url)",
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<FireproofImageProvider>('Image provider', this),
        DiagnosticsProperty<FireproofImageProvider>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    FireproofImageProvider key,
    DecoderBufferCallback decode,
  ) async {
    try {
      assert(key == this);

      // Evict from hot cache if we're breaking cache
      if (breakCache) {
        evict();
      }

      final storageRef = getRefFromUrl(Uri.parse(url));

      // First attempt to retrieve the image from cache (unless breakCache)
      final Uint8List? cachedBytes =
          (breakCache) ? null : await CachedData.getFromCache(url);

      // If not in cache or expired, fetch the data from Firebase Storage
      final Uint8List? bytes = cachedBytes ?? await storageRef.getData(maxSize);

      if (bytes == null) {
        throw Exception(
            'No data in cache and FireproofImage getData() returned null.');
      }

      if (bytes.lengthInBytes == 0) {
        throw Exception('FireproofImage is an empty file. 0 Bytes.');
      }

      // Cache the data if cachedBytes was null and cache == true
      if (cachedBytes == null && cache) {
        CachedData.saveToPersistentCache(
            url: url, bytes: bytes, cacheDuration: cacheDuration);
      }

      final ui.ImmutableBuffer buffer =
          await ui.ImmutableBuffer.fromUint8List(bytes);

      return decode(buffer);
    } catch (e) {
      // Depending on where the exception was thrown, the image cache may not
      // have had a chance to track the key in the cache at all.
      // Schedule a microtask to give the cache a chance to add the key.
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    }
  }

  // Required to utilize ImageProvider's hot memory caching system
  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }

    return other is FireproofImageProvider &&
        other.url == url &&
        other.scale == scale;
  }

  // Required to utilize ImageProvider's hot memory caching system
  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'FireproofImage')}("$url", scale: $scale)';
}
