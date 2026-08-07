import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:stockfish_flutter_plus/stockfish_flutter_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

const kLightSquare = Color(0xFFBFCCDE);
const kDarkSquare = Color(0xFF4A5C75);
const kBackground = Color(0xFF1A1F29);
const kPanelColor = Color(0xFF29333F);
const kSelectedSquare = Color(0xFF6C8FBF);
const kLegalMoveDot = Color(0xB3FFFFFF);

// A selectable board color palette. The default ("Blue-Gray") matches the
// app's original scheme; the others are alternate presets chosen from the
// menu. Only square colors vary — panels, backgrounds, and UI accents
// stay consistent across themes so the rest of the app doesn't reflow.
class BoardTheme {
  final String name;
  final Color lightSquare;
  final Color darkSquare;

  const BoardTheme({
    required this.name,
    required this.lightSquare,
    required this.darkSquare,
  });

  static const blueGray = BoardTheme(
    name: 'Blue-Gray',
    lightSquare: kLightSquare,
    darkSquare: kDarkSquare,
  );
  static const green = BoardTheme(
    name: 'Green',
    lightSquare: Color(0xFFEEEED2),
    darkSquare: Color(0xFF769656),
  );
  static const brown = BoardTheme(
    name: 'Brown',
    lightSquare: Color(0xFFE8D0AA),
    darkSquare: Color(0xFFA97A50),
  );
  static const purple = BoardTheme(
    name: 'Purple',
    lightSquare: Color(0xFFE3DBEE),
    darkSquare: Color(0xFF8B6FA8),
  );

  static const all = [blueGray, green, brown, purple];

  static BoardTheme byName(String? name) =>
      all.firstWhere((t) => t.name == name, orElse: () => blueGray);
}

// Board theme preference — a standing setting independent of any single
// saved game, so it's stored under its own key rather than with SavedGame.
const _kBoardThemeName = 'board_theme_name';

// First-launch flag — gates the onboarding screens so they only ever show
// once, then the app goes straight to the menu on every later launch.
const _kHasSeenOnboarding = 'has_seen_onboarding';

// First-time-only explanation dialog for Memory Training — separate from
// the main onboarding flow since a user might not open this mode right
// away, and it deserves its own "here's how this works" moment the first
// time they actually visit it.
const _kHasSeenMemoryIntro = 'has_seen_memory_intro';

// Lifetime stats keys (never reset). Daily stats are derived by comparing
// a stored "last active date" against today: if they differ, the daily
// counters are treated as zero without needing a separate reset step.
const _kStatsGamesPlayed = 'stats_games_played';
const _kStatsWins = 'stats_wins';
const _kStatsLosses = 'stats_losses';
const _kStatsDraws = 'stats_draws';
const _kStatsPuzzlesSolved = 'stats_puzzles_solved';
const _kStatsPuzzlesAttempted = 'stats_puzzles_attempted';
const _kStatsMemoryRoundsPlayed = 'stats_memory_rounds_played';
const _kStatsMemoryBestLevel = 'stats_memory_best_level';
const _kStatsLastActiveDate = 'stats_last_active_date'; // yyyy-mm-dd
const _kStatsTodayGamesPlayed = 'stats_today_games_played';
const _kStatsTodayPuzzlesSolved = 'stats_today_puzzles_solved';
const _kStatsTodayMemoryRounds = 'stats_today_memory_rounds';

String _todayDateString() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

// Bundles every stat shown on the Stats screen — lifetime totals plus
// today's counts (today's counts are zeroed automatically once the
// stored last-active date no longer matches today).
class AppStats {
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final int puzzlesSolved;
  final int puzzlesAttempted;
  final int memoryRoundsPlayed;
  final int memoryBestLevel;
  final int todayGamesPlayed;
  final int todayPuzzlesSolved;
  final int todayMemoryRounds;

  const AppStats({
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.puzzlesSolved,
    required this.puzzlesAttempted,
    required this.memoryRoundsPlayed,
    required this.memoryBestLevel,
    required this.todayGamesPlayed,
    required this.todayPuzzlesSolved,
    required this.todayMemoryRounds,
  });
}

Future<AppStats> _loadStats() async {
  final prefs = await SharedPreferences.getInstance();
  final lastActive = prefs.getString(_kStatsLastActiveDate);
  final isToday = lastActive == _todayDateString();
  return AppStats(
    gamesPlayed: prefs.getInt(_kStatsGamesPlayed) ?? 0,
    wins: prefs.getInt(_kStatsWins) ?? 0,
    losses: prefs.getInt(_kStatsLosses) ?? 0,
    draws: prefs.getInt(_kStatsDraws) ?? 0,
    puzzlesSolved: prefs.getInt(_kStatsPuzzlesSolved) ?? 0,
    puzzlesAttempted: prefs.getInt(_kStatsPuzzlesAttempted) ?? 0,
    memoryRoundsPlayed: prefs.getInt(_kStatsMemoryRoundsPlayed) ?? 0,
    memoryBestLevel: prefs.getInt(_kStatsMemoryBestLevel) ?? 1,
    todayGamesPlayed: isToday ? (prefs.getInt(_kStatsTodayGamesPlayed) ?? 0) : 0,
    todayPuzzlesSolved: isToday ? (prefs.getInt(_kStatsTodayPuzzlesSolved) ?? 0) : 0,
    todayMemoryRounds: isToday ? (prefs.getInt(_kStatsTodayMemoryRounds) ?? 0) : 0,
  );
}

// Resets the "today" counters to zero (by rewriting last-active-date) if
// the stored date isn't today, then increments both the lifetime and
// today counter named by `lifetimeKey`/`todayKey`. Called once per
// relevant event (game ended, puzzle attempted, memory round submitted).
Future<void> _bumpStat({
  required String lifetimeKey,
  required String todayKey,
  int amount = 1,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final today = _todayDateString();
  if (prefs.getString(_kStatsLastActiveDate) != today) {
    await prefs.setString(_kStatsLastActiveDate, today);
    await prefs.setInt(_kStatsTodayGamesPlayed, 0);
    await prefs.setInt(_kStatsTodayPuzzlesSolved, 0);
    await prefs.setInt(_kStatsTodayMemoryRounds, 0);
  }
  await prefs.setInt(lifetimeKey, (prefs.getInt(lifetimeKey) ?? 0) + amount);
  await prefs.setInt(todayKey, (prefs.getInt(todayKey) ?? 0) + amount);
}

Future<void> _recordGameResult(String result) async {
  // result: 'win', 'loss', or 'draw'
  await _bumpStat(lifetimeKey: _kStatsGamesPlayed, todayKey: _kStatsTodayGamesPlayed);
  final prefs = await SharedPreferences.getInstance();
  final key = result == 'win'
      ? _kStatsWins
      : result == 'loss'
          ? _kStatsLosses
          : _kStatsDraws;
  await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
}

Future<void> _recordPuzzleAttempt({required bool solved}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(
      _kStatsPuzzlesAttempted, (prefs.getInt(_kStatsPuzzlesAttempted) ?? 0) + 1);
  if (solved) {
    await _bumpStat(lifetimeKey: _kStatsPuzzlesSolved, todayKey: _kStatsTodayPuzzlesSolved);
  }
}

Future<void> _recordMemoryRound({required int levelReached}) async {
  await _bumpStat(lifetimeKey: _kStatsMemoryRoundsPlayed, todayKey: _kStatsTodayMemoryRounds);
  final prefs = await SharedPreferences.getInstance();
  final best = prefs.getInt(_kStatsMemoryBestLevel) ?? 1;
  if (levelReached > best) {
    await prefs.setInt(_kStatsMemoryBestLevel, levelReached);
  }
}

// Keys used to persist an in-progress game so it can be resumed from the
// menu screen after leaving via "Save & Exit".
const _kSavedFen = 'saved_game_fen';
const _kSavedHistory = 'saved_game_fen_history';
const _kSavedDifficulty = 'saved_game_difficulty';
const _kSavedPlayerColor = 'saved_game_player_color';
const _kSavedWhiteClock = 'saved_game_white_clock';
const _kSavedBlackClock = 'saved_game_black_clock';
const _kSavedUntimed = 'saved_game_untimed';

Future<void> _saveGame({
  required String fen,
  required List<String> fenHistory,
  required int skillLevel,
  required PlayerColor playerColor,
  required bool isUntimed,
  required int whiteClockSeconds,
  required int blackClockSeconds,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSavedFen, fen);
  await prefs.setStringList(_kSavedHistory, fenHistory);
  await prefs.setInt(_kSavedDifficulty, skillLevel);
  await prefs.setString(_kSavedPlayerColor, playerColor.name);
  await prefs.setBool(_kSavedUntimed, isUntimed);
  await prefs.setInt(_kSavedWhiteClock, whiteClockSeconds);
  await prefs.setInt(_kSavedBlackClock, blackClockSeconds);
}

Future<void> _clearSavedGame() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kSavedFen);
  await prefs.remove(_kSavedHistory);
  await prefs.remove(_kSavedDifficulty);
  await prefs.remove(_kSavedPlayerColor);
  await prefs.remove(_kSavedUntimed);
  await prefs.remove(_kSavedWhiteClock);
  await prefs.remove(_kSavedBlackClock);
}

class SavedGame {
  final String fen;
  final List<String> fenHistory;
  final int skillLevel;
  final PlayerColor playerColor;
  final TimeControl timeControl;
  final int whiteClockSeconds;
  final int blackClockSeconds;

  SavedGame({
    required this.fen,
    required this.fenHistory,
    required this.skillLevel,
    required this.playerColor,
    required this.timeControl,
    required this.whiteClockSeconds,
    required this.blackClockSeconds,
  });
}

Future<SavedGame?> _loadSavedGame() async {
  final prefs = await SharedPreferences.getInstance();
  final fen = prefs.getString(_kSavedFen);
  final history = prefs.getStringList(_kSavedHistory);
  // Read as an int (current format); fall back to a sensible default if
  // missing or if an old string-enum-format save is still on disk (from
  // before the Easy/Medium/Hard enum was replaced with a 1-20 slider).
  final skillLevel = prefs.getInt(_kSavedDifficulty) ?? 10;
  if (fen == null || history == null) return null;
  final colorName = prefs.getString(_kSavedPlayerColor);
  final playerColor = PlayerColor.values.firstWhere(
    (c) => c.name == colorName,
    orElse: () => PlayerColor.white,
  );
  final isUntimed = prefs.getBool(_kSavedUntimed) ?? false;
  final whiteClockSeconds = prefs.getInt(_kSavedWhiteClock) ?? 600;
  final blackClockSeconds = prefs.getInt(_kSavedBlackClock) ?? 600;
  final timeControl = isUntimed
      ? const TimeControl.untimed()
      : TimeControl.minutes(whiteClockSeconds ~/ 60);
  return SavedGame(
    fen: fen,
    fenHistory: history,
    skillLevel: skillLevel,
    playerColor: playerColor,
    timeControl: timeControl,
    whiteClockSeconds: whiteClockSeconds,
    blackClockSeconds: blackClockSeconds,
  );
}

// Shared TTS wrapper used by both the menu and game screens so Luna can
// speak lines of dialogue aloud, with the matching text also shown in her
// speech bubble.
class LunaSpeaker {
  static final FlutterTts _tts = FlutterTts()
    ..setLanguage('en-US')
    ..setSpeechRate(0.48)
    ..setPitch(1.15);

  static Future<void> speak(String text, {required bool voiceOn}) async {
    if (voiceOn) {
      await _tts.stop();
      await _tts.speak(text);
    }
  }
}

// A random pick from a list of candidate lines, so Luna doesn't say the
// exact same thing every time the same event happens.
String _pickLine(List<String> options) {
  return options[Random().nextInt(options.length)];
}

void main() {
  runApp(const LunaChessApp());
}

// Difficulty is a plain Stockfish Skill Level, 1-20, chosen via a
// scroll-wheel on the menu (see _DifficultyPicker) rather than a small
// enum of presets — this maps 1:1 onto the engine's own strength dial
// instead of an app-defined Easy/Medium/Hard abstraction over it.

enum PlayerColor { white, black }

// Either untimed play, or a per-side clock starting at a chosen number of
// minutes. Kept as a small value type (not just a nullable int) so "no
// time control" and "clock" are both explicit, unambiguous states.
class TimeControl {
  final int? minutes; // null = untimed
  const TimeControl.untimed() : minutes = null;
  const TimeControl.minutes(this.minutes);
  bool get isUntimed => minutes == null;
  int get seconds => (minutes ?? 0) * 60;
}

class LunaChessApp extends StatelessWidget {
  const LunaChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Luna Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: kBackground),
      home: const SplashScreen(),
    );
  }
}

// Shown briefly on every app launch: Luna's title fades and scales in.
// After the animation, routes to Onboarding (first launch only, gated by
// _kHasSeenOnboarding) or straight to the menu (every launch after that).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    _proceedAfterDelay();
  }

  Future<void> _proceedAfterDelay() async {
    // Held just long enough for the animation to read as intentional
    // rather than a flash, then decide where to go next.
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool(_kHasSeenOnboarding) ?? false;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      _fadeRoute(hasSeenOnboarding ? const MenuScreen() : const OnboardingScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: const Text(
              'Luna Chess',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// A shared fade transition used for the app's major screen-to-screen
// navigations (splash→onboarding/menu, onboarding→menu) so those
// transitions read as deliberate rather than the default abrupt
// platform slide. Individual push() calls elsewhere can use this too.
PageRouteBuilder<T> _fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 400),
  );
}

