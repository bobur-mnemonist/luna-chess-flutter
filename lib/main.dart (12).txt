import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:stockfish_flutter_plus/stockfish_flutter_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

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

Future<void> _saveGame({
  required String fen,
  required List<String> fenHistory,
  required Difficulty difficulty,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSavedFen, fen);
  await prefs.setStringList(_kSavedHistory, fenHistory);
  await prefs.setString(_kSavedDifficulty, difficulty.name);
}

Future<void> _clearSavedGame() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kSavedFen);
  await prefs.remove(_kSavedHistory);
  await prefs.remove(_kSavedDifficulty);
}

class SavedGame {
  final String fen;
  final List<String> fenHistory;
  final Difficulty difficulty;

  SavedGame({
    required this.fen,
    required this.fenHistory,
    required this.difficulty,
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
  return SavedGame(fen: fen, fenHistory: history, difficulty: difficulty);
}

void main() {
  runApp(const LunaChessApp());
}

enum Difficulty { easy, medium, hard }

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
  SavedGame? savedGame;
  bool checkedForSavedGame = false;

  @override
  void initState() {
    super.initState();
    _checkForSavedGame();
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
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) =>
                ChessBoardScreen(difficulty: selectedDifficulty),
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
              resumeFen: saved.fen,
              resumeHistory: saved.fenHistory,
            ),
          ),
        )
        .then((_) => _checkForSavedGame());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
              const Text(
                'Difficulty',
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              _DifficultyPicker(
                selected: selectedDifficulty,
                onChanged: (d) => setState(() => selectedDifficulty = d),
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

class ChessBoardScreen extends StatefulWidget {
  final Difficulty difficulty;
  final String? resumeFen;
  final List<String>? resumeHistory;

  const ChessBoardScreen({
    super.key,
    required this.difficulty,
    this.resumeFen,
    this.resumeHistory,
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

  Stockfish? stockfish;
  bool aiThinking = false;
  bool hintLoading = false;
  bool _awaitingHint = false;
  List<String> fenHistory = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  // The human always plays White; the engine plays Black.
  static const chess_lib.Color humanSide = chess_lib.Color.WHITE;

  @override
  void initState() {
    super.initState();
    // Use the standard media audio stream, which respects the device's
    // media volume the same way music/video apps do — more predictable
    // across devices than notification/sonification streams, which some
    // manufacturers route differently or mute by default.
    _audioPlayer.setPlayerMode(PlayerMode.lowLatency);
    _audioPlayer.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
      ),
    );
    if (widget.resumeFen != null) {
      game = chess_lib.Chess.fromFEN(widget.resumeFen!);
      fenHistory = List.of(widget.resumeHistory ?? [game.fen]);
      _updateStatus();
    } else {
      game = chess_lib.Chess();
      fenHistory = [game.fen];
    }
    _initEngine();
  }

  @override
  void dispose() {
    stockfish?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initEngine() async {
    final engine = Stockfish();
    stockfish = engine;
    engine.stdout.listen(_onEngineOutput);
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
      aiThinking = false;
      _updateStatus();
    });
    _playMoveSound(isCapture: isCapture);
  }

  void _maybeTriggerEngineMove() {
    if (game.turn == humanSide) return;
    if (game.game_over) return;
    final engine = stockfish;
    if (engine == null) return;
    if (engine.state.value != StockfishState.ready) return;

    setState(() => aiThinking = true);
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
        _makeMove(fromName, tappedSquareName);
        selectedSquareIndex = null;
        legalMoveTargets = [];
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

  void _makeMove(String from, String to) {
    // Check for a capture *before* making the move, since afterwards the
    // destination square holds our own piece.
    final isCapture = game.get(to) != null;
    // Auto-queen on promotion for now; a picker popup can be added later.
    game.move({'from': from, 'to': to, 'promotion': 'q'});
    fenHistory.add(game.fen);
    _playMoveSound(isCapture: isCapture);
    _updateStatus();
    _maybeTriggerEngineMove();
  }

  void _playMoveSound({bool isCapture = false}) {
    if (!soundOn) return;
    // Bundled short sound effects via audioplayers, more reliable across
    // devices than the system click sound (which some devices silence).
    // Check takes priority (most eventful), then capture, then a plain move.
    final String asset;
    if (game.in_check) {
      asset = 'audio/check.wav';
    } else if (isCapture) {
      asset = 'audio/capture.wav';
    } else {
      asset = 'audio/move.wav';
    }
    _audioPlayer.play(AssetSource(asset)).catchError((error) {
      // Surface playback errors in the status text temporarily so they're
      // visible on-device without needing a debugger attached.
      if (mounted) {
        setState(() => statusText = 'Audio error: $error');
      }
    });
  }

  void _updateStatus() {
    if (game.in_checkmate) {
      final winner = game.turn == chess_lib.Color.WHITE ? 'Black' : 'White';
      statusText = 'Checkmate — $winner wins';
      _clearSavedGame();
    } else if (game.in_stalemate) {
      statusText = 'Stalemate — draw';
      _clearSavedGame();
    } else if (game.in_draw) {
      statusText = 'Draw';
      _clearSavedGame();
    } else if (game.in_check) {
      final side = game.turn == chess_lib.Color.WHITE ? 'White' : 'Black';
      statusText = '$side is in check';
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
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
      if (parsed != null) {
        setState(() {
          evalText = parsed;
          _evalCache[currentIndex] = parsed;
        });
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
    setState(() => evalText = 'Evaluating...');
    engine.stdin = 'position fen ${widget.fenHistory[currentIndex]}';
    engine.stdin = 'go movetime 600';
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.fenHistory.length) return;
    setState(() => currentIndex = index);
    _requestEval();
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
            const SizedBox(height: 16),
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
