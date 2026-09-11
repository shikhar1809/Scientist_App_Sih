import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
import '../models/dispatch.dart';
import 'local_db.dart';

// SyncService flushes the local pending queue to Firestore: at startup,
// straight after a report is saved, and whenever the connection comes back.
// Uploads media first, then writes the Firestore document with the resulting
// download URLs.
//
// The portal's rules (firestore.rules, storage.rules) decide what it accepts:
// the report's authorUid must be the signed-in user, at most five photos, and
// notes of at most 2,000 characters. So:
//   - the author is stamped at sync time with whoever is signed in NOW — an
//     anonymous session can change between filing and syncing (a reinstall,
//     an offline first launch), and a report stamped with the old id would be
//     refused on every attempt, forever;
//   - at most five photos are sent;
//   - a refusal is recorded against the report, in words, instead of being
//     swallowed — "queued" should never secretly mean "rejected".

class SyncService {
  SyncService({
    LocalDb? db,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _db = db ?? LocalDb(),
        _firestore = firestore,
        _storage = storage;

  /// The one the app uses; tests construct their own.
  static final SyncService instance = SyncService();

  /// The portal accepts at most this many photographs per report.
  static const maxPhotos = 5;

  /// A connection that drops mid-upload must not leave a write waiting for
  /// ever — that would hold the sync "busy" and nothing would send again.
  static const _uploadTimeout = Duration(minutes: 3);
  static const _writeTimeout = Duration(seconds: 45);

  final LocalDb _db;
  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;
  bool _syncing = false;

  /// Bumped whenever a report reaches the portal, so screens can reload.
  final ValueNotifier<int> syncedCount = ValueNotifier(0);

  /// Why a report has not reached the portal yet, by report id, in words.
  final ValueNotifier<Map<String, String>> errors = ValueNotifier(const {});

  // Call once from main(). Syncs straight away, then on every reconnection.
  void startWatching() {
    Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) flush();
    });
    flush();
  }

  // Flush all pending local dispatches to Firestore.
  Future<void> flush() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final user = await _signedIn();
      if (user == null) return; // offline, or Firebase unreachable — try again later
      final pending = await _db.getPending();
      for (final d in pending) {
        await _uploadDispatch(d, user.uid);
      }
    } finally {
      _syncing = false;
    }
  }

  /// Firebase, initialised and signed in — or null when that is not possible
  /// right now. An app that started offline never got this far in main().
  Future<User?> _signedIn() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
      final auth = FirebaseAuth.instance;
      return auth.currentUser ?? (await auth.signInAnonymously()).user;
    } catch (e) {
      debugPrint('sync: not signed in yet — $e');
      return null;
    }
  }

  Future<void> _uploadDispatch(Dispatch d, String uid) async {
    final firestore = _firestore ?? FirebaseFirestore.instance;
    try {
      final base = 'dispatches/$uid/${d.id}';

      // Upload voice memo
      String? voiceUrl;
      if (d.voicePath != null) {
        voiceUrl = await _uploadFile('$base/voice.m4a', d.voicePath!);
      }

      // Upload photos — the portal refuses a report with more than five.
      final photos = d.imagePaths.take(maxPhotos).toList();
      final imageUrls = <String>[];
      for (var i = 0; i < photos.length; i++) {
        final ext = photos[i].split('.').last;
        final url = await _uploadFile('$base/photo_$i.$ext', photos[i]);
        imageUrls.add(url);
      }

      // Upload CSV
      String? csvUrl;
      if (d.csvPath != null) {
        final name = d.csvPath!.split(Platform.pathSeparator).last;
        csvUrl = await _uploadFile('$base/$name', d.csvPath!);
      }

      // Upload documents
      final docUrls = <Map<String, String>>[];
      for (final doc in d.docPaths) {
        final url = await _uploadFile('$base/docs/${doc['name']}', doc['path']!);
        docUrls.add({'name': doc['name']!, 'url': url});
      }

      // Write Firestore document
      await firestore.collection('dispatches').doc(d.id).set({
        'authorUid': uid,
        'authorName': d.authorName,
        'observedAt': d.observedAt.millisecondsSinceEpoch,
        'station': d.station,
        'lat': d.lat,
        'lon': d.lon,
        'elevationM': d.elevationM,
        'positionSource': d.positionSource,
        'activity': d.activity,
        'priority': d.priority.name,
        'weather': d.weather.toMap(),
        'measurements': d.measurements,
        'notes': d.notes.length > 2000 ? d.notes.substring(0, 2000) : d.notes,
        'teamMembers': d.teamMembers,
        'sampleIds': d.sampleIds,
        'safetyFlag': d.safetyFlag,
        'voiceUrl': voiceUrl,
        'imageUrls': imageUrls,
        'csvUrl': csvUrl,
        'docUrls': docUrls,
        'caption': '',
        'status': 'raw',
        'publisherName': null,
        'adminNotes': null,
        'createdAt': d.createdAt.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'createdAtServer': FieldValue.serverTimestamp(),
      }).timeout(_writeTimeout);

      await _db.markSynced(d.id);
      _setError(d.id, null);
      syncedCount.value++;
    } catch (e) {
      // Left in the queue to retry — but with the reason on record.
      debugPrint('sync: ${d.id} not sent — $e');
      _setError(d.id, _describe(e));
    }
  }

  void _setError(String id, String? message) {
    final next = Map<String, String>.from(errors.value);
    if (message == null) {
      next.remove(id);
    } else {
      next[id] = message;
    }
    errors.value = next;
  }

  static String _describe(Object e) {
    if (e is FirebaseException) {
      if (e.code == 'permission-denied' || e.code == 'unauthorized') {
        return 'The portal refused this report (${e.code}). It will keep retrying; if it persists, contact the portal admin.';
      }
      if (e.code == 'unavailable' || e.code == 'network-request-failed') {
        return 'No connection to the portal — will retry when online.';
      }
      return 'Sync failed (${e.code}): ${e.message ?? ''}'.trim();
    }
    if (e is TimeoutException) return 'The connection dropped during the upload — will retry.';
    if (e is FileSystemException) return 'A file attached to this report could not be read: ${e.path ?? ''}';
    return 'Sync failed: $e';
  }

  Future<String> _uploadFile(String storagePath, String localPath) async {
    final ref = (_storage ?? FirebaseStorage.instance).ref(storagePath);
    await ref.putFile(File(localPath)).timeout(_uploadTimeout);
    return ref.getDownloadURL().timeout(_writeTimeout);
  }
}
