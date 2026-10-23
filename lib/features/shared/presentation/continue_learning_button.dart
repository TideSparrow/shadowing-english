import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../player/presentation/learning_resume_provider.dart';
import 'pad/app_design_tokens.dart';

class ContinueLearningButton extends ConsumerStatefulWidget {
  const ContinueLearningButton({super.key});

  @override
  ConsumerState<ContinueLearningButton> createState() =>
      _ContinueLearningButtonState();
}

class _ContinueLearningButtonState
    extends ConsumerState<ContinueLearningButton> {
  bool _isOpening = false;

  @override
  Widget build(BuildContext context) {
    final ContinueLearningTarget? target = ref.watch(
      continueLearningTargetProvider,
    );
    if (target == null) return const SizedBox.shrink();
    return FloatingActionButton.extended(
      key: const ValueKey<String>('continue-learning-button'),
      heroTag: 'global-continue-learning',
      tooltip: '继续学习《${target.course.title}》 · 第 ${target.episode.numberStr} 集',
      onPressed: _isOpening
          ? null
          : () async {
              if (_isOpening) return;
              setState(() => _isOpening = true);
              try {
                await context.pushNamed<void>(
                  SGRoute.player.name,
                  pathParameters: <String, String>{
                    'episodeId': target.episode.id,
                  },
                  queryParameters: const <String, String>{'autoplay': '1'},
                );
              } finally {
                if (mounted) setState(() => _isOpening = false);
              }
            },
      backgroundColor: AppDesignTokens.brandGreen,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: const StadiumBorder(),
      icon: const Icon(Icons.play_circle_fill_rounded),
      label: const Text('继续学习', style: TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
