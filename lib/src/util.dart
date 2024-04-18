import 'package:firebase_storage/firebase_storage.dart';

Uri getUrlFromRef(Reference ref) {
  final link = "gs://${ref.bucket}/${ref.fullPath}";
  return Uri.parse(link);
}

FirebaseStorage getStorageFromUrl(Uri uri) {
  return FirebaseStorage.instanceFor(bucket: getBucketFromUrl(uri));
}

String getBucketFromUrl(Uri url) => '${url.scheme}://${url.authority}';

Reference getRefFromUrl(Uri url) {
  return getStorageFromUrl(url).ref(url.path);
}
