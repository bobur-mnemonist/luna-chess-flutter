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

// Keys used to persist an in-progress game so it can be resumed from the
// menu screen after leaving via "Save & Exit".
const _kSavedFen = 'saved_game_fen';
const _kSavedHistory = 'saved_game_fen_history';
const _kSavedDifficulty = 'saved_game_difficulty';
const _kSavedPlayerColor = 'saved_game_player_color';
const _kSavedWhiteClock = 'saved_game_white_clock';
const _kSavedBlackClock = 'saved_game_black_clock';

Future<void> _saveGame({
  required String fen,
  required List<String> fenHistory,
  required Difficulty difficulty,
  required PlayerColor playerColor,
  required int whiteClockSeconds,
  required int blackClockSeconds,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSavedFen, fen);
  await prefs.setStringList(_kSavedHistory, fenHistory);
  await prefs.setString(_kSavedDifficulty, difficulty.name);
  await prefs.setString(_kSavedPlayerColor, playerColor.name);
  await prefs.setInt(_kSavedWhiteClock, whiteClockSeconds);
  await prefs.setInt(_kSavedBlackClock, blackClockSeconds);
}

Future<void> _clearSavedGame() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kSavedFen);
  await prefs.remove(_kSavedHistory);
  await prefs.remove(_kSavedDifficulty);
  await prefs.remove(_kSavedPlayerColor);
  await prefs.remove(_kSavedWhiteClock);
  await prefs.remove(_kSavedBlackClock);
}

class SavedGame {
  final String fen;
  final List<String> fenHistory;
  final Difficulty difficulty;
  final PlayerColor playerColor;
  final int whiteClockSeconds;
  final int blackClockSeconds;

  SavedGame({
    required this.fen,
    required this.fenHistory,
    required this.difficulty,
    required this.playerColor,
    required this.whiteClockSeconds,
    required this.blackClockSeconds,
  });
}

