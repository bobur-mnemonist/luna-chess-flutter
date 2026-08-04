import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess_lib;

const kLightSquare = Color(0xFFBFCCDE);
const kDarkSquare = Color(0xFF4A5C75);
const kBackground = Color(0xFF1A1F29);
const kPanelColor = Color(0xFF29333F);
const kSelectedSquare = Color(0xFF6C8FBF);
const kLegalMoveDot = Color(0xB3FFFFFF);

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

  void _startGame() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChessBoardScreen(difficulty: selectedDifficulty),
      ),
    );
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
              _ActionButton(label: 'Start Game', onPressed: _startGame),
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

  const ChessBoardScreen({super.key, required this.difficulty});

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

  @override
  void initState() {
    super.initState();
    game = chess_lib.Chess();
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
    // Auto-queen on promotion for now; a picker popup can be added later.
    game.move({'from': from, 'to': to, 'promotion': 'q'});
    _updateStatus();
  }

  void _updateStatus() {
    if (game.in_checkmate) {
      final winner = game.turn == chess_lib.Color.WHITE ? 'Black' : 'White';
      statusText = 'Checkmate — $winner wins';
    } else if (game.in_stalemate) {
      statusText = 'Stalemate — draw';
    } else if (game.in_draw) {
      statusText = 'Draw';
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
    });
  }

  void _undo() {
    setState(() {
      game.undo_move();
      selectedSquareIndex = null;
      legalMoveTargets = [];
      _updateStatus();
    });
  }

  void _backToMenu() {
    Navigator.of(context).pop();
  }

  void _toggleSound() {
    setState(() => soundOn = !soundOn);
  }

  void _toggleVoice() {
    setState(() => voiceOn = !voiceOn);
  }

  // Shows a simple hint: highlights the from/to squares of the first legal
  // move available. Not engine-backed yet — that comes with the AI later.
  void _showHint() {
    final moves = game.moves({'verbose': true});
    if (moves.isEmpty) return;
    final move = moves.first;
    final fromName = move['from'] as String;
    final toName = move['to'] as String;

    int indexFromName(String name) {
      final col = name.codeUnitAt(0) - 'a'.codeUnitAt(0);
      final row = 8 - int.parse(name[1]);
      return squareIndex(row, col);
    }

    setState(() {
      hintFromIndex = indexFromName(fromName);
      hintToIndex = indexFromName(toName);
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
              statusText,
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
            const SizedBox(height: 24),
          ],
        ),
      ),
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
