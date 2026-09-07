import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/api/api_config.dart';
import '../core/api/api_endpoints.dart';
import '../services/session_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Plays one call's recording.
///
/// The audio endpoint is org- AND telecaller-scoped on the backend (a
/// telecaller can only fetch audio for calls on their own leads), so there is
/// nothing to gate here beyond attaching the bearer token — which is exactly
/// why this uses just_audio: it is the player whose [AudioSource] accepts
/// request headers. The file is STREAMED, not downloaded first, so a long call
/// starts playing without waiting for the whole recording.
///
/// Errors are deliberately split rather than collapsed into one "couldn't
/// play" message: a call that was never recorded is a different situation from
/// a server that can't be reached, and only one of them is worth a retry.
class CallRecordingPlayer extends ConsumerStatefulWidget {
  const CallRecordingPlayer({
    super.key,
    required this.callId,
    this.compact = false,
  });

  final String callId;

  /// Tighter layout for embedding inside a lead-detail card, as opposed to the
  /// full-width bar on the call-detail screen.
  final bool compact;

  @override
  ConsumerState<CallRecordingPlayer> createState() =>
      _CallRecordingPlayerState();
}

class _CallRecordingPlayerState extends ConsumerState<CallRecordingPlayer> {
  final AudioPlayer _player = AudioPlayer();
  String? _error;
  bool _retryable = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CallRecordingPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The host screen re-renders in place when the lead changes, so without
    // this the player would keep the PREVIOUS lead's recording loaded and
    // happily play it under the new lead's header.
    if (oldWidget.callId != widget.callId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _retryable = false;
    });
    final token = ref.read(sessionProvider).token;
    if (token == null) {
      // A missing token here means the session went away mid-screen; the
      // global 401 handler owns the logout, this just stops pretending.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign in again to play this recording.';
        });
      }
      return;
    }
    try {
      await _player.setAudioSource(
        AudioSource.uri(
          ApiConfig.uri(ApiEndpoints.callAudio(widget.callId)),
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      if (mounted) setState(() => _loading = false);
    } on PlayerException catch (e) {
      // PlayerException carries the HTTP status for a network source, which
      // is what separates "never recorded" from "server had a problem".
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.code == 404) {
          _error = 'No recording was saved for this call.';
          _retryable = false;
        } else if (e.code == 401 || e.code == 403) {
          _error = "You don't have access to this recording.";
          _retryable = false;
        } else {
          _error = "The server couldn't return this recording.";
          _retryable = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't reach the server to load this recording.";
        _retryable = true;
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: AppColors.schooner),
            SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, color: AppColors.schooner),
              ),
            ),
            if (_retryable)
              TextButton(
                onPressed: _load,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      );
    }

    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        final processing = snapshot.data?.processingState;
        final buffering =
            processing == ProcessingState.loading ||
            processing == ProcessingState.buffering;

        return Row(
          children: [
            _PlayButton(
              playing: playing,
              busy: _loading || buffering,
              compact: widget.compact,
              onTap: () {
                if (_loading) return;
                if (playing) {
                  _player.pause();
                } else {
                  // Restart from the top once it has run to the end, instead
                  // of a dead button sitting at the final frame.
                  if (processing == ProcessingState.completed) {
                    _player.seek(Duration.zero);
                  }
                  _player.play();
                }
              },
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, posSnap) {
                  final total = _player.duration ?? Duration.zero;
                  final pos = posSnap.data ?? Duration.zero;
                  final max = total.inMilliseconds.toDouble();
                  final value = pos.inMilliseconds
                      .clamp(0, total.inMilliseconds)
                      .toDouble();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: max > 0 ? value : 0,
                          max: max > 0 ? max : 1,
                          onChanged: max > 0
                              ? (v) => _player.seek(
                                  Duration(milliseconds: v.round()),
                                )
                              : null,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fmt(pos),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.schooner,
                              ),
                            ),
                            Text(
                              total > Duration.zero
                                  ? _fmt(total)
                                  : (_loading ? 'Loading…' : '0:00'),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.schooner,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.busy,
    required this.compact,
    required this.onTap,
  });

  final bool playing;
  final bool busy;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 38.0 : 44.0;
    return Semantics(
      button: true,
      label: playing ? 'Pause call recording' : 'Play call recording',
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(size),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: busy ? AppColors.merlin.withValues(alpha: 0.4) : AppColors.merlin,
            shape: BoxShape.circle,
          ),
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.white),
                  ),
                )
              : Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  color: AppColors.white,
                  size: compact ? 20 : 24,
                ),
        ),
      ),
    );
  }
}