Future<SavedGame?> _loadSavedGame() async {
  final prefs = await SharedPreferences.getInstance();
  final fen = prefs.getString(_kSavedFen);
  final history = prefs.getStringList(_kSavedHistory);
  final difficultyName = prefs.getString(_kSavedDifficulty);
  if (fen == null || history == null || difficultyName == null) return null;
  final difficulty = Difficulty.values.firstWhere(
    (d) => d.name == difficultyName,
    orElse: () => Difficulty.medium,
  );
  final colorName = prefs.getString(_kSavedPlayerColor);
  final playerColor = PlayerColor.values.firstWhere(
    (c) => c.name == colorName,
    orElse: () => PlayerColor.white,
  );
  final whiteClockSeconds = prefs.getInt(_kSavedWhiteClock) ?? 600;
  final blackClockSeconds = prefs.getInt(_kSavedBlackClock) ?? 600;
  return SavedGame(
    fen: fen,
    fenHistory: history,
    difficulty: difficulty,
    playerColor: playerColor,
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

enum Difficulty { easy, medium, hard }

enum PlayerColor { white, black }

class LunaChessApp extends StatelessWidget {
  const LunaChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Luna Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: kBackground),
      home: const MenuScreen(),
    );
  }
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Difficulty selectedDifficulty = Difficulty.medium;
  PlayerColor selectedColor = PlayerColor.white;
  SavedGame? savedGame;
  bool checkedForSavedGame = false;
  String? lunaLine;

  static final List<String> _greetings = [
    "Hi there! Ready for a game? 🙂",
    "Welcome back! Shall we play? ♟️",
    "Hello! Pick a difficulty and let's go. 👋",
    "Good to see you! What level today? 😊",
  ];

  @override
  void initState() {
    super.initState();
    _checkForSavedGame();
    lunaLine = _pickLine(_greetings);
  }

  Future<void> _checkForSavedGame() async {
    final saved = await _loadSavedGame();
    if (mounted) {
      setState(() {
        savedGame = saved;
        checkedForSavedGame = true;
        if (saved != null) {
          lunaLine = "You have a game in progress — want to continue?";
        }
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
          MaterialPageRoute(
            builder: (context) => ChessBoardScreen(
              difficulty: selectedDifficulty,
              playerColor: selectedColor,
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
          MaterialPageRoute(
            builder: (context) => ChessBoardScreen(
              difficulty: saved.difficulty,
              playerColor: saved.playerColor,
              resumeFen: saved.fen,
              resumeHistory: saved.fenHistory,
              resumeWhiteClockSeconds: saved.whiteClockSeconds,
              resumeBlackClockSeconds: saved.blackClockSeconds,
            ),
          ),
        )
        .then((_) => _checkForSavedGame());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      const SizedBox(height: 24),
                      LunaPanel(mood: 'idle', line: lunaLine, voiceOn: false),
                      const SizedBox(height: 24),
                      const Text(
                        'Difficulty',
                        style: TextStyle(fontSize: 18, color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      _DifficultyPicker(
                        selected: selectedDifficulty,
                        onChanged: (d) => setState(() => selectedDifficulty = d),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Play as',
                        style: TextStyle(fontSize: 18, color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      _ColorPicker(
                        selected: selectedColor,
                        onChanged: (c) => setState(() => selectedColor = c),
                      ),
                      const SizedBox(height: 48),
                      if (checkedForSavedGame && savedGame != null) ...[
                        _ActionButton(label: 'Continue Game', onPressed: _continueGame),
                        const SizedBox(height: 12),
                      ],
                      _ActionButton(label: 'Start New Game', onPressed: _startGame),
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

class _DifficultyPicker extends StatelessWidget {
  final Difficulty selected;
  final ValueChanged<Difficulty> onChanged;

  const _DifficultyPicker({required this.selected, required this.onChanged});

  String _label(Difficulty d) {
    switch (d) {
      case Difficulty.easy:
        return 'Easy';
      case Difficulty.medium:
        return 'Medium';
      case Difficulty.hard:
        return 'Hard';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: Difficulty.values.map((d) {
        final isSelected = d == selected;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: ChoiceChip(
            label: Text(_label(d)),
            selected: isSelected,
            onSelected: (_) => onChanged(d),
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

class _LunaPanelState extends State<LunaPanel> with TickerProviderStateMixin {
  late final AnimationController _blinkController;
  Timer? _blinkTimer;
  String? _lastSpokenLine;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    // A real blink is fast to close, brief to stay shut, and a touch slower
    // to reopen — a single linear controller reading both directions the
    // same way looks robotic, so closing/opening get separate easing below.
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scheduleNextBlink();
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

  void _scheduleNextBlink() {
    // Real blink intervals are irregular, roughly every 2.5–6.5s — a true
    // random draw each cycle instead of a near-fixed clock-derived delay.
    final randomDelay = 2500 + _random.nextInt(4000);
    _blinkTimer = Timer(Duration(milliseconds: randomDelay), () {
      if (!mounted) return;
      // Occasionally do a quick double-blink, like a real eye sometimes does.
      _blinkController.forward().then((_) {
        if (!mounted) return;
        _blinkController.reverse().then((_) {
          if (mounted && _random.nextDouble() < 0.15) {
            _blinkController.forward().then((_) {
              if (mounted) _blinkController.reverse();
            });
          }
        });
      });
      _scheduleNextBlink();
    });
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _blinkTimer?.cancel();
    super.dispose();
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
              child: AnimatedBuilder(
                animation: _blinkController,
                builder: (context, child) {
                  // Eased close/open instead of linear, and the squash
                  // amount eases too, so the lid motion doesn't feel
                  // mechanical.
                  final t =
                      Curves.easeInOutCubic.transform(_blinkController.value);
                  final blinkSquash = 1.0 - (t * 0.9);
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..scale(1.0, blinkSquash),
                    child: child,
                  );
                },
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
  final Difficulty difficulty;
  final PlayerColor playerColor;
  final String? resumeFen;
  final List<String>? resumeHistory;
  final int? resumeWhiteClockSeconds;
  final int? resumeBlackClockSeconds;

  const ChessBoardScreen({
    super.key,
    required this.difficulty,
    this.playerColor = PlayerColor.white,
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
  bool soundOn = true;
  bool voiceOn = true;
  int? hintFromIndex;
  int? hintToIndex;
  int? lastMoveFromIndex;
  int? lastMoveToIndex;
  int whiteClockSeconds = 600;
  int blackClockSeconds = 600;
  Timer? _clockTimer;

  Stockfish? stockfish;
  bool aiThinking = false;
  bool hintLoading = false;
  bool _awaitingHint = false;
  List<String> fenHistory = [];
  String? lunaLine;
  // Which side the human plays — set from the menu's color picker.
  chess_lib.Color get humanSide => widget.playerColor == PlayerColor.white
      ? chess_lib.Color.WHITE
      : chess_lib.Color.BLACK;

  static final List<String> _humanMoveLines = [
    "Nice move! 🙂",
    "Interesting... 🤔",
    "Let's see what you're planning. 👀",
    "Okay, my turn to think. 🧠",
    "Solid choice! 👍",
  ];
  static final List<String> _humanCaptureLines = [
    "Ooh, nice capture! 😮",
    "You took my piece! 😅",
    "That's a good grab. 👏",
  ];
  static final List<String> _humanKnightLines = [
    "Ooh, a knight hop! 🐴",
    "Knights are tricky — nice. 🐴✨",
  ];
  static final List<String> _humanBishopLines = [
    "Sliding across the diagonal! ✝️",
    "Nice bishop move. ✝️",
  ];
  static final List<String> _humanRookLines = [
    "Rook on the move! 🏰",
    "Straight down the line. 🏰",
  ];
  static final List<String> _humanQueenLines = [
    "Bringing out the queen! 👑",
    "Your queen is powerful there. 👑✨",
  ];
  static final List<String> _humanCastleLines = [
    "Castling — smart, tucking your king away. 🏯🛡️",
    "Nice, your king is safer now. 🛡️",
  ];
  static final List<String> _humanPromotionLines = [
    "A new queen is born! 👑✨",
    "Promotion! That's a big upgrade. 🎉",
  ];
  static final List<String> _engineMoveLines = [
    "There, my move. ♟️",
    "Let's see how you handle that. 😏",
    "Your turn again. 👉",
  ];
  static final List<String> _engineCaptureLines = [
    "Got one of yours! 😈",
    "I'll take that, thank you. 🙃",
    "Careful — I'm not holding back. ⚔️",
  ];
  static final List<String> _engineCastleLines = [
    "I'll castle here — my king is safe now. 🏯",
  ];
  static final List<String> _checkLines = [
    "Check! Watch your king. ⚠️👑",
    "Your king is in danger! 🚨",
  ];
  static final List<String> _humanWinLines = [
    "Checkmate! Well played, you win! 🏆🎉",
    "Wow, you got me! Great game. 👏😄",
  ];
  static final List<String> _engineWinLines = [
    "Checkmate! Good game though. 🏆",
    "I win this one — want a rematch? 😏🔁",
  ];
  static final List<String> _drawLines = [
    "A draw — well fought on both sides. 🤝",
    "Stalemate! Nobody wins this time. 😐",
  ];
  static final List<String> _thinkingLines = [
    "Hmm, let me think... 🤔",
    "Give me a moment... ⏳",
    "Analyzing the position... 🧠",
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
    if (isCapture) return _humanCaptureLines;
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
    if (isCapture) return _engineCaptureLines;
    return _engineMoveLines;
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
      whiteClockSeconds = widget.resumeWhiteClockSeconds ?? 600;
      blackClockSeconds = widget.resumeBlackClockSeconds ?? 600;
      _updateStatus();
    } else {
      game = chess_lib.Chess();
      fenHistory = [game.fen];
    }
    _initEngine();
    _startClock();
  }

  // Ticks once per second, deducting time from whichever side is currently
  // to move. Stops automatically once the game is over.
  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (game.game_over) {
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
          final winner = whiteClockSeconds == 0 ? 'Black' : 'White';
          statusText = '$winner wins on time';
          _clearSavedGame();
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

  // Maps the menu difficulty to a Stockfish "go" search budget. Movetime
  // (milliseconds) is simplest to reason about and keeps easy/medium quick.
  int _movetimeForDifficulty(Difficulty d) {
    switch (d) {
      case Difficulty.easy:
        return 200;
      case Difficulty.medium:
        return 800;
      case Difficulty.hard:
        return 2000;
    }
  }

  // Maps difficulty to Stockfish's UCI_LimitStrength / Skill Level so easy
  // mode actually plays weaker, not just "thinks less".
  int _skillLevelForDifficulty(Difficulty d) {
    switch (d) {
      case Difficulty.easy:
        return 2;
      case Difficulty.medium:
        return 10;
      case Difficulty.hard:
        return 20;
    }
  }

  void _onEngineOutput(String line) {
    if (line.startsWith('bestmove')) {
      final parts = line.split(' ');
      if (parts.length >= 2) {
        final uciMove = parts[1]; // e.g. "e2e4" or "e7e8q"
        if (_awaitingHint) {
          _awaitingHint = false;
          _applyHintMove(uciMove);
        } else {
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
    });
    _playMoveSound(isCapture: isCapture);
  }

  void _maybeTriggerEngineMove() {
    if (game.turn == humanSide) return;
    if (game.game_over) return;
    final engine = stockfish;
    if (engine == null) return;
    if (engine.state.value != StockfishState.ready) return;

    setState(() {
      aiThinking = true;
      lunaLine = _pickLine(_thinkingLines);
    });
    engine.stdin = 'position fen ${game.fen}';
    engine.stdin =
        'setoption name Skill Level value ${_skillLevelForDifficulty(widget.difficulty)}';
    engine.stdin = 'go movetime ${_movetimeForDifficulty(widget.difficulty)}';
  }

  // Convert (row, col) with row 0 = top of the visual board to the
  // algebraic square name the chess package expects, e.g. "e4".
  String squareName(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);
    final rank = 8 - row;
    return '$file$rank';
  }

  int squareIndex(int row, int col) => row * 8 + col;

  int _indexFromSquareName(String name) {
    final col = name.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final row = 8 - int.parse(name[1]);
    return squareIndex(row, col);
  }

  void onSquareTapped(int row, int col) {
    if (aiThinking) return;
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
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('Promote pawn to:', style: TextStyle(color: Colors.white)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _PromotionChoice(glyph: '♛', label: 'Queen', onTap: () => Navigator.of(dialogContext).pop('q')),
            _PromotionChoice(glyph: '♜', label: 'Rook', onTap: () => Navigator.of(dialogContext).pop('r')),
            _PromotionChoice(glyph: '♝', label: 'Bishop', onTap: () => Navigator.of(dialogContext).pop('b')),
            _PromotionChoice(glyph: '♞', label: 'Knight', onTap: () => Navigator.of(dialogContext).pop('n')),
          ],
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
    _maybeTriggerEngineMove();
  }

  void _playMoveSound({bool isCapture = false}) {
    if (!soundOn) return;
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
    } else if (game.in_stalemate) {
      statusText = 'Stalemate — draw';
      _clearSavedGame();
      lunaLine = _pickLine(_drawLines);
    } else if (game.in_draw) {
      statusText = 'Draw';
      _clearSavedGame();
      lunaLine = _pickLine(_drawLines);
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
      whiteClockSeconds = 600;
      blackClockSeconds = 600;
    });
    _startClock();
    _maybeTriggerEngineMove();
  }

  void _undo() {
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

  void _openAnalysis() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AnalysisScreen(fenHistory: List.of(fenHistory)),
      ),
    );
  }

  void _backToMenu() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kPanelColor,
        title: const Text('Leave game?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You can save your progress and continue later, or discard this game.',
          style: TextStyle(color: Colors.white70),
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
            child: const Text('Discard & Exit'),
          ),
          TextButton(
            onPressed: () async {
              await _saveGame(
                fen: game.fen,
                fenHistory: fenHistory,
                difficulty: widget.difficulty,
                playerColor: widget.playerColor,
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

  void _toggleSound() {
    setState(() => soundOn = !soundOn);
  }

  void _toggleVoice() {
    setState(() => voiceOn = !voiceOn);
  }

  void _showHint() {
    if (aiThinking || game.turn != humanSide) return;
    final engine = stockfish;
    if (engine == null || engine.state.value != StockfishState.ready) return;

    setState(() => hintLoading = true);
    _awaitingHint = true;
    engine.stdin = 'position fen ${game.fen}';
    engine.stdin = 'setoption name Skill Level value 20';
    engine.stdin = 'go movetime 500';
  }

  void _applyHintMove(String uciMove) {
    if (uciMove == '(none)') {
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

  String _difficultyLabel(Difficulty d) {
    switch (d) {
      case Difficulty.easy:
        return 'Easy';
      case Difficulty.medium:
        return 'Medium';
      case Difficulty.hard:
        return 'Hard';
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              _difficultyLabel(widget.difficulty),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ClockDisplay(
                  label: 'White',
                  seconds: whiteClockSeconds,
                  isActive: game.turn == chess_lib.Color.WHITE && !game.game_over,
                  formatted: _formatClock(whiteClockSeconds),
                ),
                _ClockDisplay(
                  label: 'Black',
                  seconds: blackClockSeconds,
                  isActive: game.turn == chess_lib.Color.BLACK && !game.game_over,
                  formatted: _formatClock(blackClockSeconds),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                    final row = index ~/ 8;
                    final col = index % 8;
                    final isLight = (row + col) % 2 == 0;
                    final isSelected = selectedSquareIndex == index;
                    final isLegalTarget = legalMoveTargets.contains(index);
                    final isHintSquare =
                        index == hintFromIndex || index == hintToIndex;
                    final isLastMoveSquare =
                        index == lastMoveFromIndex || index == lastMoveToIndex;
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
                                    : (isLight ? kLightSquare : kDarkSquare),
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
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(label: 'Menu', onPressed: _backToMenu),
                const SizedBox(width: 16),
                _ActionButton(label: 'Undo', onPressed: _undo),
                const SizedBox(width: 16),
                _ActionButton(label: 'Restart', onPressed: _restart),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(label: 'Hint', onPressed: _showHint),
                const SizedBox(width: 16),
                _ActionButton(
                  label: soundOn ? 'SFX: On' : 'SFX: Off',
                  onPressed: _toggleSound,
                ),
                const SizedBox(width: 16),
                _ActionButton(
                  label: voiceOn ? 'Voice: On' : 'Voice: Off',
                  onPressed: _toggleVoice,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Analysis',
              onPressed: fenHistory.length > 1 ? _openAnalysis : () {},
            ),
            const SizedBox(height: 24),
          ],
          ),
        ),
      ),
    );
  }
}

class AnalysisScreen extends StatefulWidget {
  final List<String> fenHistory;

  const AnalysisScreen({super.key, required this.fenHistory});

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

  @override
  void initState() {
    super.initState();
    currentIndex = widget.fenHistory.length - 1;
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
    _requestEval();
  }

  void _onEngineOutput(String line) {
    if (line.startsWith('info') && line.contains('score')) {
      final parsed = _parseScore(line);
      final cp = _parseScoreCp(line);
      if (parsed != null) {
        final targetIndex = _isBackgroundScanning ? _scanIndex : currentIndex;
        _evalCache[targetIndex] = parsed;
        if (cp != null) _evalCpCache[targetIndex] = cp;
        if (targetIndex == currentIndex) {
          setState(() => evalText = parsed);
        }
      }
    }
    if (line.startsWith('bestmove') && _isBackgroundScanning) {
      _scanIndex++;
      _continueBackgroundScan();
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
    } else {
      setState(() => evalText = 'Evaluating...');
      engine.stdin = 'position fen ${widget.fenHistory[currentIndex]}';
      engine.stdin = 'go movetime 600';
    }
    // Kick off (or continue) a background scan of every position so move
    // markers can be shown without the user having to visit each one.
    if (!_isBackgroundScanning && _scanIndex < widget.fenHistory.length) {
      _isBackgroundScanning = true;
      _continueBackgroundScan();
    }
  }

  void _continueBackgroundScan() {
    if (_scanIndex >= widget.fenHistory.length) {
      _isBackgroundScanning = false;
      return;
    }
    if (_evalCpCache.containsKey(_scanIndex)) {
      _scanIndex++;
      _continueBackgroundScan();
      return;
    }
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
                child: _MiniBoard(game: game),
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

// A read-only board renderer, reused by the Analysis screen so it doesn't
// share mutable state with the live game board.
class _MiniBoard extends StatelessWidget {
  final chess_lib.Chess game;

  const _MiniBoard({required this.game});

  String _squareName(int row, int col) {
    final file = String.fromCharCode('a'.codeUnitAt(0) + col);
    final rank = 8 - row;
    return '$file$rank';
  }

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
        final row = index ~/ 8;
        final col = index % 8;
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
          color: isLight ? kLightSquare : kDarkSquare,
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
