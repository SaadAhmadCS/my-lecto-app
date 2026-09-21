import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Playback bar for a recording's audio chunks stored on this device
/// (ORG-012). Chunks play back to back with one seek bar across the whole
/// recording. Renders nothing if the audio isn't on this device.
class RecordingAudioPlayerBar extends StatefulWidget {
  final String recordingId;

  const RecordingAudioPlayerBar({super.key, required this.recordingId});

  @override
  State<RecordingAudioPlayerBar> createState() =>
      _RecordingAudioPlayerBarState();
}

class _RecordingAudioPlayerBarState extends State<RecordingAudioPlayerBar> {
  final AudioPlayer _player = AudioPlayer();

  /// Start offset of each chunk within the whole recording.
  List<Duration> _chunkOffsets = const [];
  Duration _total = Duration.zero;
  bool _ready = false;
  double? _dragValueMs;

  static final _chunkFilePattern = RegExp(r'^chunk_\d{3}\.m4a$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${docsDir.path}/recordings/${widget.recordingId}');
      if (!await dir.exists()) return;

      final files = await dir
          .list()
          .where(
            (e) =>
                e is File &&
                _chunkFilePattern.hasMatch(e.uri.pathSegments.last),
          )
          .cast<File>()
          .toList();
      if (files.isEmpty) return;
      files.sort(
        (a, b) => a.path.compareTo(b.path),
      ); // chunk_000, chunk_001, ...

      // Per-chunk durations, needed to map the seek bar across chunks
      final offsets = <Duration>[];
      var total = Duration.zero;
      for (final file in files) {
        final probe = AudioPlayer();
        try {
          offsets.add(total);
          total += await probe.setFilePath(file.path) ?? Duration.zero;
        } finally {
          await probe.dispose();
        }
      }

      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: [for (final file in files) AudioSource.file(file.path)],
        ),
      );

      if (!mounted) return;
      setState(() {
        _chunkOffsets = offsets;
        _total = total;
        _ready = total > Duration.zero;
      });
    } catch (e) {
      // Unplayable or missing audio — keep the bar hidden
      debugPrint('RecordingAudioPlayerBar: could not load audio: $e');
    }
  }

  Duration _globalPosition(Duration chunkPosition) {
    final index = _player.currentIndex ?? 0;
    if (index >= _chunkOffsets.length) return chunkPosition;
    return _chunkOffsets[index] + chunkPosition;
  }

  Future<void> _seek(Duration position) async {
    var index = 0;
    for (var i = 0; i < _chunkOffsets.length; i++) {
      if (_chunkOffsets[i] <= position) index = i;
    }
    await _player.seek(position - _chunkOffsets[index], index: index);
  }

  Future<void> _togglePlay(PlayerState state) async {
    if (state.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero, index: 0);
      await _player.play();
    } else if (state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  static String _format(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.base,
          AppSpacing.xs,
        ),
        decoration: const BoxDecoration(
          color: AppColors.darkSurface,
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
        ),
        child: Row(
          children: [
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snapshot) {
                final state = snapshot.data ?? _player.playerState;
                final isPlaying =
                    state.playing &&
                    state.processingState != ProcessingState.completed;
                return IconButton(
                  onPressed: () => _togglePlay(state),
                  tooltip: isPlaying ? 'Pause' : 'Play',
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: AppColors.primary,
                    size: 32,
                  ),
                );
              },
            ),
            Expanded(
              child: StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, snapshot) {
                  final position = _globalPosition(
                    snapshot.data ?? Duration.zero,
                  );
                  final totalMs = _total.inMilliseconds.toDouble();
                  final valueMs =
                      (_dragValueMs ?? position.inMilliseconds.toDouble())
                          .clamp(0.0, totalMs);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: valueMs,
                          max: totalMs,
                          activeColor: AppColors.primary,
                          inactiveColor: AppColors.darkBorder,
                          onChanged: (v) => setState(() => _dragValueMs = v),
                          onChangeEnd: (v) async {
                            await _seek(Duration(milliseconds: v.round()));
                            if (mounted) setState(() => _dragValueMs = null);
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _format(Duration(milliseconds: valueMs.round())),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.textTertiaryDark),
                          ),
                          Text(
                            _format(_total),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.textTertiaryDark),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