// First-launch-only walkthrough: a swipeable set of short intro cards
// explaining Luna, Puzzles, and Memory Training, followed by a Get
// Started button that marks onboarding as seen and moves to the menu.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  final String title;
  final String body;
  final String emoji;
  const _OnboardingPage({required this.title, required this.body, required this.emoji});
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _pageIndex = 0;

  static const _pages = [
    _OnboardingPage(
      emoji: '♟️',
      title: 'Meet Luna',
      body:
          "Luna is your chess companion — she comments on your moves, reacts to captures and checks, and can play at whatever difficulty suits you.",
    ),
    _OnboardingPage(
      emoji: '🧩',
      title: 'Puzzles',
      body:
          "Freshly generated positions, every time — find the best move Stockfish would play. A hint reveals which piece to move, but not where.",
    ),
    _OnboardingPage(
      emoji: '🧠',
      title: 'Memory Training',
      body:
          "Study a position, then place every piece back from memory. Difficulty ramps up automatically as you improve — built for chess players who want to train recall, not just play.",
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSeenOnboarding, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(_fadeRoute(const MenuScreen()));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _pageIndex == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip', style: TextStyle(color: Colors.white54)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  // AnimatedOpacity/Scale gives each page a soft entrance
                  // as it becomes the active page, rather than snapping in.
                  return TweenAnimationBuilder<double>(
                    key: ValueKey(index),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * 20),
                        child: child,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(page.emoji, style: const TextStyle(fontSize: 64)),
                          const SizedBox(height: 24),
                          Text(
                            page.title,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            page.body,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.white70,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final isActive = i == _pageIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive ? kSelectedSquare : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: _ActionButton(
                  label: isLastPage ? 'Get Started' : 'Next',
                  onPressed: () {
                    if (isLastPage) {
                      _finish();
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  int selectedSkillLevel = 10;
  PlayerColor selectedColor = PlayerColor.white;
  TimeControl selectedTimeControl = const TimeControl.minutes(10);
  BoardTheme selectedBoardTheme = BoardTheme.blueGray;
  SavedGame? savedGame;
  bool checkedForSavedGame = false;

  @override
  void initState() {
    super.initState();
    _checkForSavedGame();
    _loadBoardTheme();
  }

  Future<void> _loadBoardTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kBoardThemeName);
    if (mounted) {
      setState(() => selectedBoardTheme = BoardTheme.byName(name));
    }
  }

  Future<void> _checkForSavedGame() async {
    final saved = await _loadSavedGame();
    if (mounted) {
      setState(() {
        savedGame = saved;
        checkedForSavedGame = true;
      });
    }
  }

  void _startGame() {
    if (savedGame != null) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: kPanelColor,
          title: const Text('Start a new game?',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'You have a game in progress. Starting a new one will erase it '
            'unless you go back and continue it instead.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _clearSavedGame();
                _pushNewGame();
              },
              child: const Text('Start New (erase saved)'),
            ),
          ],
        ),
      );
    } else {
      _pushNewGame();
    }
  }

  void _pushNewGame() {
    Navigator.of(context)
        .push(
          _fadeRoute(
            ChessBoardScreen(
              skillLevel: selectedSkillLevel,
              playerColor: selectedColor,
              timeControl: selectedTimeControl,
              boardTheme: selectedBoardTheme,
            ),
          ),
        )
        .then((_) => _checkForSavedGame());
  }

  void _continueGame() {
    final saved = savedGame;
    if (saved == null) return;
    Navigator.of(context)
        .push(
          _fadeRoute(
            ChessBoardScreen(
              skillLevel: saved.skillLevel,
              playerColor: saved.playerColor,
              timeControl: saved.timeControl,
              boardTheme: selectedBoardTheme,
              resumeFen: saved.fen,
              resumeHistory: saved.fenHistory,
              resumeWhiteClockSeconds: saved.whiteClockSeconds,
              resumeBlackClockSeconds: saved.blackClockSeconds,
            ),
          ),
        )
        .then((_) => _checkForSavedGame());
  }

  void _openPuzzles() {
    Navigator.of(context).push(
      _fadeRoute(PuzzleScreen(boardTheme: selectedBoardTheme)),
    );
  }

  void _openMemoryTrain() {
    Navigator.of(context).push(
      _fadeRoute(MemoryTrainScreen(boardTheme: selectedBoardTheme)),
    );
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<_SettingsResult>(
      _fadeRoute<_SettingsResult>(
        SettingsScreen(
          skillLevel: selectedSkillLevel,
          playerColor: selectedColor,
          timeControl: selectedTimeControl,
          boardTheme: selectedBoardTheme,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        selectedSkillLevel = result.skillLevel;
        selectedColor = result.playerColor;
        selectedTimeControl = result.timeControl;
        selectedBoardTheme = result.boardTheme;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBoardThemeName, result.boardTheme.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart, color: Colors.white70),
            tooltip: 'Stats',
            onPressed: () => Navigator.of(context).push(
              _fadeRoute(const StatsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Luna Chess',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 48),
                      if (checkedForSavedGame && savedGame != null) ...[
                        _ActionButton(label: 'Continue Game', onPressed: _continueGame),
                        const SizedBox(height: 12),
                      ],
                      _ActionButton(label: 'Start New Game', onPressed: _startGame),
                      const SizedBox(height: 12),
                      _ActionButton(label: 'Puzzles', onPressed: _openPuzzles),
                      const SizedBox(height: 12),
                      _ActionButton(label: 'Memory Training', onPressed: _openMemoryTrain),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Return value from SettingsScreen back to the menu — a plain bundle of
// the four settings, since they're edited together on one screen but each
// lives as its own field on the menu.
class _SettingsResult {
  final int skillLevel;
  final PlayerColor playerColor;
  final TimeControl timeControl;
  final BoardTheme boardTheme;

  const _SettingsResult({
    required this.skillLevel,
    required this.playerColor,
    required this.timeControl,
    required this.boardTheme,
  });
}

// Holds every standing game-setup preference (difficulty, color, time
// control, board theme) in one place, reached via the gear icon on the
// menu — kept off the main menu screen so that screen can stay focused on
// "what do you want to do right now" (start a game, open puzzles, etc.)
// rather than being a long scroll of settings before any action button.
class SettingsScreen extends StatefulWidget {
  final int skillLevel;
  final PlayerColor playerColor;
  final TimeControl timeControl;
  final BoardTheme boardTheme;

  const SettingsScreen({
    super.key,
    required this.skillLevel,
    required this.playerColor,
    required this.timeControl,
    required this.boardTheme,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int skillLevel;
  late PlayerColor playerColor;
  late TimeControl timeControl;
  late BoardTheme boardTheme;

  @override
  void initState() {
    super.initState();
    skillLevel = widget.skillLevel;
    playerColor = widget.playerColor;
    timeControl = widget.timeControl;
    boardTheme = widget.boardTheme;
  }

  void _returnResult() {
    Navigator.of(context).pop(_SettingsResult(
      skillLevel: skillLevel,
      playerColor: playerColor,
      timeControl: timeControl,
      boardTheme: boardTheme,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Each change updates local state immediately (so the picker widgets
    // reflect it right away) and also pops with the latest values — the
    // back button/gesture is the only way to leave, and always saves,
    // since there's no destructive action here to warn about.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _returnResult();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white70),
          title: const Text('Settings', style: TextStyle(color: Colors.white)),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Text(
                    'Difficulty',
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  _DifficultyPicker(
                    selected: skillLevel,
                    onChanged: (d) => setState(() => skillLevel = d),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Play as',
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  _ColorPicker(
                    selected: playerColor,
                    onChanged: (c) => setState(() => playerColor = c),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Time',
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  _TimeControlPicker(
                    selected: timeControl,
                    onChanged: (tc) => setState(() => timeControl = tc),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Board theme',
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  _BoardThemePicker(
                    selected: boardTheme,
                    onChanged: (t) => setState(() => boardTheme = t),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// A horizontal scroll-wheel for picking a Stockfish Skill Level from 1
// (weakest) to 20 (strongest, full engine strength) — replaces the old
// Easy/Medium/Hard three-tier chips with direct, fine-grained control
// over the same dial Stockfish itself uses.
class _DifficultyPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _DifficultyPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Skill Level $selected',
          style: const TextStyle(fontSize: 15, color: Colors.white70),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          width: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Highlight band showing which column is the current pick.
              Container(
                width: 48,
                decoration: BoxDecoration(
                  color: kPanelColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              // ListWheelScrollView is vertical-only (no scrollDirection
              // param) — rotating the whole wheel 90° with RotatedBox and
              // counter-rotating each item's content is the standard way
              // to get a genuine horizontal wheel-scroll feel out of it,
              // rather than faking it with a plain ListView.
              RotatedBox(
                quarterTurns: -1,
                child: ListWheelScrollView.useDelegate(
                  itemExtent: 48,
                  diameterRatio: 1.8,
                  physics: const FixedExtentScrollPhysics(),
                  controller: FixedExtentScrollController(initialItem: selected - 1),
                  onSelectedItemChanged: (index) => onChanged(index + 1),
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: 20,
                    builder: (context, index) {
                      final level = index + 1;
                      final isCenter = level == selected;
                      return RotatedBox(
                        quarterTurns: 1,
                        child: Center(
                          child: Text(
                            '$level',
                            style: TextStyle(
                              fontSize: isCenter ? 20 : 16,
                              fontWeight: isCenter ? FontWeight.bold : FontWeight.normal,
                              color: isCenter ? Colors.white : Colors.white38,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final PlayerColor selected;
  final ValueChanged<PlayerColor> onChanged;

  const _ColorPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: PlayerColor.values.map((c) {
        final isSelected = c == selected;
        final label = c == PlayerColor.white ? 'White' : 'Black';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: ChoiceChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) => onChanged(c),
            selectedColor: kSelectedSquare,
            backgroundColor: kPanelColor,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// Lets the player pick a board color palette. Each option shows a small
// 2x2 checkerboard swatch in that theme's actual colors, plus its name,
// so the choice is visual rather than just a text label.
class _BoardThemePicker extends StatelessWidget {
  final BoardTheme selected;
  final ValueChanged<BoardTheme> onChanged;

  const _BoardThemePicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: BoardTheme.all.map((theme) {
        final isSelected = theme.name == selected.name;
        return GestureDetector(
          onTap: () => onChanged(theme),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPanelColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? kSelectedSquare : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(child: Container(color: theme.lightSquare)),
                              Expanded(child: Container(color: theme.darkSquare)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(child: Container(color: theme.darkSquare)),
                              Expanded(child: Container(color: theme.lightSquare)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  theme.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// Lets the player choose "no clock" or a per-side minutes value. A few
// common presets are offered as quick taps, plus a free-typed custom
// number of minutes — not restricted to the preset list.
class _TimeControlPicker extends StatelessWidget {
  final TimeControl selected;
  final ValueChanged<TimeControl> onChanged;

  const _TimeControlPicker({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // The wheel always shows *some* minute value even in Untimed mode (it
    // just remembers the last chosen number), so switching back from
    // Untimed doesn't reset to a default — it resumes wherever the wheel
    // was left.
    final wheelMinutes = selected.minutes ?? 10;
    return Column(
      children: [
        ChoiceChip(
          label: const Text('Untimed'),
          selected: selected.isUntimed,
          onSelected: (_) => onChanged(
            selected.isUntimed
                ? TimeControl.minutes(wheelMinutes)
                : const TimeControl.untimed(),
          ),
          selectedColor: kSelectedSquare,
          backgroundColor: kPanelColor,
          labelStyle: TextStyle(
            color: selected.isUntimed ? Colors.white : Colors.white70,
            fontWeight: selected.isUntimed ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: selected.isUntimed ? 0.35 : 1.0,
          child: IgnorePointer(
            ignoring: selected.isUntimed,
            child: SizedBox(
              height: 110,
              width: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Highlight band showing which row is the current pick.
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: kPanelColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  ListWheelScrollView.useDelegate(
                    itemExtent: 36,
                    diameterRatio: 1.4,
                    physics: const FixedExtentScrollPhysics(),
                    controller: FixedExtentScrollController(
                      initialItem: wheelMinutes - 1,
                    ),
                    onSelectedItemChanged: (index) {
                      onChanged(TimeControl.minutes(index + 1));
                    },
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: 60,
                      builder: (context, index) {
                        final minutes = index + 1;
                        final isCenter = minutes == wheelMinutes;
                        return Center(
                          child: Text(
                            '$minutes min',
                            style: TextStyle(
                              fontSize: isCenter ? 18 : 15,
                              fontWeight:
                                  isCenter ? FontWeight.bold : FontWeight.normal,
                              color: isCenter ? Colors.white : Colors.white38,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Luna's avatar + speech bubble. Four static images (one per mood) are
// swapped based on game state, animated with a natural eye-blink (vertical
// squash) so the still image reads as alive rather than a static photo.
// The avatar sits in a fixed-size box that never moves or resizes, even as
// the speech bubble text next to it appears/changes/disappears.
class LunaPanel extends StatefulWidget {
  final String mood; // 'idle', 'thinking', 'happy', 'worried'
  final String? line; // current speech bubble text, null = nothing shown
  final bool voiceOn;

  const LunaPanel({
    super.key,
    required this.mood,
    this.line,
    this.voiceOn = true,
  });

  @override
  State<LunaPanel> createState() => _LunaPanelState();
}

class _LunaPanelState extends State<LunaPanel> {
  String? _lastSpokenLine;

  @override
  void initState() {
    super.initState();
    _maybeSpeak();
  }

  @override
  void didUpdateWidget(LunaPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeSpeak();
  }

  void _maybeSpeak() {
    final line = widget.line;
    if (line != null && line != _lastSpokenLine) {
      _lastSpokenLine = line;
      LunaSpeaker.speak(line, voiceOn: widget.voiceOn);
    }
  }

  String _imageForMood() {
    switch (widget.mood) {
      case 'happy':
        return 'assets/images/luna_happy-1.png';
      case 'worried':
        return 'assets/images/luna_worried-1.png';
      case 'thinking':
        return 'assets/images/luna_thinking-1.png';
      default:
        return 'assets/images/luna_idle-1.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    // The panel sits inside a centered Column at both call sites. If the
    // Row below were mainAxisSize.min, its total width would grow/shrink
    // with the bubble text and the parent's centering would then shift the
    // avatar left/right along with it. Fixing this Row to the screen's
    // available width and left-aligning its children keeps the avatar's
    // pixel position constant no matter what the bubble does.
    return Center(
      child: SizedBox(
        width: 280,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              height: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(45),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Image.asset(
                    _imageForMood(),
                    key: ValueKey(_imageForMood()),
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            if (widget.line != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    key: ValueKey(widget.line),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: kPanelColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      widget.line!,
                      textAlign: TextAlign.left,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ChessBoardScreen extends StatefulWidget {
  final int skillLevel;
  final PlayerColor playerColor;
  final TimeControl timeControl;
  final BoardTheme boardTheme;
  final String? resumeFen;
  final List<String>? resumeHistory;
  final int? resumeWhiteClockSeconds;
  final int? resumeBlackClockSeconds;

  const ChessBoardScreen({
    super.key,
    required this.skillLevel,
    this.playerColor = PlayerColor.white,
    this.timeControl = const TimeControl.minutes(10),
    this.boardTheme = BoardTheme.blueGray,
    this.resumeFen,
    this.resumeHistory,
    this.resumeWhiteClockSeconds,
    this.resumeBlackClockSeconds,
  });

  @override
  State<ChessBoardScreen> createState() => _ChessBoardScreenState();
}

class _ChessBoardScreenState extends State<ChessBoardScreen> {
  late chess_lib.Chess game;
  int? selectedSquareIndex; // 0-63, null if nothing selected
  List<int> legalMoveTargets = [];
  String statusText = "White's move";
  bool voiceOn = true;
  int? hintFromIndex;
  int? hintToIndex;
  int? lastMoveFromIndex;
  int? lastMoveToIndex;
  int whiteClockSeconds = 600;
  int blackClockSeconds = 600;
  Timer? _clockTimer;
  // True once a side's clock hits zero. The chess_lib.Chess game object has
  // no concept of "lost on time" — game.game_over only reflects checkmate/
  // stalemate/draw — so this flag is checked everywhere game.game_over
  // would normally gate further play (taps, hints, engine moves) to
  // actually stop the game once time runs out.
  bool timeExpired = false;

  Stockfish? stockfish;
  bool aiThinking = false;
  bool hintLoading = false;
  bool _awaitingHint = false;
  // The board FEN a hint was requested for. If the position has since
  // changed (a move was made) by the time the hint's bestmove arrives, the
  // response is stale and must be discarded rather than applied — this is
  // the safety net behind the hintLoading/_awaitingHint re-tap guard.
  String? _hintRequestedForFen;
  List<String> fenHistory = [];
  String? lunaLine;
  // Which side the human plays — set from the menu's color picker.
  chess_lib.Color get humanSide => widget.playerColor == PlayerColor.white
      ? chess_lib.Color.WHITE
      : chess_lib.Color.BLACK;

  // Lightweight pattern tracking so Luna's commentary reacts to how the
  // game is actually going, not just the single move that just happened.
  // All local, no network — just counters updated alongside each move.
  int _humanCaptureStreak = 0; // consecutive human captures with no reply capture
  int _engineCaptureStreak = 0; // consecutive engine captures with no reply capture
  int _movesSinceLastCapture = 0;
  bool _hasCommentedOnLongGame = false;
  bool _hasCommentedOnQuickCaptureFlurry = false;

  static final List<String> _humanMoveLines = [
    "Nice move! 🙂",
    "Interesting... 🤔",
    "Let's see what you're planning. 👀",
    "Okay, my turn to think. 🧠",
    "Solid choice! 👍",
    "Hmm, didn't expect that. 🤨",
    "I see what you're doing. 😌",
    "Alright, my move now. ♟️",
    "Building something? 🏗️",
    "That's a reasonable move. 🙂",
  ];
  static final List<String> _humanCaptureLines = [
    "Ooh, nice capture! 😮",
    "You took my piece! 😅",
    "That's a good grab. 👏",
    "Ouch, didn't see that coming. 😬",
    "Fair trade, I suppose. 🤷",
  ];
  static final List<String> _humanKnightLines = [
    "Ooh, a knight hop! 🐴",
    "Knights are tricky — nice. 🐴✨",
    "That knight's got moves. 🐴",
  ];
  static final List<String> _humanBishopLines = [
    "Sliding across the diagonal! ✝️",
    "Nice bishop move. ✝️",
    "Watch those diagonals. ✝️👀",
  ];
  static final List<String> _humanRookLines = [
    "Rook on the move! 🏰",
    "Straight down the line. 🏰",
    "Rooks love open files. 🏰",
  ];
  static final List<String> _humanQueenLines = [
    "Bringing out the queen! 👑",
    "Your queen is powerful there. 👑✨",
    "Careful with her — she's valuable. 👑",
  ];
  static final List<String> _humanCastleLines = [
    "Castling — smart, tucking your king away. 🏯🛡️",
    "Nice, your king is safer now. 🛡️",
    "Good king safety. 🏯",
  ];
  static final List<String> _humanPromotionLines = [
    "A new queen is born! 👑✨",
    "Promotion! That's a big upgrade. 🎉",
    "That pawn earned it. 👑",
  ];
  static final List<String> _engineMoveLines = [
    "There, my move. ♟️",
    "Let's see how you handle that. 😏",
    "Your turn again. 👉",
    "Thinking ahead here. 🧠",
    "That should do it. 🙂",
    "Let's keep this interesting. 😌",
  ];
  static final List<String> _engineCaptureLines = [
    "Got one of yours! 😈",
    "I'll take that, thank you. 🙃",
    "Careful — I'm not holding back. ⚔️",
    "Couldn't resist. 😏",
  ];
  static final List<String> _engineCastleLines = [
    "I'll castle here — my king is safe now. 🏯",
  ];
  static final List<String> _checkLines = [
    "Check! Watch your king. ⚠️👑",
    "Your king is in danger! 🚨",
    "That's check — careful now. ⚠️",
  ];
  static final List<String> _humanWinLines = [
    "Checkmate! Well played, you win! 🏆🎉",
    "Wow, you got me! Great game. 👏😄",
    "That was well played — congrats! 🏆",
  ];
  static final List<String> _engineWinLines = [
    "Checkmate! Good game though. 🏆",
    "I win this one — want a rematch? 😏🔁",
    "Good fight — better luck next time. 🙂",
  ];
  static final List<String> _drawLines = [
    "A draw — well fought on both sides. 🤝",
    "Stalemate! Nobody wins this time. 😐",
    "Even game — nicely balanced. 🤝",
  ];
  static final List<String> _thinkingLines = [
    "Hmm, let me think... 🤔",
    "Give me a moment... ⏳",
    "Analyzing the position... 🧠",
    "This needs some thought. 🤔",
    "Let me consider my options... ♟️",
  ];
  // Fires when the human has captured several pieces in a row without
  // losing one back — a genuine "you're on a roll" moment, only shown
  // once per streak so it doesn't repeat every single capture.
  static final List<String> _humanCaptureStreakLines = [
    "You're on a roll! Keep it up. 🔥",
    "That's a nice streak you've got going. 🔥😮",
    "You're cleaning house out there! 🔥",
  ];
  static final List<String> _engineCaptureStreakLines = [
    "I'm on a bit of a streak here. 😈🔥",
    "That's a few in a row for me now. 😏",
  ];
  // Fires once, the first time a game runs long without a capture — a
  // quiet positional grind rather than a tactical fight.
  static final List<String> _longQuietGameLines = [
    "This is a slow, thoughtful game. I like it. 🧘",
    "Quite the positional battle we've got here. 🧠",
    "No captures in a while — real chess. 🙂",
  ];

  // Picks a natural comment for the human's move: special-move commentary
  // (castling, promotion) takes priority, then piece-specific flavor, then
  // a generic capture/move line as a fallback so there's always something
  // to say.
  List<String> _lineForHumanMove({
    required String from,
    required String to,
    required bool isCapture,
  }) {
    final piece = game.get(to);
    final isCastle = piece != null &&
        (piece.type.toString() == 'k' || piece.type.toString() == 'Piece.KING') &&
        (from == 'e1' || from == 'e8') &&
        (to == 'g1' || to == 'c1' || to == 'g8' || to == 'c8');
    if (isCastle) return _humanCastleLines;
    if (_pawnJustPromoted) return _humanPromotionLines;
    // Streak commentary takes priority over a plain capture line, but only
    // the moment the streak becomes noteworthy (3+) and only once per
    // streak — _humanCaptureStreak is reset to 0 whenever the engine
    // recaptures, so this naturally re-fires on a fresh streak later.
    if (isCapture && _humanCaptureStreak >= 3 && !_hasCommentedOnQuickCaptureFlurry) {
      _hasCommentedOnQuickCaptureFlurry = true;
      return _humanCaptureStreakLines;
    }
    if (isCapture) return _humanCaptureLines;
    if (!isCapture &&
        _movesSinceLastCapture >= 16 &&
        !_hasCommentedOnLongGame) {
      _hasCommentedOnLongGame = true;
      return _longQuietGameLines;
    }
    if (piece == null) return _humanMoveLines;
    switch (piece.type.toString()) {
      case 'n':
      case 'Piece.KNIGHT':
        return _humanKnightLines;
      case 'b':
      case 'Piece.BISHOP':
        return _humanBishopLines;
      case 'r':
      case 'Piece.ROOK':
        return _humanRookLines;
      case 'q':
      case 'Piece.QUEEN':
        return _humanQueenLines;
      default:
        return _humanMoveLines;
    }
  }

  List<String> _lineForEngineMove({
    required String from,
    required String to,
    required bool isCapture,
  }) {
    final piece = game.get(to);
    final isCastle = piece != null &&
        (piece.type.toString() == 'k' || piece.type.toString() == 'Piece.KING') &&
        (from == 'e1' || from == 'e8') &&
        (to == 'g1' || to == 'c1' || to == 'g8' || to == 'c8');
    if (isCastle) return _engineCastleLines;
    if (isCapture && _engineCaptureStreak >= 3 && !_hasCommentedOnQuickCaptureFlurry) {
      _hasCommentedOnQuickCaptureFlurry = true;
      return _engineCaptureStreakLines;
    }
    if (isCapture) return _engineCaptureLines;
    return _engineMoveLines;
  }

  // Updates the streak/quiet-game counters right after a move is applied
  // (both human and engine moves go through this), so the *next* move's
  // commentary can react to the pattern that's forming. Kept separate
  // from the line-selection functions above since those need to read the
  // state as it stood *before* this move, not after.
  void _updateMoveTracking({required bool isCapture, required bool wasHumanMove}) {
    if (isCapture) {
      _movesSinceLastCapture = 0;
      if (wasHumanMove) {
        _humanCaptureStreak++;
        _engineCaptureStreak = 0;
      } else {
        _engineCaptureStreak++;
        _humanCaptureStreak = 0;
      }
    } else {
      _movesSinceLastCapture++;
      // A non-capture move breaks any capture streak, so the "on a roll"
      // commentary is free to fire again the next time a fresh streak
      // builds up, rather than having said its one thing for the whole
      // game.
      if (_humanCaptureStreak > 0 || _engineCaptureStreak > 0) {
        _hasCommentedOnQuickCaptureFlurry = false;
      }
      _humanCaptureStreak = 0;
      _engineCaptureStreak = 0;
    }
  }

  // Set right before a promotion move is applied so _lineForHumanMove can
  // tell a promotion apart from an ordinary queen move.
  bool _pawnJustPromoted = false;

  @override
  void initState() {
    super.initState();
    // Preload the three SFX assets into the shared AudioCache so playback
    // is instant. Each move creates its own short-lived AudioPlayer (see
    // _playMoveSound) rather than reusing one long-lived player, since
    // reusing a single AudioPlayer across many rapid plays is a known
    // source of silent/stuck playback on some Android OEM audio stacks.
    AudioCache.instance.loadAll(['audio/move-2.wav', 'audio/capture-2.wav', 'audio/check-2.wav']);
    if (widget.resumeFen != null) {
      game = chess_lib.Chess.fromFEN(widget.resumeFen!);
      fenHistory = List.of(widget.resumeHistory ?? [game.fen]);
      whiteClockSeconds = widget.resumeWhiteClockSeconds ?? widget.timeControl.seconds;
      blackClockSeconds = widget.resumeBlackClockSeconds ?? widget.timeControl.seconds;
      _updateStatus();
    } else {
      game = chess_lib.Chess();
      fenHistory = [game.fen];
      whiteClockSeconds = widget.timeControl.seconds;
      blackClockSeconds = widget.timeControl.seconds;
    }
    _initEngine();
    if (!widget.timeControl.isUntimed) _startClock();
  }

  // Ticks once per second, deducting time from whichever side is currently
  // to move. Stops automatically once the game is over. Never called at
  // all for untimed games (see initState/_restart), so no clock UI or
  // time-based loss condition applies to them.
  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (game.game_over || timeExpired) {
        _clockTimer?.cancel();
        return;
      }
      setState(() {
        if (game.turn == chess_lib.Color.WHITE) {
          whiteClockSeconds = (whiteClockSeconds - 1).clamp(0, 999999);
        } else {
          blackClockSeconds = (blackClockSeconds - 1).clamp(0, 999999);
        }
        if (whiteClockSeconds == 0 || blackClockSeconds == 0) {
          _clockTimer?.cancel();
          timeExpired = true;
          selectedSquareIndex = null;
          legalMoveTargets = [];
          aiThinking = false;
          final winner = whiteClockSeconds == 0 ? 'Black' : 'White';
          statusText = '$winner wins on time';
          _clearSavedGame();
          final winnerColor =
              winner == 'White' ? chess_lib.Color.WHITE : chess_lib.Color.BLACK;
          _recordGameResult(winnerColor == humanSide ? 'win' : 'loss');
          lunaLine = _pickLine(
              winner == (widget.playerColor == PlayerColor.white ? 'White' : 'Black')
                  ? _humanWinLines
                  : _engineWinLines);
        }
      });
    });
  }

  String _formatClock(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    stockfish?.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _initEngine() async {
    final engine = Stockfish();
    stockfish = engine;
    engine.stdout.listen(_onEngineOutput);
    // If the human is playing Black, the engine (White) needs to make the
    // very first move — but stdin can't be sent until Stockfish reports
    // ready, so wait for that state rather than firing immediately.
    engine.state.addListener(() {
      if (engine.state.value == StockfishState.ready) {
        _maybeTriggerEngineMove();
      }
    });
  }

  // Scales the Stockfish "go" search budget (movetime, ms) with the chosen
  // Skill Level: low levels think briefly (matching their intentionally
  // weaker play), high levels get a longer budget to actually use their
  // full strength. Skill Level itself (1-20) is sent to Stockfish
  // directly as widget.skillLevel — no separate mapping needed now that
  // the menu exposes the same 1-20 dial the engine does.
  int _movetimeForSkillLevel(int level) {
    // Linear ramp from ~200ms at level 1 to ~2000ms at level 20.
    return 200 + ((level - 1) * (1800 / 19)).round();
  }

  void _onEngineOutput(String line) {
    if (line.startsWith('bestmove')) {
      final parts = line.split(' ');
      if (parts.length >= 2) {
        final uciMove = parts[1]; // e.g. "e2e4" or "e7e8q"
        if (_awaitingHint) {
          _awaitingHint = false;
          _applyHintMove(uciMove);
        } else if (aiThinking) {
          // Only apply as a real move if we actually asked the engine to
          // move (aiThinking is set exactly there, in
          // _maybeTriggerEngineMove). Without this check, any stray or
          // duplicate bestmove — e.g. a leftover response from an earlier
          // request — was being applied as a move unconditionally, which
          // is what caused a piece to move on its own and the board to
          // get stuck afterward.
          _applyEngineMove(uciMove);
        }
      }
    }
  }

  void _applyEngineMove(String uciMove) {
    if (uciMove == '(none)') {
      setState(() => aiThinking = false);
      return;
    }
    final from = uciMove.substring(0, 2);
    final to = uciMove.substring(2, 4);
    final promotion = uciMove.length > 4 ? uciMove.substring(4, 5) : null;
    // Check for a capture *before* making the move, same reasoning as
    // in _makeMove.
    final isCapture = game.get(to) != null;

    setState(() {
      game.move({
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      });
      fenHistory.add(game.fen);
      lastMoveFromIndex = _indexFromSquareName(from);
      lastMoveToIndex = _indexFromSquareName(to);
      aiThinking = false;
      _updateStatus();
      lunaLine = _pickLine(_lineForEngineMove(from: from, to: to, isCapture: isCapture));
      _updateMoveTracking(isCapture: isCapture, wasHumanMove: false);
    });
    _playMoveSound(isCapture: isCapture);
  }

  void _maybeTriggerEngineMove() {
    if (game.turn == humanSide) return;
    if (game.game_over || timeExpired) return;
    final engine = stockfish;
    if (engine == null) return;
    if (engine.state.value != StockfishState.ready) return;

    setState(() {
      aiThinking = true;
      lunaLine = _pickLine(_thinkingLines);
    });
    engine.stdin = 'position fen ${game.fen}';
    engine.stdin = 'setoption name Skill Level value ${widget.skillLevel}';
    engine.stdin = 'go movetime ${_movetimeForSkillLevel(widget.skillLevel)}';
  }

  // Convert (row, col) with row 0 = top of the visual board to the
  // algebraic square name the chess package expects, e.g. "e4".
  String squareName(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);
    final rank = 8 - row;
    return '$file$rank';
  }

  int squareIndex(int row, int col) => row * 8 + col;

  // When the human plays Black, the board is visually flipped so their
  // own pieces sit at the bottom, matching how a physical board would be
  // turned around. All grid rendering and tap handling goes through these
  // two functions to convert between "display" position (what's drawn on
  // screen, row 0 = top) and "logical" board row/col (row 0 = rank 8,
  // matching squareName above) — nothing else in the file needs to know
  // about orientation.
  int _displayToLogicalRow(int displayRow) =>
      humanSide == chess_lib.Color.BLACK ? 7 - displayRow : displayRow;
  int _displayToLogicalCol(int displayCol) =>
      humanSide == chess_lib.Color.BLACK ? 7 - displayCol : displayCol;

  int _indexFromSquareName(String name) {
    final col = name.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final row = 8 - int.parse(name[1]);
    return squareIndex(row, col);
  }

  void onSquareTapped(int row, int col) {
    if (aiThinking || timeExpired) return;
    if (game.turn != humanSide) return;
    final tappedIndex = squareIndex(row, col);
    final tappedSquareName = squareName(row, col);

    setState(() {
      hintFromIndex = null;
      hintToIndex = null;
      if (selectedSquareIndex == null) {
        // Nothing selected yet — try to select a piece belonging to the side to move.
        final piece = game.get(tappedSquareName);
        if (piece != null && piece.color == game.turn) {
          selectedSquareIndex = tappedIndex;
          legalMoveTargets = _legalTargetsFrom(tappedSquareName);
        }
      } else if (tappedIndex == selectedSquareIndex) {
        // Tapped the same square again — deselect.
        selectedSquareIndex = null;
        legalMoveTargets = [];
      } else if (legalMoveTargets.contains(tappedIndex)) {
        // Tapped a legal destination — make the move.
        final fromRow = selectedSquareIndex! ~/ 8;
        final fromCol = selectedSquareIndex! % 8;
        final fromName = squareName(fromRow, fromCol);
        selectedSquareIndex = null;
        legalMoveTargets = [];
        if (_isPromotionMove(fromName, tappedSquareName)) {
          _promptPromotion(fromName, tappedSquareName);
        } else {
          _makeMove(fromName, tappedSquareName);
        }
      } else {
        // Tapped a different square — if it's our own piece, switch selection.
        final piece = game.get(tappedSquareName);
        if (piece != null && piece.color == game.turn) {
          selectedSquareIndex = tappedIndex;
          legalMoveTargets = _legalTargetsFrom(tappedSquareName);
        } else {
          selectedSquareIndex = null;
          legalMoveTargets = [];
        }
      }
    });
  }

  List<int> _legalTargetsFrom(String fromSquareName) {
    final moves = game.moves({'square': fromSquareName, 'verbose': true});
    final targets = <int>[];
    for (final m in moves) {
      final toName = m['to'] as String;
      final col = toName.codeUnitAt(0) - 'a'.codeUnitAt(0);
      final row = 8 - int.parse(toName[1]);
      targets.add(squareIndex(row, col));
    }
    return targets;
  }

  bool _isPromotionMove(String from, String to) {
    final piece = game.get(from);
    if (piece == null) return false;
    final isPawn = piece.type.toString() == 'Piece.PAWN' ||
        piece.type.toString() == 'p';
    if (!isPawn) return false;
    final targetRank = to[1];
    return targetRank == '8' || targetRank == '1';
  }

  void _promptPromotion(String from, String to) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: kPanelColor,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Promote pawn to:',
                  style: TextStyle(fontSize: 18, color: Colors.white)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _PromotionChoice(glyph: '♛', label: 'Queen', onTap: () => Navigator.of(dialogContext).pop('q')),
                  _PromotionChoice(glyph: '♜', label: 'Rook', onTap: () => Navigator.of(dialogContext).pop('r')),
                  _PromotionChoice(glyph: '♝', label: 'Bishop', onTap: () => Navigator.of(dialogContext).pop('b')),
                  _PromotionChoice(glyph: '♞', label: 'Knight', onTap: () => Navigator.of(dialogContext).pop('n')),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((choice) {
      setState(() {
        _pawnJustPromoted = true;
        _makeMove(from, to, promotion: choice ?? 'q');
        _pawnJustPromoted = false;
      });
    });
  }

  void _makeMove(String from, String to, {String promotion = 'q'}) {
    // Check for a capture *before* making the move, since afterwards the
    // destination square holds our own piece.
    final isCapture = game.get(to) != null;
    game.move({'from': from, 'to': to, 'promotion': promotion});
    fenHistory.add(game.fen);
    lastMoveFromIndex = _indexFromSquareName(from);
    lastMoveToIndex = _indexFromSquareName(to);
    _playMoveSound(isCapture: isCapture);
    _updateStatus();
    lunaLine = _pickLine(_lineForHumanMove(from: from, to: to, isCapture: isCapture));
    _updateMoveTracking(isCapture: isCapture, wasHumanMove: true);
    _maybeTriggerEngineMove();
  }

  // Always plays — there is no SFX on/off toggle, only Luna's voice can be
  // muted independently via voiceOn.
  void _playMoveSound({bool isCapture = false}) {
    // Bundled short sound effects via audioplayers, more reliable across
    // devices than the system click sound (which some devices silence).
    // Check takes priority (most eventful), then capture, then a plain move.
    final String asset;
    if (game.in_check) {
      asset = 'audio/check-2.wav';
    } else if (isCapture) {
      asset = 'audio/capture-2.wav';
    } else {
      asset = 'audio/move-2.wav';
    }
    // AssetSource is known to fail to set its source in --release builds
    // on some devices (mimeType isn't reliably inferred in release mode —
    // see bluefireteam/audioplayers#1919), which matches the
    // "Failed to set source... MEDIA_ERROR_UNKNOWN" error seen on device.
    // Passing an explicit mimeType works around it.
    final player = AudioPlayer();
    player.setReleaseMode(ReleaseMode.release);
    player
        .play(AssetSource(asset, mimeType: 'audio/wav'), volume: 1.0);
  }

  void _updateStatus() {
    if (game.in_checkmate) {
      final winner = game.turn == chess_lib.Color.WHITE ? 'Black' : 'White';
      statusText = 'Checkmate — $winner wins';
      _clearSavedGame();
      lunaLine = _pickLine(winner == 'White' ? _humanWinLines : _engineWinLines);
      final winnerColor =
          winner == 'White' ? chess_lib.Color.WHITE : chess_lib.Color.BLACK;
      _recordGameResult(winnerColor == humanSide ? 'win' : 'loss');
    } else if (game.in_stalemate) {
      statusText = 'Stalemate — draw';
      _clearSavedGame();
      lunaLine = _pickLine(_drawLines);
      _recordGameResult('draw');
    } else if (game.in_draw) {
      statusText = 'Draw';
      _clearSavedGame();
      lunaLine = _pickLine(_drawLines);
      _recordGameResult('draw');
    } else if (game.in_check) {
      final side = game.turn == chess_lib.Color.WHITE ? 'White' : 'Black';
      statusText = '$side is in check';
      lunaLine = _pickLine(_checkLines);
    } else {
      final side = game.turn == chess_lib.Color.WHITE ? "White's" : "Black's";
      statusText = '$side move';
    }
  }

  void _restart() {
    setState(() {
      game = chess_lib.Chess();
      selectedSquareIndex = null;
      legalMoveTargets = [];
      statusText = "White's move";
      aiThinking = false;
      fenHistory = [game.fen];
      lastMoveFromIndex = null;
      lastMoveToIndex = null;
      timeExpired = false;
      whiteClockSeconds = widget.timeControl.seconds;
      blackClockSeconds = widget.timeControl.seconds;
      _humanCaptureStreak = 0;
      _engineCaptureStreak = 0;
      _movesSinceLastCapture = 0;
      _hasCommentedOnLongGame = false;
      _hasCommentedOnQuickCaptureFlurry = false;
    });
    if (!widget.timeControl.isUntimed) _startClock();
    _maybeTriggerEngineMove();
  }

  void _undo() {
    if (timeExpired) return;
    setState(() {
      // Undo the engine's reply too, if there was one, so the human is
      // always the one to move again after pressing Undo.
      game.undo_move();
      if (fenHistory.length > 1) fenHistory.removeLast();
      if (game.turn != humanSide && game.history.isNotEmpty) {
        game.undo_move();
        if (fenHistory.length > 1) fenHistory.removeLast();
      }
      selectedSquareIndex = null;
      legalMoveTargets = [];
      aiThinking = false;
      lastMoveFromIndex = null;
      lastMoveToIndex = null;
      _updateStatus();
    });
  }

  void _openAnalysis() async {
    // The Stockfish FFI binding appears to only support one live engine
    // process at a time — leaving this screen's engine running while
    // Analysis creates its own second instance is what left Analysis stuck
    // on "Evaluating..." (its engine never reached the ready state). Tear
    // this one down before navigating, and rebuild it on return. The
    // native process teardown isn't guaranteed to be synchronous, so a
    // short delay here gives it time to actually release before Analysis
    // tries to start a new one.
    _clockTimer?.cancel();
    stockfish?.dispose();
    stockfish = null;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await Navigator.of(context).push(
      _fadeRoute(
        AnalysisScreen(
          fenHistory: List.of(fenHistory),
          boardTheme: widget.boardTheme,
          playerColor: widget.playerColor,
        ),
      ),
    );
    if (!mounted) return;
    _initEngine();
    if (!widget.timeControl.isUntimed && !timeExpired && !game.game_over) {
      _startClock();
    }
  }

  void _backToMenu() {
    final gameIsOver = game.game_over || timeExpired;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kPanelColor,
        title: Text(
          gameIsOver ? 'Back to menu?' : 'Leave game?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          gameIsOver
              ? 'This game has ended.'
              : 'You can save your progress and continue later, or discard this game.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _clearSavedGame();
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(gameIsOver ? 'Exit' : 'Discard & Exit'),
          ),
          if (!gameIsOver)
            TextButton(
              onPressed: () async {
                await _saveGame(
                  fen: game.fen,
                  fenHistory: fenHistory,
                  skillLevel: widget.skillLevel,
                  playerColor: widget.playerColor,
                  isUntimed: widget.timeControl.isUntimed,
                  whiteClockSeconds: whiteClockSeconds,
                  blackClockSeconds: blackClockSeconds,
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text('Save & Exit'),
            ),
        ],
      ),
    );
  }

  void _toggleVoice() {
    setState(() => voiceOn = !voiceOn);
  }

  void _showHint() {
    // hintLoading/_awaitingHint guard against double-tapping Hint before
    // the first request resolves — sending a second Stockfish 'go' while
    // one is already in flight silently supersedes the first (Stockfish
    // only tracks one search at a time), and the stray bestmove that
    // eventually arrives was landing in the wrong place, which is what
    // caused a piece to move on its own and the board to freeze.
    if (aiThinking || timeExpired || hintLoading || _awaitingHint) return;
    if (game.turn != humanSide) return;
    final engine = stockfish;
    if (engine == null || engine.state.value != StockfishState.ready) return;

    setState(() => hintLoading = true);
    _awaitingHint = true;
    _hintRequestedForFen = game.fen;
    engine.stdin = 'position fen ${game.fen}';
    engine.stdin = 'setoption name Skill Level value 20';
    engine.stdin = 'go movetime 500';
  }

  void _applyHintMove(String uciMove) {
    // Safety net: if the board has moved on since this hint was requested
    // (e.g. timing overlap with an engine move), applying it would show a
    // hint for a position that no longer exists — discard it instead.
    final stale = _hintRequestedForFen != null && _hintRequestedForFen != game.fen;
    _hintRequestedForFen = null;
    if (stale || uciMove == '(none)') {
      setState(() => hintLoading = false);
      return;
    }
    final fromName = uciMove.substring(0, 2);
    final toName = uciMove.substring(2, 4);

    int indexFromName(String name) {
      final col = name.codeUnitAt(0) - 'a'.codeUnitAt(0);
      final row = 8 - int.parse(name[1]);
      return squareIndex(row, col);
    }

    setState(() {
      hintFromIndex = indexFromName(fromName);
      hintToIndex = indexFromName(toName);
      hintLoading = false;
    });
  }

  // Solid glyphs for both colors — we color them ourselves via TextStyle
  // rather than relying on the outline/filled Unicode variants, since some
  // fonts render the "white" (outline) chess glyphs as visually identical
  // to the "black" (filled) ones. The pawn glyph (U+265F) renders as a
  // colored emoji on some Android fonts, ignoring our TextStyle color
  // entirely — so we draw our own simple pawn shape instead of relying on
  // that character.
  String? _pieceGlyph(int row, int col) {
    final piece = game.get(squareName(row, col));
    if (piece == null) return null;
    switch (piece.type.toString()) {
      case 'Piece.PAWN':
      case 'p':
        return null; // handled separately as a drawn shape, see _isPawn
      case 'Piece.KNIGHT':
      case 'n':
        return '♞';
      case 'Piece.BISHOP':
      case 'b':
        return '♝';
      case 'Piece.ROOK':
      case 'r':
        return '♜';
      case 'Piece.QUEEN':
      case 'q':
        return '♛';
      case 'Piece.KING':
      case 'k':
        return '♚';
      default:
        return null;
    }
  }

  bool _isPawn(int row, int col) {
    final piece = game.get(squareName(row, col));
    if (piece == null) return false;
    final t = piece.type.toString();
    return t == 'Piece.PAWN' || t == 'p';
  }

  Color _pieceColor(int row, int col) {
    final piece = game.get(squareName(row, col));
    final isWhite = piece?.color == chess_lib.Color.WHITE;
    return isWhite ? const Color(0xFFF5F5F5) : const Color(0xFF1B1F27);
  }

  // Derives Luna's mood from the current game state for the avatar panel.
  String get _lunaMood {
    if (game.in_checkmate) {
      return game.turn == humanSide ? 'happy' : 'worried';
    }
    if (game.in_check && game.turn != humanSide) return 'happy';
    if (game.in_check) return 'worried';
    if (aiThinking) return 'thinking';
    return 'idle';
  }

  // Whichever color sits at the visual TOP of the (possibly flipped) board
  // — always the opponent's color, since the human's own side is kept at
  // the bottom, matching how a physical board is oriented.
  chess_lib.Color get _topSideColor =>
      humanSide == chess_lib.Color.WHITE
          ? chess_lib.Color.BLACK
          : chess_lib.Color.WHITE;

  chess_lib.Color get _bottomSideColor =>
      humanSide == chess_lib.Color.WHITE
          ? chess_lib.Color.WHITE
          : chess_lib.Color.BLACK;

  Widget _buildClockFor(chess_lib.Color side) {
    final isWhite = side == chess_lib.Color.WHITE;
    final seconds = isWhite ? whiteClockSeconds : blackClockSeconds;
    return Align(
      alignment: isWhite ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _ClockDisplay(
          label: isWhite ? 'White' : 'Black',
          seconds: seconds,
          isActive: game.turn == side && !game.game_over,
          formatted: _formatClock(seconds),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Intercept the system/back-gesture navigation too, not just the
      // in-app "Menu" button — otherwise leaving via Android's back button
      // skips the save/discard dialog entirely and silently abandons
      // whatever was in progress without ever offering to save it.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _backToMenu();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              tooltip: 'Menu',
              onPressed: _backToMenu,
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
            children: [
              const SizedBox(height: 24),
              const Text(
                'Luna Chess',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Skill Level ${widget.skillLevel}',
              style: const TextStyle(fontSize: 13, color: Colors.white38),
            ),
            const SizedBox(height: 12),
            LunaPanel(mood: _lunaMood, line: lunaLine, voiceOn: voiceOn),
            const SizedBox(height: 8),
            Text(
              aiThinking
                  ? "Luna is thinking..."
                  : hintLoading
                      ? "Finding a hint..."
                      : statusText,
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            if (!widget.timeControl.isUntimed) ...[
              // The clock for whichever color sits at the TOP of the (possibly
              // flipped) board is shown above it; the bottom side's clock is
              // shown below — so each clock visually sits on its own side.
              _buildClockFor(_topSideColor),
              const SizedBox(height: 8),
            ],
            AspectRatio(
              aspectRatio: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                  ),
                  itemCount: 64,
                  itemBuilder: (context, index) {
                    final displayRow = index ~/ 8;
                    final displayCol = index % 8;
                    final row = _displayToLogicalRow(displayRow);
                    final col = _displayToLogicalCol(displayCol);
                    final isLight = (row + col) % 2 == 0;
                    final isSelected = selectedSquareIndex == squareIndex(row, col);
                    final isLegalTarget =
                        legalMoveTargets.contains(squareIndex(row, col));
                    final isHintSquare = squareIndex(row, col) == hintFromIndex ||
                        squareIndex(row, col) == hintToIndex;
                    final isLastMoveSquare =
                        squareIndex(row, col) == lastMoveFromIndex ||
                            squareIndex(row, col) == lastMoveToIndex;
                    final glyph = _pieceGlyph(row, col);
                    final glyphColor = _pieceColor(row, col);
                    final strokeColor = glyphColor == const Color(0xFFF5F5F5)
                        ? const Color(0xFF1B1F27)
                        : const Color(0xFFF5F5F5);
                    final isPawnHere = _isPawn(row, col);

                    return GestureDetector(
                      onTap: () => onSquareTapped(row, col),
                      child: Container(
                        color: isSelected
                            ? kSelectedSquare
                            : isHintSquare
                                ? const Color(0xFF7FBF7F)
                                : isLastMoveSquare
                                    ? (isLight
                                        ? const Color(0xFFE0D98C)
                                        : const Color(0xFFB8A83E))
                                    : (isLight
                                        ? widget.boardTheme.lightSquare
                                        : widget.boardTheme.darkSquare),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (isPawnHere)
                              _PawnShape(
                                fillColor: glyphColor,
                                strokeColor: strokeColor,
                              ),
                            if (glyph != null)
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Outline pass: draws a thin stroke in the
                                  // opposite color so the piece stays legible
                                  // on both light and dark squares.
                                  Text(
                                    glyph,
                                    style: TextStyle(
                                      fontSize: 32,
                                      foreground: Paint()
                                        ..style = PaintingStyle.stroke
                                        ..strokeWidth = 2.2
                                        ..color = strokeColor,
                                    ),
                                  ),
                                  // Fill pass: the actual piece color on top.
                                  Text(
                                    glyph,
                                    style: TextStyle(
                                      fontSize: 32,
                                      color: glyphColor,
                                    ),
                                  ),
                                ],
                              ),
                            if (isLegalTarget)
                              Container(
                                width: 14,
                                height: 14,
                                decoration: const BoxDecoration(
                                  color: kLegalMoveDot,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (!widget.timeControl.isUntimed) ...[
              const SizedBox(height: 8),
              _buildClockFor(_bottomSideColor),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(label: 'Undo', onPressed: _undo),
                const SizedBox(width: 12),
                _ActionButton(label: 'Restart', onPressed: _restart),
                const SizedBox(width: 12),
                _ActionButton(label: 'Hint', onPressed: _showHint),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  label: voiceOn ? 'Voice: On' : 'Voice: Off',
                  onPressed: _toggleVoice,
                ),
                const SizedBox(width: 12),
                _ActionButton(
                  label: 'Analysis',
                  onPressed: fenHistory.length > 1 ? _openAnalysis : () {},
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          ),
        ),
      ),
      ),
    );
  }
}

// Puzzle mode: Stockfish plays a short randomized self-game to reach a
// varied position, then that position becomes the puzzle — the user must
// find Stockfish's own top move in it. No bundled puzzle database; every
// puzzle is generated fresh from the engine.
class PuzzleScreen extends StatefulWidget {
  final BoardTheme boardTheme;

  const PuzzleScreen({super.key, this.boardTheme = BoardTheme.blueGray});

  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

enum _PuzzlePhase { generating, solving, correct, incorrect, sequenceComplete }

class _PuzzleScreenState extends State<PuzzleScreen> {
  Stockfish? stockfish;
  chess_lib.Chess game = chess_lib.Chess();
  _PuzzlePhase phase = _PuzzlePhase.generating;
  int? selectedSquareIndex;
  List<int> legalMoveTargets = [];
  // The full sequence of correct moves for this puzzle, computed once up
  // front (before the user starts solving) by repeatedly asking Stockfish
  // for the best move and applying it. Each entry is a UCI move like
  // "e2e4". currentMoveIndex tracks how far through the sequence the user
  // has gotten.
  List<String> solutionSequence = [];
  int currentMoveIndex = 0;
  String? lastAttemptFrom;
  String? lastAttemptTo;
  int solvedCount = 0;
  int attemptedCount = 0;
  bool hintRevealed = false;
  final Random _random = Random();
  bool _awaitingSetupMove = false;
  bool _awaitingSequenceMove = false;
  int _setupMovesRemaining = 0;
  int _sequenceMovesRemaining = 0;

  int get solutionSequenceLength => solutionSequence.length;

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  @override
  void dispose() {
    stockfish?.dispose();
    super.dispose();
  }

  Future<void> _initEngine() async {
    final engine = Stockfish();
    stockfish = engine;
    engine.stdout.listen(_onEngineOutput);
    engine.state.addListener(() {
      if (engine.state.value == StockfishState.ready) {
        _generateNewPuzzle();
      }
    });
  }

  void _generateNewPuzzle() {
    final engine = stockfish;
    if (engine == null || engine.state.value != StockfishState.ready) return;
    setState(() {
      phase = _PuzzlePhase.generating;
      game = chess_lib.Chess();
      selectedSquareIndex = null;
      legalMoveTargets = [];
      solutionSequence = [];
      currentMoveIndex = 0;
      lastAttemptFrom = null;
      lastAttemptTo = null;
      hintRevealed = false;
      // A random number of half-moves (6–16) gives varied, non-opening
      // positions without needing any bundled puzzle data.
      _setupMovesRemaining = 6 + _random.nextInt(11);
    });
    _playNextSetupMove();
  }

  void _playNextSetupMove() {
    if (_setupMovesRemaining <= 0 || game.game_over) {
      // 2-5 moves per puzzle, decided fresh each round.
      _sequenceMovesRemaining = 2 + _random.nextInt(4);
      _requestNextSequenceMove();
      return;
    }
    final engine = stockfish;
    if (engine == null || engine.state.value != StockfishState.ready) return;
    _awaitingSetupMove = true;
    engine.stdin = 'position fen ${game.fen}';
    // Low skill + short movetime during setup keeps self-play games
    // varied (not always the same "best" line) and fast to generate.
    engine.stdin = 'setoption name Skill Level value ${_random.nextInt(15)}';
    engine.stdin = 'go movetime 60';
  }

  // Builds the solution sequence by asking Stockfish for the best move in
  // the position, then applying it to a scratch board to get the next
  // position, and repeating — all before the user sees anything. The
  // live `game` board isn't touched by this; it stays at the puzzle's
  // starting position until the user actually solves each step.
  chess_lib.Chess? _sequenceScratchGame;

  void _requestNextSequenceMove() {
    if (_sequenceMovesRemaining <= 0) {
      setState(() => phase = _PuzzlePhase.solving);
      return;
    }
    _sequenceScratchGame ??= chess_lib.Chess.fromFEN(game.fen);
    if (_sequenceScratchGame!.game_over) {
      // Ran out of legal replies — shorten the sequence to what we've got.
      setState(() => phase = _PuzzlePhase.solving);
      return;
    }
    final engine = stockfish;
    if (engine == null || engine.state.value != StockfishState.ready) return;
    _awaitingSequenceMove = true;
    engine.stdin = 'position fen ${_sequenceScratchGame!.fen}';
    engine.stdin = 'setoption name Skill Level value 20';
    engine.stdin = 'go movetime 500';
  }

  void _onEngineOutput(String line) {
    if (!line.startsWith('bestmove')) return;
    final parts = line.split(' ');
    if (parts.length < 2) return;
    final uciMove = parts[1];
    if (uciMove == '(none)') {
      if (_awaitingSequenceMove) {
        _awaitingSequenceMove = false;
        // No more legal replies — the sequence ends here, however long it
        // got. Still a valid puzzle as long as at least one move exists.
        if (solutionSequence.isEmpty) {
          _generateNewPuzzle();
        } else {
          setState(() => phase = _PuzzlePhase.solving);
        }
      } else if (_awaitingSetupMove) {
        _awaitingSetupMove = false;
        _sequenceMovesRemaining = 2 + _random.nextInt(4);
        _requestNextSequenceMove();
      }
      return;
    }
    if (_awaitingSetupMove) {
      _awaitingSetupMove = false;
      final from = uciMove.substring(0, 2);
      final to = uciMove.substring(2, 4);
      final promotion = uciMove.length > 4 ? uciMove.substring(4, 5) : null;
      game.move({
        'from': from,
        'to': to,
        if (promotion != null) 'promotion': promotion,
      });
      _setupMovesRemaining--;
      _playNextSetupMove();
    } else if (_awaitingSequenceMove) {
      _awaitingSequenceMove = false;
      solutionSequence.add(uciMove);
      _sequenceScratchGame!.move({
        'from': uciMove.substring(0, 2),
        'to': uciMove.substring(2, 4),
        if (uciMove.length > 4) 'promotion': uciMove.substring(4, 5),
      });
      _sequenceMovesRemaining--;
      _requestNextSequenceMove();
    }
  }

  String _squareName(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);
    final rank = 8 - row;
    return '$file$rank';
  }

  int _squareIndex(int row, int col) => row * 8 + col;

  // The puzzle always asks the user to find a move for whichever side is
  // actually to move in the generated position — there's no fixed "human
  // color" here like in the main game. So the board flips based on
  // game.turn: when it's Black to move, Black's pieces render at the
  // bottom, matching how the user is meant to think about the position.
  int _displayToLogicalRow(int displayRow) =>
      game.turn == chess_lib.Color.BLACK ? 7 - displayRow : displayRow;
  int _displayToLogicalCol(int displayCol) =>
      game.turn == chess_lib.Color.BLACK ? 7 - displayCol : displayCol;

  List<int> _legalTargetsFrom(String fromSquareName) {
    final moves = game.moves({'square': fromSquareName, 'verbose': true});
    final targets = <int>[];
    for (final m in moves) {
      final toName = m['to'] as String;
      final col = toName.codeUnitAt(0) - 'a'.codeUnitAt(0);
      final row = 8 - int.parse(toName[1]);
      targets.add(_squareIndex(row, col));
    }
    return targets;
  }

  void _onSquareTapped(int row, int col) {
    if (phase != _PuzzlePhase.solving) return;
    final tappedIndex = _squareIndex(row, col);
    final tappedSquareName = _squareName(row, col);

    setState(() {
      if (selectedSquareIndex == null) {
        final piece = game.get(tappedSquareName);
        if (piece != null && piece.color == game.turn) {
          selectedSquareIndex = tappedIndex;
          legalMoveTargets = _legalTargetsFrom(tappedSquareName);
        }
      } else if (tappedIndex == selectedSquareIndex) {
        selectedSquareIndex = null;
        legalMoveTargets = [];
      } else if (legalMoveTargets.contains(tappedIndex)) {
        final fromRow = selectedSquareIndex! ~/ 8;
        final fromCol = selectedSquareIndex! % 8;
        final fromName = _squareName(fromRow, fromCol);
        selectedSquareIndex = null;
        legalMoveTargets = [];
        _attemptMove(fromName, tappedSquareName);
      } else {
        final piece = game.get(tappedSquareName);
        if (piece != null && piece.color == game.turn) {
          selectedSquareIndex = tappedIndex;
          legalMoveTargets = _legalTargetsFrom(tappedSquareName);
        } else {
          selectedSquareIndex = null;
          legalMoveTargets = [];
        }
      }
    });
  }

  void _showHint() {
    if (phase != _PuzzlePhase.solving) return;
    setState(() => hintRevealed = true);
  }

  void _attemptMove(String from, String to) {
    final expected = solutionSequence[currentMoveIndex];
    final expectedFrom = expected.substring(0, 2);
    final expectedTo = expected.substring(2, 4);
    final isCorrect = from == expectedFrom && to == expectedTo;
    attemptedCount++;
    if (!isCorrect) {
      // Wrong attempts are never shown the solution — just a plain
      // incorrect signal, and the board stays exactly where it was so
      // the user can try again with a fresh selection.
      _recordPuzzleAttempt(solved: false);
      setState(() {
        lastAttemptFrom = from;
        lastAttemptTo = to;
        phase = _PuzzlePhase.incorrect;
      });
      return;
    }
    // Correct: actually apply the move to the live board, then either
    // advance to the next move in the sequence or finish the puzzle.
    game.move({'from': from, 'to': to, 'promotion': 'q'});
    final isLastMove = currentMoveIndex == solutionSequence.length - 1;
    if (isLastMove) {
      solvedCount++;
      _recordPuzzleAttempt(solved: true);
      setState(() {
        currentMoveIndex++;
        hintRevealed = false;
        phase = _PuzzlePhase.sequenceComplete;
      });
    } else {
      setState(() {
        currentMoveIndex++;
        hintRevealed = false;
        phase = _PuzzlePhase.solving;
      });
    }
  }

  // After a wrong attempt, lets the user try the same move again without
  // regenerating the whole puzzle — the board/sequence position is
  // unchanged, only the "incorrect" message needs clearing.
  void _tryAgain() {
    setState(() => phase = _PuzzlePhase.solving);
  }

  String? _pieceGlyph(int row, int col) {
    final piece = game.get(_squareName(row, col));
    if (piece == null) return null;
    switch (piece.type.toString()) {
      case 'Piece.PAWN':
      case 'p':
        return null;
      case 'Piece.KNIGHT':
      case 'n':
        return '♞';
      case 'Piece.BISHOP':
      case 'b':
        return '♝';
      case 'Piece.ROOK':
      case 'r':
        return '♜';
      case 'Piece.QUEEN':
      case 'q':
        return '♛';
      case 'Piece.KING':
      case 'k':
        return '♚';
      default:
        return null;
    }
  }

  bool _isPawn(int row, int col) {
    final piece = game.get(_squareName(row, col));
    if (piece == null) return false;
    final t = piece.type.toString();
    return t == 'Piece.PAWN' || t == 'p';
  }

  Color _pieceColor(int row, int col) {
    final piece = game.get(_squareName(row, col));
    final isWhite = piece?.color == chess_lib.Color.WHITE;
    return isWhite ? const Color(0xFFF5F5F5) : const Color(0xFF1B1F27);
  }

  int? _indexForSquareName(String? name) {
    if (name == null) return null;
    final col = name.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final row = 8 - int.parse(name[1]);
    return _squareIndex(row, col);
  }

  @override
  Widget build(BuildContext context) {
    final toMove = game.turn == chess_lib.Color.WHITE ? 'White' : 'Black';
    // Hint reveals only the piece to move, not the destination — the user
    // still has to work out where it goes. Never available for the
    // solution's destination square, and never shown after a wrong
    // attempt (that would leak the answer).
    final hintFromIndex = (phase == _PuzzlePhase.solving &&
            hintRevealed &&
            currentMoveIndex < solutionSequence.length)
        ? _indexForSquareName(
            solutionSequence[currentMoveIndex].substring(0, 2))
        : null;
    final attemptFromIndex = _indexForSquareName(lastAttemptFrom);
    final attemptToIndex = _indexForSquareName(lastAttemptTo);
    final showingProgress = solutionSequenceLength > 0 &&
        (phase == _PuzzlePhase.solving ||
            phase == _PuzzlePhase.incorrect ||
            phase == _PuzzlePhase.sequenceComplete);

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white70),
          title: const Text('Puzzles', style: TextStyle(color: Colors.white)),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  'Solved: $solvedCount / $attemptedCount',
                  style: const TextStyle(fontSize: 14, color: Colors.white54),
                ),
                if (showingProgress) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Move ${(currentMoveIndex + 1).clamp(1, solutionSequenceLength)} of $solutionSequenceLength',
                    style: const TextStyle(fontSize: 13, color: Colors.white38),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  phase == _PuzzlePhase.generating
                      ? 'Preparing puzzle...'
                      : phase == _PuzzlePhase.solving
                          ? "Find $toMove's best move"
                          : phase == _PuzzlePhase.incorrect
                              ? 'Not quite — try again'
                              : 'Puzzle solved! 🎉',
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
                const SizedBox(height: 16),
                AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
                      itemCount: 64,
                      itemBuilder: (context, index) {
                        final displayRow = index ~/ 8;
                        final displayCol = index % 8;
                        final row = _displayToLogicalRow(displayRow);
                        final col = _displayToLogicalCol(displayCol);
                        final isLight = (row + col) % 2 == 0;
                        final isSelected = selectedSquareIndex == _squareIndex(row, col);
                        final isLegalTarget =
                            legalMoveTargets.contains(_squareIndex(row, col));
                        final isWrongAttemptSquare = phase == _PuzzlePhase.incorrect &&
                            (_squareIndex(row, col) == attemptFromIndex ||
                                _squareIndex(row, col) == attemptToIndex);
                        final isHintSquare = _squareIndex(row, col) == hintFromIndex;
                        final glyph = _pieceGlyph(row, col);
                        final glyphColor = _pieceColor(row, col);
                        final strokeColor = glyphColor == const Color(0xFFF5F5F5)
                            ? const Color(0xFF1B1F27)
                            : const Color(0xFFF5F5F5);
                        final isPawnHere = _isPawn(row, col);

                        return GestureDetector(
                          onTap: () => _onSquareTapped(row, col),
                          child: Container(
                            color: isSelected
                                ? kSelectedSquare
                                : isWrongAttemptSquare
                                    ? const Color(0xFFBF7F7F)
                                    : isHintSquare
                                        ? const Color(0xFFD9C46A)
                                        : (isLight
                                            ? widget.boardTheme.lightSquare
                                            : widget.boardTheme.darkSquare),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (isPawnHere)
                                  _PawnShape(fillColor: glyphColor, strokeColor: strokeColor),
                                if (glyph != null)
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Text(
                                        glyph,
                                        style: TextStyle(
                                          fontSize: 32,
                                          foreground: Paint()
                                            ..style = PaintingStyle.stroke
                                            ..strokeWidth = 2.2
                                            ..color = strokeColor,
                                        ),
                                      ),
                                      Text(
                                        glyph,
                                        style: TextStyle(fontSize: 32, color: glyphColor),
                                      ),
                                    ],
                                  ),
                                if (isLegalTarget)
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: const BoxDecoration(
                                      color: kLegalMoveDot,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (phase == _PuzzlePhase.solving)
                  _ActionButton(
                    label: hintRevealed ? 'Hint: shown' : 'Hint',
                    onPressed: hintRevealed ? () {} : _showHint,
                  ),
                if (phase == _PuzzlePhase.incorrect)
                  _ActionButton(label: 'Try Again', onPressed: _tryAgain),
                if (phase == _PuzzlePhase.sequenceComplete)
                  _ActionButton(label: 'Next Puzzle', onPressed: _generateNewPuzzle),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Memory training mode: Stockfish self-plays a short randomized game to
// produce a varied position, that position is shown on the board for a
// fixed study time, then the board clears and the user must place every
// piece back on its correct square from a palette of piece buttons.
// Scored by how many squares end up correct. No bundled data — positions
// are generated fresh each round, same approach as Puzzles.
class MemoryTrainScreen extends StatefulWidget {
  final BoardTheme boardTheme;

  const MemoryTrainScreen({super.key, this.boardTheme = BoardTheme.blueGray});

  @override
  State<MemoryTrainScreen> createState() => _MemoryTrainScreenState();
}

enum _MemoryPhase { generating, studying, placing, results }

// A single piece placement: type + color, without square info — the
// "correct" answer key is a Map<squareIndex, _PieceSpec>, and the palette
// offers one draggable/tappable button per distinct spec still remaining.
class _PieceSpec {
  final String type; // 'p','n','b','r','q','k'
  final chess_lib.Color color;
  const _PieceSpec(this.type, this.color);

  @override
  bool operator ==(Object other) =>
      other is _PieceSpec && other.type == type && other.color == color;
  @override
  int get hashCode => Object.hash(type, color);

  String get glyph {
    switch (type) {
      case 'n':
        return '♞';
      case 'b':
        return '♝';
      case 'r':
        return '♜';
      case 'q':
        return '♛';
      case 'k':
        return '♚';
      default:
        return ''; // pawn drawn separately
    }
  }
}

class _MemoryTrainScreenState extends State<MemoryTrainScreen> {
  Stockfish? stockfish;
  chess_lib.Chess game = chess_lib.Chess();
  _MemoryPhase phase = _MemoryPhase.generating;
  final Random _random = Random();
  bool _awaitingSetupMove = false;
  int _setupMovesRemaining = 0;

  // Level 1 shows just a handful of pieces (easy to remember); each level
  // up adds more, ramping toward a full board by the top level. This is
  // controlled directly — a real position is generated via a short
  // Stockfish self-play game, then randomly thinned down to the target
  // piece count for the current level, so difficulty tracks "how many
  // pieces are on the board" rather than "how many moves were played"
  // (a small move count can still leave 30 pieces on the board, which
  // isn't actually easier to memorize).
  //
  // Timing follows published memory-training practice rather than a
  // guess: sources on chess memory drills (e.g. DYNSEO's protocol) use a
  // ~30s study window for a first block of 4-5 pieces, ramping piece
  // count over weeks rather than compressing study time toward what only
  // trained memory athletes can do. So level 1 starts at 30s (not the
  // previous 26s), and the floor at the top level is 12s (not 8s) —
  // still a real challenge, but not requiring competition-grade recall
  // speed to ever reach level 10.
  int level = 1;
  static const int maxLevel = 10;
  int get _targetPieceCountForLevel => 4 + (level - 1) * 3; // 4,7,...,31
  int get studySecondsForLevel =>
      (30 - (level - 1) * 2).clamp(12, 30); // 30,28,...,12
  int secondsLeft = 30;
  Timer? _studyTimer;

  // The answer key: every occupied square's correct piece, captured right
  // before the board is cleared for the placing phase.
  Map<int, _PieceSpec> answerKey = {};
  // What the user has placed so far, keyed the same way.
  Map<int, _PieceSpec> placed = {};
  _PieceSpec? selectedPaletteSpec;
  int correctCount = 0;
  // Counts consecutive rounds solved with 100% accuracy — resets to 0 the
  // moment a round isn't perfect. Tracked purely for the on-screen streak
  // badge/reward; doesn't affect level progression itself.
  int perfectStreak = 0;
  int bestPerfectStreak = 0;

  // True while the first-time intro dialog is showing (or hasn't been
  // checked yet) — the engine-ready listener must not start generating a
  // round (and thus starting the study timer) until this clears, or the
  // timer runs invisibly behind the dialog and the user loses seconds
  // they never got to actually study the position for.
  bool _waitingOnIntro = true;

  @override
  void initState() {
    super.initState();
    _checkIntroThenInit();
  }

  Future<void> _checkIntroThenInit() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool(_kHasSeenMemoryIntro) ?? false;
    if (!hasSeen) {
      await prefs.setBool(_kHasSeenMemoryIntro, true);
    }
    if (!mounted) return;
    _initEngine();
    if (hasSeen) {
      // Nothing to show — clear the gate immediately so the engine-ready
      // listener is free to auto-generate the first round as normal.
      _waitingOnIntro = false;
    } else {
      // Gate stays up until the dialog's "Got it" button clears it and
      // kicks off generation itself.
      _showIntroDialog();
    }
  }

  void _showIntroDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('How Memory Training works',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          "You'll see a position on the board for a few seconds — study "
          "where every piece is. Then the board clears and you place each "
          "piece back from the palette below: tap a piece, then tap the "
          "square it belongs on. Tap a filled square to pick a piece back "
          "up if you change your mind.\n\n"
          "Solve well and the difficulty ramps up automatically — more "
          "pieces, less time.",
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _waitingOnIntro = false;
              // The engine may have already reached ready state while the
              // dialog was up (its listener was gated by _waitingOnIntro,
              // so nothing started automatically) — kick off the first
              // round now that the user has actually seen the explanation.
              _generateNewRound();
            },
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _studyTimer?.cancel();
    stockfish?.dispose();
    super.dispose();
  }

  Future<void> _initEngine() async {
    final engine = Stockfish();
    stockfish = engine;
    engine.stdout.listen(_onEngineOutput);
    engine.state.addListener(() {
      if (engine.state.value == StockfishState.ready && !_waitingOnIntro) {
        _generateNewRound();
      }
    });
  }

  void _generateNewRound() {
    final engine = stockfish;
    if (engine == null || engine.state.value != StockfishState.ready) return;
    _studyTimer?.cancel();
    setState(() {
      phase = _MemoryPhase.generating;
      game = chess_lib.Chess();
      answerKey = {};
      placed = {};
      selectedPaletteSpec = null;
      correctCount = 0;
      secondsLeft = studySecondsForLevel;
      // A short, fixed amount of self-play gives a realistic (not
      // random-looking) arrangement to draw pieces from — the actual
      // difficulty control is the thinning step in _startStudyPhase, not
      // this move count.
      _setupMovesRemaining = 10 + _random.nextInt(11);
    });
    _playNextSetupMove();
  }

  void _playNextSetupMove() {
    if (_setupMovesRemaining <= 0 || game.game_over) {
      _startStudyPhase();
      return;
    }
    final engine = stockfish;
    if (engine == null || engine.state.value != StockfishState.ready) return;
    _awaitingSetupMove = true;
    engine.stdin = 'position fen ${game.fen}';
    engine.stdin = 'setoption name Skill Level value ${_random.nextInt(15)}';
    engine.stdin = 'go movetime 60';
  }

  void _onEngineOutput(String line) {
    if (!line.startsWith('bestmove') || !_awaitingSetupMove) return;
    _awaitingSetupMove = false;
    final parts = line.split(' ');
    if (parts.length < 2 || parts[1] == '(none)') {
      _startStudyPhase();
      return;
    }
    final uciMove = parts[1];
    final from = uciMove.substring(0, 2);
    final to = uciMove.substring(2, 4);
    final promotion = uciMove.length > 4 ? uciMove.substring(4, 5) : null;
    game.move({
      'from': from,
      'to': to,
      if (promotion != null) 'promotion': promotion,
    });
    _setupMovesRemaining--;
    _playNextSetupMove();
  }

  String _squareName(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);
    final rank = 8 - row;
    return '$file$rank';
  }

  int _squareIndex(int row, int col) => row * 8 + col;

  _PieceSpec? _specFor(chess_lib.Piece? piece) {
    if (piece == null) return null;
    final raw = piece.type.toString();
    final type = raw.contains('.') ? raw.split('.').last.toLowerCase()[0] : raw;
    return _PieceSpec(type, piece.color);
  }

  void _startStudyPhase() {
    // Snapshot every occupied square from the generated position, then
    // randomly thin it down to the level's target piece count — this is
    // what actually controls how much there is to remember. Kings are
    // always kept (a position missing a king reads as broken), everything
    // else is a random subset.
    final allSquares = <int, _PieceSpec>{};
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final piece = game.get(_squareName(row, col));
        final spec = _specFor(piece);
        if (spec != null) allSquares[_squareIndex(row, col)] = spec;
      }
    }
    final kingSquares =
        allSquares.entries.where((e) => e.value.type == 'k').map((e) => e.key).toList();
    final otherSquares =
        allSquares.entries.where((e) => e.value.type != 'k').map((e) => e.key).toList()
          ..shuffle(_random);
    final targetTotal = _targetPieceCountForLevel.clamp(2, allSquares.length);
    final keepCount = (targetTotal - kingSquares.length).clamp(0, otherSquares.length);
    final keptSquares = {...kingSquares, ...otherSquares.take(keepCount)};
    final key = <int, _PieceSpec>{
      for (final sq in keptSquares) sq: allSquares[sq]!,
    };

    setState(() {
      answerKey = key;
      phase = _MemoryPhase.studying;
      secondsLeft = studySecondsForLevel;
    });
    _studyTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => secondsLeft--);
      if (secondsLeft <= 0) {
        _studyTimer?.cancel();
        setState(() {
          phase = _MemoryPhase.placing;
          placed = {};
          selectedPaletteSpec = null;
        });
      }
    });
  }

  // Remaining palette entries: one button per (type,color) combo that
  // still has at least one un-placed instance, so the user places pieces
  // one at a time without needing to count "how many pawns are left" —
  // they just keep tapping the same button until it disappears.
  List<_PieceSpec> get _paletteSpecs {
    final remaining = <_PieceSpec, int>{};
    answerKey.forEach((_, spec) {
      remaining[spec] = (remaining[spec] ?? 0) + 1;
    });
    placed.forEach((_, spec) {
      if (remaining.containsKey(spec)) {
        remaining[spec] = remaining[spec]! - 1;
        if (remaining[spec]! <= 0) remaining.remove(spec);
      }
    });
    final specs = remaining.keys.toList();
    specs.sort((a, b) {
      const order = ['k', 'q', 'r', 'b', 'n', 'p'];
      final byType = order.indexOf(a.type).compareTo(order.indexOf(b.type));
      if (byType != 0) return byType;
      return a.color == chess_lib.Color.WHITE ? -1 : 1;
    });
    return specs;
  }

  void _onSquareTappedForPlacing(int index) {
    if (phase != _MemoryPhase.placing) return;
    setState(() {
      if (placed.containsKey(index)) {
        // Tapping an occupied square picks the piece back up (removes it),
        // so mistakes are easy to correct without a separate "clear" tool.
        placed.remove(index);
      } else if (selectedPaletteSpec != null) {
        placed[index] = selectedPaletteSpec!;
        // Auto-advance to the next available spec so repeated taps of the
        // same square type don't require re-selecting the palette button
        // every time (mirrors how the palette count naturally decreases).
        final stillAvailable = _paletteSpecs;
        selectedPaletteSpec =
            stillAvailable.contains(selectedPaletteSpec) ? selectedPaletteSpec : null;
      }
    });
  }

  void _submitPlacement() {
    int correct = 0;
    answerKey.forEach((index, spec) {
      if (placed[index] == spec) correct++;
    });
    final total = answerKey.length;
    final accuracy = total == 0 ? 1.0 : correct / total;
    final isPerfect = total > 0 && correct == total;
    _recordMemoryRound(levelReached: level);
    setState(() {
      correctCount = correct;
      phase = _MemoryPhase.results;
      // A strong round (80%+) advances the level for next time; anything
      // weaker just repeats the current level rather than dropping back
      // down, so a single rough round isn't punishing.
      if (accuracy >= 0.8 && level < maxLevel) {
        level++;
      }
      if (isPerfect) {
        perfectStreak++;
        if (perfectStreak > bestPerfectStreak) bestPerfectStreak = perfectStreak;
      } else {
        perfectStreak = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalPieces = answerKey.length;
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white70),
          title: const Text('Memory Training', style: TextStyle(color: Colors.white)),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  'Level $level / $maxLevel',
                  style: const TextStyle(fontSize: 13, color: Colors.white54),
                ),
                const SizedBox(height: 4),
                Text(
                  phase == _MemoryPhase.generating
                      ? 'Preparing position...'
                      : phase == _MemoryPhase.studying
                          ? 'Study the position — $secondsLeft s'
                          : phase == _MemoryPhase.placing
                              ? 'Place every piece back'
                              : (correctCount == totalPieces && totalPieces > 0
                                      ? 'Perfect! '
                                      : '') +
                                  'You placed $correctCount / $totalPieces correctly',
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
                if (phase == _MemoryPhase.results && perfectStreak >= 2) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9A94A).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD9A94A)),
                    ),
                    child: Text(
                      '🔥 $perfectStreak perfect rounds in a row!',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD9A94A),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
                      itemCount: 64,
                      itemBuilder: (context, index) {
                        final row = index ~/ 8;
                        final col = index % 8;
                        final isLight = (row + col) % 2 == 0;

                        _PieceSpec? spec;
                        if (phase == _MemoryPhase.studying ||
                            phase == _MemoryPhase.generating) {
                          spec = answerKey[index];
                        } else {
                          spec = placed[index];
                        }

                        Color squareColor =
                            isLight ? widget.boardTheme.lightSquare : widget.boardTheme.darkSquare;
                        if (phase == _MemoryPhase.results) {
                          final isCorrect =
                              answerKey.containsKey(index) && placed[index] == answerKey[index];
                          final wasAttempted = placed.containsKey(index);
                          final wasExpected = answerKey.containsKey(index);
                          if (wasExpected && isCorrect) {
                            squareColor = const Color(0xFF7FBF7F);
                          } else if (wasExpected || wasAttempted) {
                            squareColor = const Color(0xFFBF7F7F);
                          }
                        }

                        final glyphColor = spec?.color == chess_lib.Color.WHITE
                            ? const Color(0xFFF5F5F5)
                            : const Color(0xFF1B1F27);
                        final strokeColor = spec?.color == chess_lib.Color.WHITE
                            ? const Color(0xFF1B1F27)
                            : const Color(0xFFF5F5F5);

                        return GestureDetector(
                          onTap: () => _onSquareTappedForPlacing(index),
                          child: Container(
                            color: squareColor,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (spec != null && spec.type == 'p')
                                  _PawnShape(fillColor: glyphColor, strokeColor: strokeColor),
                                if (spec != null && spec.type != 'p')
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Text(
                                        spec.glyph,
                                        style: TextStyle(
                                          fontSize: 32,
                                          foreground: Paint()
                                            ..style = PaintingStyle.stroke
                                            ..strokeWidth = 2.2
                                            ..color = strokeColor,
                                        ),
                                      ),
                                      Text(
                                        spec.glyph,
                                        style: TextStyle(fontSize: 32, color: glyphColor),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (phase == _MemoryPhase.placing) ...[
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: _paletteSpecs.map((spec) {
                      final isSelected = selectedPaletteSpec == spec;
                      final glyphColor = spec.color == chess_lib.Color.WHITE
                          ? const Color(0xFFF5F5F5)
                          : const Color(0xFF1B1F27);
                      return GestureDetector(
                        onTap: () => setState(() => selectedPaletteSpec = spec),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isSelected ? kSelectedSquare : kPanelColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: spec.type == 'p'
                                ? _PawnShape(fillColor: glyphColor, strokeColor: Colors.white24)
                                : Text(
                                    spec.glyph,
                                    style: TextStyle(fontSize: 26, color: glyphColor),
                                  ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  _ActionButton(label: 'Submit', onPressed: _submitPlacement),
                ],
                if (phase == _MemoryPhase.results)
                  _ActionButton(label: 'Next Position', onPressed: _generateNewRound),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Shows lifetime and today's counts for games, puzzles, and memory
// training rounds — all sourced from AppStats/shared_preferences, no
// screen-specific state of its own beyond the loaded snapshot.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  AppStats? stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await _loadStats();
    if (mounted) setState(() => stats = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: const Text('Stats', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: s == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Today',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatCard(label: 'Games', value: '${s.todayGamesPlayed}'),
                        const SizedBox(width: 12),
                        _StatCard(label: 'Puzzles solved', value: '${s.todayPuzzlesSolved}'),
                        const SizedBox(width: 12),
                        _StatCard(label: 'Memory rounds', value: '${s.todayMemoryRounds}'),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'All time',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _StatCard(label: 'Games played', value: '${s.gamesPlayed}'),
                        _StatCard(label: 'Wins', value: '${s.wins}'),
                        _StatCard(label: 'Losses', value: '${s.losses}'),
                        _StatCard(label: 'Draws', value: '${s.draws}'),
                        _StatCard(
                          label: 'Puzzles solved',
                          value:
                              '${s.puzzlesSolved} / ${s.puzzlesAttempted}',
                        ),
                        _StatCard(label: 'Memory rounds', value: '${s.memoryRoundsPlayed}'),
                        _StatCard(label: 'Best memory level', value: '${s.memoryBestLevel} / 10'),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: kPanelColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class AnalysisScreen extends StatefulWidget {
  final List<String> fenHistory;
  final BoardTheme boardTheme;
  final PlayerColor playerColor;

  const AnalysisScreen({
    super.key,
    required this.fenHistory,
    this.boardTheme = BoardTheme.blueGray,
    this.playerColor = PlayerColor.white,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  int currentIndex = 0;
  Stockfish? stockfish;
  String evalText = 'Evaluating...';
  final Map<int, String> _evalCache = {};
  // Numeric centipawn eval per position (always from White's perspective),
  // used to classify move quality by comparing consecutive positions.
  // A very large number represents "mate for White", very negative "mate
  // for Black", so comparisons still behave sensibly near forced mates.
  final Map<int, int> _evalCpCache = {};
  bool _isBackgroundScanning = false;
  int _scanIndex = 0;
  // True while a 'go' is in flight for currentIndex specifically. The
  // background scanner must never issue its own 'position'+'go' while this
  // is true — Stockfish only tracks one search at a time, so a second 'go'
  // silently supersedes the first and its bestmove/eval never arrives,
  // which is what left the screen stuck on "Evaluating...".
  bool _foregroundEvalPending = false;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.fenHistory.length - 1;
    _scanIndex = currentIndex;
    _initEngine();
    // Fallback in case Stockfish never reaches ready at all (rather than
    // just being slow) — surfaces a clear message instead of spinning on
    // "Evaluating..." forever with no feedback.
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && evalText == 'Evaluating...' && !_evalCache.containsKey(currentIndex)) {
        setState(() => evalText = 'Engine unavailable — try reopening Analysis');
      }
    });
  }

  @override
  void dispose() {
    stockfish?.dispose();
    super.dispose();
  }

  Future<void> _initEngine() async {
    final engine = Stockfish();
    stockfish = engine;
    engine.stdout.listen(_onEngineOutput);
    _requestEval();
  }

  void _onEngineOutput(String line) {
    if (line.startsWith('info') && line.contains('score')) {
      final parsed = _parseScore(line);
      final cp = _parseScoreCp(line);
      if (parsed != null) {
        final targetIndex = _foregroundEvalPending ? currentIndex : _scanIndex;
        _evalCache[targetIndex] = parsed;
        if (cp != null) _evalCpCache[targetIndex] = cp;
        if (targetIndex == currentIndex) {
          setState(() => evalText = parsed);
        }
      }
    }
    if (line.startsWith('bestmove')) {
      if (_foregroundEvalPending) {
        _foregroundEvalPending = false;
        // Now that the position the user is looking at has resolved, it's
        // safe to let the background scanner send its own 'go' — starting
        // (or resuming) it here rather than in _requestEval avoids ever
        // having two searches in flight at once.
        if (!_isBackgroundScanning && _scanIndex < widget.fenHistory.length) {
          _isBackgroundScanning = true;
          _continueBackgroundScan();
        }
      } else if (_isBackgroundScanning) {
        _scanIndex++;
        _continueBackgroundScan();
      }
    }
  }

  String? _parseScore(String line) {
    final parts = line.split(' ');
    final scoreIdx = parts.indexOf('score');
    if (scoreIdx == -1 || scoreIdx + 2 >= parts.length) return null;
    final kind = parts[scoreIdx + 1]; // "cp" or "mate"
    final value = int.tryParse(parts[scoreIdx + 2]);
    if (value == null) return null;
    if (kind == 'mate') {
      return value > 0 ? 'Mate in $value' : 'Mate in ${-value} (for opponent)';
    }
    final pawns = value / 100.0;
    final sign = pawns >= 0 ? '+' : '';
    return '$sign${pawns.toStringAsFixed(2)}';
  }

  // Same parse as _parseScore but returns a plain centipawn integer
  // (always from White's point of view, since that's what Stockfish's UCI
  // "score cp" reports relative to the side to move — the sign is flipped
  // below at the call site depending on whose turn it was) so consecutive
  // positions can be compared numerically for move-quality classification.
  int? _parseScoreCp(String line) {
    final parts = line.split(' ');
    final scoreIdx = parts.indexOf('score');
    if (scoreIdx == -1 || scoreIdx + 2 >= parts.length) return null;
    final kind = parts[scoreIdx + 1];
    final value = int.tryParse(parts[scoreIdx + 2]);
    if (value == null) return null;
    if (kind == 'mate') {
      return value > 0 ? 100000 - value : -100000 - value;
    }
    return value;
  }

  void _requestEval() {
    final engine = stockfish;
    if (engine == null || engine.state.value != StockfishState.ready) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _requestEval();
      });
      return;
    }
    if (_evalCache.containsKey(currentIndex)) {
      setState(() => evalText = _evalCache[currentIndex]!);
      return;
    }
    // The position being viewed always takes priority over the background
    // scan — on long games, waiting for the scanner to reach currentIndex
    // on its own could take dozens of seconds (previously this just sat
    // waiting for the scan, which is what left Analysis stuck on
    // "Evaluating..." on long histories). _foregroundEvalPending tells
    // the scanner to hold off sending its own 'go' until this resolves.
    setState(() => evalText = 'Evaluating...');
    _foregroundEvalPending = true;
    engine.stdin = 'position fen ${widget.fenHistory[currentIndex]}';
    engine.stdin = 'go movetime 600';
  }

  void _continueBackgroundScan() {
    // Scan wraps around so positions before the starting index (usually
    // the game's final position) still get covered eventually, not just
    // the ones after it.
    if (_scanIndex >= widget.fenHistory.length) {
      _scanIndex = 0;
    }
    if (_evalCpCache.length >= widget.fenHistory.length) {
      _isBackgroundScanning = false;
      return;
    }
    if (_evalCpCache.containsKey(_scanIndex)) {
      _scanIndex++;
      _continueBackgroundScan();
      return;
    }
    // Never compete with a pending foreground request — it'll resume the
    // scan itself via _onEngineOutput once its own bestmove arrives.
    if (_foregroundEvalPending) return;
    final engine = stockfish;
    if (engine == null || engine.state.value != StockfishState.ready) {
      Future.delayed(const Duration(milliseconds: 300), _continueBackgroundScan);
      return;
    }
    engine.stdin = 'position fen ${widget.fenHistory[_scanIndex]}';
    engine.stdin = 'go movetime 300';
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.fenHistory.length) return;
    setState(() => currentIndex = index);
    _requestEval();
  }

  // Classifies the move that led FROM position (index-1) TO position
  // (index), by comparing eval swing from the mover's perspective. Returns
  // null if we don't have both evals yet (background scan still catching
  // up), so the UI can show nothing rather than a wrong guess.
  String? _symbolForMove(int index) {
    if (index <= 0) return null;
    final before = _evalCpCache[index - 1];
    final after = _evalCpCache[index];
    if (before == null || after == null) return null;
    // Position at (index-1) has White or Black to move; that side made the
    // move landing at (index). Swing is measured from that mover's side.
    final moverWasWhite =
        chess_lib.Chess.fromFEN(widget.fenHistory[index - 1]).turn ==
            chess_lib.Color.WHITE;
    // Only annotate the human's own moves — the engine's moves are
    // Stockfish playing itself, so grading them as "blunders" or
    // "brilliant" is meaningless noise, not useful feedback.
    final moverWasHuman = moverWasWhite == (widget.playerColor == PlayerColor.white);
    if (!moverWasHuman) return null;
    final beforeForMover = moverWasWhite ? before : -before;
    final afterForMover = moverWasWhite ? after : -after;
    final swing = afterForMover - beforeForMover;
    // Negative swing = position got worse for the mover after their own
    // move, i.e. they gave something up.
    if (swing <= -300) return '?? Blunder';
    if (swing <= -150) return '? Mistake';
    if (swing <= -50) return '?! Inaccuracy';
    if (swing >= 150) return '!! Brilliant';
    if (swing >= 50) return '! Good';
    return null; // roughly neutral — no marker needed
  }

  Color _colorForSymbol(String symbol) {
    if (symbol.startsWith('??')) return const Color(0xFFE05B5B);
    if (symbol.startsWith('?!')) return const Color(0xFFE0B85B);
    if (symbol.startsWith('?')) return const Color(0xFFE08A5B);
    if (symbol.startsWith('!!')) return const Color(0xFF5BC0E0);
    if (symbol.startsWith('!')) return const Color(0xFF6FE05B);
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final game = chess_lib.Chess.fromFEN(widget.fenHistory[currentIndex]);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            const Text(
              'Analysis',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Move ${currentIndex} of ${widget.fenHistory.length - 1}',
              style: const TextStyle(fontSize: 13, color: Colors.white38),
            ),
            const SizedBox(height: 12),
            // A tappable timeline of every human move's quality symbol, so
            // the whole game's pattern of blunders/good moves is visible
            // at a glance rather than having to step through one at a
            // time. Only human moves get a dot (see _symbolForMove), so
            // the strip naturally skips the engine's own replies.
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.fenHistory.length,
                itemBuilder: (context, index) {
                  final symbol = _symbolForMove(index);
                  final isCurrent = index == currentIndex;
                  final dotColor =
                      symbol != null ? _colorForSymbol(symbol) : Colors.white24;
                  return GestureDetector(
                    onTap: () => _goTo(index),
                    child: Container(
                      width: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: isCurrent ? kSelectedSquare : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Eval-over-time line chart — shows the overall shape of the
            // game (who was ahead when) at a glance, complementing the
            // per-move dots above with a continuous view of the swing.
            SizedBox(
              height: 70,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onTapDown: (details) {
                        final width = constraints.maxWidth;
                        if (width <= 0) return;
                        final fraction = details.localPosition.dx / width;
                        final index = (fraction * (widget.fenHistory.length - 1))
                            .round()
                            .clamp(0, widget.fenHistory.length - 1);
                        _goTo(index);
                      },
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _EvalChartPainter(
                          evalCpByIndex: _evalCpCache,
                          totalMoves: widget.fenHistory.length,
                          currentIndex: currentIndex,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              evalText,
              style: const TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final symbol = _symbolForMove(currentIndex);
              if (symbol == null) return const SizedBox(height: 20);
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _colorForSymbol(symbol).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _colorForSymbol(symbol)),
                ),
                child: Text(
                  symbol,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _colorForSymbol(symbol),
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _MiniBoard(
                  game: game,
                  boardTheme: widget.boardTheme,
                  playerColor: widget.playerColor,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  label: 'Prev',
                  onPressed: () => _goTo(currentIndex - 1),
                ),
                const SizedBox(width: 16),
                _ActionButton(
                  label: 'Next',
                  onPressed: () => _goTo(currentIndex + 1),
                ),
                const SizedBox(width: 16),
                _ActionButton(
                  label: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Draws a simple line chart of Stockfish eval (centipawns, White's
// perspective) across every position that's been scanned so far. Gaps
// (positions not yet evaluated by the background scan) are simply
// skipped when building the line rather than shown as zero, so the chart
// fills in progressively as Analysis keeps scanning in the background.
class _EvalChartPainter extends CustomPainter {
  final Map<int, int> evalCpByIndex;
  final int totalMoves;
  final int currentIndex;

  _EvalChartPainter({
    required this.evalCpByIndex,
    required this.totalMoves,
    required this.currentIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Midline (eval = 0) always drawn so "even" has a visible reference.
    final midlinePaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      midlinePaint,
    );

    if (totalMoves < 2 || evalCpByIndex.isEmpty) return;

    // Clamp extreme/mate evals so one blowout swing doesn't flatten the
    // rest of the chart into an unreadable line near the edges.
    const clampCp = 1000;
    double yFor(int cp) {
      final clamped = cp.clamp(-clampCp, clampCp);
      // cp > 0 (White ahead) draws higher (smaller y); cp < 0 draws lower.
      return size.height / 2 - (clamped / clampCp) * (size.height / 2 - 4);
    }

    double xFor(int index) => (index / (totalMoves - 1)) * size.width;

    final linePaint = Paint()
      ..color = kSelectedSquare
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    Path? path;
    for (int i = 0; i < totalMoves; i++) {
      final cp = evalCpByIndex[i];
      if (cp == null) continue; // not scanned yet — leave a gap
      final point = Offset(xFor(i), yFor(cp));
      if (path == null) {
        path = Path()..moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    if (path != null) canvas.drawPath(path, linePaint);

    // Marker for the position currently being viewed.
    final currentCp = evalCpByIndex[currentIndex];
    if (currentCp != null) {
      final markerPaint = Paint()..color = Colors.white;
      canvas.drawCircle(
        Offset(xFor(currentIndex), yFor(currentCp)),
        4,
        markerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EvalChartPainter oldDelegate) {
    return oldDelegate.evalCpByIndex.length != evalCpByIndex.length ||
        oldDelegate.currentIndex != currentIndex;
  }
}

// A read-only board renderer, reused by the Analysis screen so it doesn't
// share mutable state with the live game board.
class _MiniBoard extends StatelessWidget {
  final chess_lib.Chess game;
  final BoardTheme boardTheme;
  final PlayerColor playerColor;

  const _MiniBoard({
    required this.game,
    this.boardTheme = BoardTheme.blueGray,
    this.playerColor = PlayerColor.white,
  });

  String _squareName(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);
    final rank = 8 - row;
    return '$file$rank';
  }

  // Same flip convention as the live game board: when the human played
  // Black, the board is shown with Black at the bottom, matching what
  // they actually saw during the game — Analysis should never show the
  // position from the opposite side of how it was played.
  int _displayToLogicalRow(int displayRow) =>
      playerColor == PlayerColor.black ? 7 - displayRow : displayRow;
  int _displayToLogicalCol(int displayCol) =>
      playerColor == PlayerColor.black ? 7 - displayCol : displayCol;

  String? _glyphFor(chess_lib.Piece piece) {
    switch (piece.type.toString()) {
      case 'Piece.PAWN':
      case 'p':
        return null;
      case 'Piece.KNIGHT':
      case 'n':
        return '♞';
      case 'Piece.BISHOP':
      case 'b':
        return '♝';
      case 'Piece.ROOK':
      case 'r':
        return '♜';
      case 'Piece.QUEEN':
      case 'q':
        return '♛';
      case 'Piece.KING':
      case 'k':
        return '♚';
      default:
        return null;
    }
  }

  bool _isPawn(chess_lib.Piece piece) {
    final t = piece.type.toString();
    return t == 'Piece.PAWN' || t == 'p';
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemCount: 64,
      itemBuilder: (context, index) {
        final displayRow = index ~/ 8;
        final displayCol = index % 8;
        final row = _displayToLogicalRow(displayRow);
        final col = _displayToLogicalCol(displayCol);
        final isLight = (row + col) % 2 == 0;
        final piece = game.get(_squareName(row, col));

        Color? glyphColor;
        String? glyph;
        bool isPawnHere = false;
        if (piece != null) {
          final isWhite = piece.color == chess_lib.Color.WHITE;
          glyphColor =
              isWhite ? const Color(0xFFF5F5F5) : const Color(0xFF1B1F27);
          glyph = _glyphFor(piece);
          isPawnHere = _isPawn(piece);
        }
        final strokeColor = glyphColor == const Color(0xFFF5F5F5)
            ? const Color(0xFF1B1F27)
            : const Color(0xFFF5F5F5);

        return Container(
          color: isLight ? boardTheme.lightSquare : boardTheme.darkSquare,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isPawnHere)
                _PawnShape(
                  fillColor: glyphColor!,
                  strokeColor: strokeColor,
                ),
              if (glyph != null)
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      glyph,
                      style: TextStyle(
                        fontSize: 28,
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 2.0
                          ..color = strokeColor,
                      ),
                    ),
                    Text(
                      glyph,
                      style: TextStyle(fontSize: 28, color: glyphColor),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PawnShape extends StatelessWidget {
  final Color fillColor;
  final Color strokeColor;

  const _PawnShape({required this.fillColor, required this.strokeColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: CustomPaint(
        painter: _PawnPainter(fillColor: fillColor, strokeColor: strokeColor),
      ),
    );
  }
}

class _PawnPainter extends CustomPainter {
  final Color fillColor;
  final Color strokeColor;

  _PawnPainter({required this.fillColor, required this.strokeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final cx = size.width / 2;
    final headRadius = size.width * 0.17;
    final headCy = size.height * 0.32;

    // Base (trapezoid-ish body) as a rounded rect for simplicity.
    final baseRect = Rect.fromLTWH(
      cx - size.width * 0.24,
      size.height * 0.68,
      size.width * 0.48,
      size.height * 0.20,
    );
    final baseRRect =
        RRect.fromRectAndRadius(baseRect, Radius.circular(size.width * 0.06));

    // Body (neck tapering from head to base).
    final bodyPath = Path()
      ..moveTo(cx - size.width * 0.10, headCy + headRadius * 0.6)
      ..lineTo(cx - size.width * 0.20, size.height * 0.68)
      ..lineTo(cx + size.width * 0.20, size.height * 0.68)
      ..lineTo(cx + size.width * 0.10, headCy + headRadius * 0.6)
      ..close();

    canvas.drawPath(bodyPath, fill);
    canvas.drawPath(bodyPath, stroke);
    canvas.drawRRect(baseRRect, fill);
    canvas.drawRRect(baseRRect, stroke);
    canvas.drawCircle(Offset(cx, headCy), headRadius, fill);
    canvas.drawCircle(Offset(cx, headCy), headRadius, stroke);
  }

  @override
  bool shouldRepaint(covariant _PawnPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor;
  }
}

class _PromotionChoice extends StatelessWidget {
  final String glyph;
  final String label;
  final VoidCallback onTap;

  const _PromotionChoice({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text(glyph, style: const TextStyle(fontSize: 36, color: Colors.white)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _ClockDisplay extends StatelessWidget {
  final String label;
  final int seconds;
  final bool isActive;
  final String formatted;

  const _ClockDisplay({
    required this.label,
    required this.seconds,
    required this.isActive,
    required this.formatted,
  });

  @override
  Widget build(BuildContext context) {
    final isLow = seconds <= 30;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? kSelectedSquare : kPanelColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isActive ? Colors.white : Colors.white54,
            ),
          ),
          Text(
            formatted,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isLow ? const Color(0xFFE07A7A) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPanelColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
