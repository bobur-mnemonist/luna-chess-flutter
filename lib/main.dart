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

class LunaChessApp extends StatelessWidget {
  const LunaChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Luna Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: kBackground),
      home: const ChessBoardScreen(),
    );
  }
}

class ChessBoardScreen extends StatefulWidget {
  const ChessBoardScreen({super.key});

  @override
  State<ChessBoardScreen> createState() => _ChessBoardScreenState();
}

class _ChessBoardScreenState extends State<ChessBoardScreen> {
  late chess_lib.Chess game;
  int? selectedSquareIndex; // 0-63, null if nothing selected
  List<int> legalMoveTargets = [];
  String statusText = "White's move";

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

  String? _pieceGlyph(int row, int col) {
    final piece = game.get(squareName(row, col));
    if (piece == null) return null;
    final isWhite = piece.color == chess_lib.Color.WHITE;
    switch (piece.type.toString()) {
      case 'Piece.PAWN':
      case 'p':
        return isWhite ? '♙' : '♟';
      case 'Piece.KNIGHT':
      case 'n':
        return isWhite ? '♘' : '♞';
      case 'Piece.BISHOP':
      case 'b':
        return isWhite ? '♗' : '♝';
      case 'Piece.ROOK':
      case 'r':
        return isWhite ? '♖' : '♜';
      case 'Piece.QUEEN':
      case 'q':
        return isWhite ? '♕' : '♛';
      case 'Piece.KING':
      case 'k':
        return isWhite ? '♔' : '♚';
      default:
        return null;
    }
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
            const SizedBox(height: 12),
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
                    final glyph = _pieceGlyph(row, col);

                    return GestureDetector(
                      onTap: () => onSquareTapped(row, col),
                      child: Container(
                        color: isSelected
                            ? kSelectedSquare
                            : (isLight ? kLightSquare : kDarkSquare),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (glyph != null)
                              Text(
                                glyph,
                                style: const TextStyle(fontSize: 32),
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
                _ActionButton(label: 'Undo', onPressed: _undo),
                const SizedBox(width: 16),
                _ActionButton(label: 'Restart', onPressed: _restart),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
