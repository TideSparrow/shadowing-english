// ignore_for_file: prefer_function_declarations_over_variables

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/authentication/presentation/login/login_screen.dart';
import '../features/daily_review/presentation/daily_review_screen.dart';
import '../features/growth/presentation/growth_screen.dart';
import '../features/guide/presentation/guide_screen.dart';
import '../features/home/presentation/pad_home_screen.dart';
import '../features/import_course/presentation/import_course_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/phrases/presentation/phrases_screen.dart';
import '../features/player/presentation/player_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/words/presentation/words_screen.dart';
import 'fade_extension.dart';

part 'app_router.g.dart';

enum SGRoute {
  home,
  library,
  growth,
  review,
  reviewSession,
  phrases,
  words,
  phraseReview,
  guide,
  settings,
  importCourse,
  login,
  player,
  register,
  forgotPassword,
  editProfile,
  changePassword;

  String get route => this == reviewSession
      ? '/review/session'
      : '/${toString().replaceAll('SGRoute.', '')}';
  String get name => toString().replaceAll('SGRoute.', '');
}

@riverpod
GoRouter goRouter(Ref ref) => GoRouter(
  initialLocation: SGRoute.home.route,
  routes: <GoRoute>[
    GoRoute(
      path: SGRoute.login.route,
      builder: (BuildContext context, GoRouterState state) {
        return const LoginScreen();
      },
    ).fade(),
    GoRoute(
      path: SGRoute.home.route,
      builder: (BuildContext context, GoRouterState state) =>
          const PadHomeScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.library.route,
      name: SGRoute.library.name,
      builder: (BuildContext context, GoRouterState state) {
        final String initialView = state.uri.queryParameters['view'] ?? 'list';
        return LibraryScreen(
          initialView: _parseLibraryView(initialView),
          initialCourseId: state.uri.queryParameters['courseId'],
          initialEpisodeId: state.uri.queryParameters['episodeId'],
        );
      },
    ).fade(),
    GoRoute(
      path: SGRoute.growth.route,
      builder: (BuildContext context, GoRouterState state) =>
          const GrowthScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.review.route,
      name: SGRoute.review.name,
      builder: (BuildContext context, GoRouterState state) =>
          const DailyReviewScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.reviewSession.route,
      name: SGRoute.reviewSession.name,
      builder: (BuildContext context, GoRouterState state) => DailyReviewScreen(
        session: true,
        practice: state.uri.queryParameters['practice'] == '1',
      ),
    ).fade(),
    GoRoute(
      path: SGRoute.phrases.route,
      builder: (BuildContext context, GoRouterState state) =>
          const PhrasesScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.words.route,
      builder: (BuildContext context, GoRouterState state) =>
          const WordsScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.phraseReview.route,
      name: SGRoute.phraseReview.name,
      builder: (BuildContext context, GoRouterState state) =>
          const DailyReviewScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.guide.route,
      builder: (BuildContext context, GoRouterState state) =>
          const GuideScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.settings.route,
      builder: (BuildContext context, GoRouterState state) =>
          const SettingsScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.importCourse.route,
      builder: (BuildContext context, GoRouterState state) =>
          const ImportCourseScreen(),
    ).fade(),
    GoRoute(
      path: '/episodes/:episodeId',
      name: SGRoute.player.name,
      builder: (BuildContext context, GoRouterState state) {
        return PlayerScreen(
          episodeId: state.pathParameters['episodeId']!,
          initialStartTime: state.uri.queryParameters['startTime'],
          autoPlay: state.uri.queryParameters['autoplay'] == '1',
          autoOpenFullscreen: state.uri.queryParameters['fullscreen'] == '1',
        );
      },
    ).fade(),
  ],
);

LibraryScreenView _parseLibraryView(String value) {
  if (value == 'import') {
    return LibraryScreenView.import;
  }
  if (value == 'detail') {
    return LibraryScreenView.detail;
  }
  return LibraryScreenView.list;
}
