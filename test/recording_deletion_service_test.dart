import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_lecto/features/recording/data/local/recording_dao.dart';
import 'package:my_lecto/features/recording/data/services/recording_deletion_service.dart';

/// In-memory stand-in for the recordings/photos tables.
class _FakeDao extends RecordingDao {
  final List<String> deleted = [];
  final Map<String, List<Map<String, dynamic>>> photos = {};

  @override
  Future<void> deleteRecording(String id) async => deleted.add(id);

  @override
  Future<List<Map<String, dynamic>>> getPhotos(String recordingId) async =>
      photos[recordingId] ?? [];
}

void main() {
  late Directory root;
  late _FakeDao dao;
  late RecordingDeletionService deleter;

  Directory dirFor(String id) => Directory('${root.path}/$id');

  Future<File> writeChunk(String id, int seq) async {
    final file = File('${dirFor(id).path}/chunk_00$seq.m4a');
    await file.create(recursive: true);
    await file.writeAsString('audio');
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lecto_delete_test');
    dao = _FakeDao();
    deleter = RecordingDeletionService(
      dao: dao,
      recordingDir: (id) async => dirFor(id),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('removes the rows and the audio', () async {
    // The audio is the only copy there is, so deleting has to take it too.
    final chunk = await writeChunk('rec-1', 0);

    await deleter.delete('rec-1');

    expect(dao.deleted, ['rec-1']);
    expect(await chunk.exists(), isFalse);
    expect(await dirFor('rec-1').exists(), isFalse);
  });

  test('deletes captured photos too', () async {
    final photo = File('${root.path}/photo.jpg');
    await photo.create(recursive: true);
    await photo.writeAsString('image');
    dao.photos['rec-1'] = [
      {'file_path': photo.path},
    ];

    await deleter.delete('rec-1');

    expect(await photo.exists(), isFalse);
  });

  test('a recording whose audio is already gone still deletes', () async {
    // Nothing on disk — the rows must still go, or the entry is undeletable.
    await deleter.delete('rec-1');

    expect(dao.deleted, ['rec-1']);
  });

  test('leaves other recordings alone', () async {
    final mine = await writeChunk('rec-1', 0);
    final theirs = await writeChunk('rec-2', 0);

    await deleter.delete('rec-1');

    expect(await mine.exists(), isFalse);
    expect(await theirs.exists(), isTrue);
  });
}
