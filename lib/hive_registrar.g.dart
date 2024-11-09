import 'package:hive_ce/hive.dart';
import 'package:fireproof_closet/src/cached_data.dart';

extension HiveRegistrar on HiveInterface {
  void registerAdapters() {
    registerAdapter(CachedDataAdapter());
  }
}
