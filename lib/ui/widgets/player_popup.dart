import 'package:flutter/material.dart';
import 'package:hbcure/services/player_service.dart';

class PlayerPopup extends StatelessWidget {
  final PlayerService player;

  /// sync resolver: id -> display name
  final String Function(String programId) resolveTitle;

  const PlayerPopup({
    super.key,
    required this.player,
    required this.resolveTitle,
  });

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h}h ${m}m ${sec}s';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: player,
        builder: (context, _) {
          final st = player.state;
          final currentId = st.currentProgramId;
          final title = currentId == null ? 'Playlist leer' : resolveTitle(currentId);

          final totalSeconds = st.total.inSeconds <= 0 ? 1 : st.total.inSeconds;
          final progress = (totalSeconds - st.remaining.inSeconds) / totalSeconds;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),

                LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
                const SizedBox(height: 8),

                Align(
                  alignment: Alignment.centerRight,
                  child: Text('${_fmt(st.remaining)} / ${_fmt(st.total)}'),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: st.hasPrev ? player.previous : null,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    IconButton(
                      onPressed: () {
                        if (st.isPlaying) {
                          player.pause();
                        } else {
                          // Wenn am Ende: Restart current
                          if (st.remaining == Duration.zero && st.total != Duration.zero) {
                            player.stop();
                            player.play();
                          } else {
                            player.play();
                          }
                        }
                      },
                      icon: Icon(st.isPlaying ? Icons.pause : Icons.play_arrow),
                      iconSize: 42,
                    ),
                    IconButton(
                      onPressed: player.stop,
                      icon: const Icon(Icons.stop),
                    ),
                    IconButton(
                      onPressed: st.hasNext ? player.next : null,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                if (st.queueIds.isNotEmpty)
                  Text(
                    '${st.currentIndex + 1} / ${st.queueIds.length}',
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
