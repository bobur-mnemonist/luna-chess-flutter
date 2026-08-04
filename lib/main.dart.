import 'package:flutter/material.dart';

void main() {
  runApp(const LunaChessApp());
}

// ============================================
// Color palette (matches the old blue-gray board theme)
// ============================================
const Color kLightSquare = Color(0xFFBFCCDE);
const Color kDarkSquare = Color(0xFF4A5C75);
const Color kBackground = Color(0xFF1A1F29);
const Color kPanelColor = Color(0xFF29333F);

class LunaChessApp extends StatelessWidget {
  const LunaChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Luna Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: kBackground,
        fontFamily: 'Roboto',
      ),
      home: const ChessBoardScreen(),
    );
  }
}

class ChessBoardScreen extends StatelessWidget {
  const ChessBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            const Text(
              'Luna Chess',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _EmptyBoard(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Just draws the 8x8 checkerboard pattern for now — no pieces, no
/// interaction yet. This is step 1: confirm the visual layout works.
class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
      ),
      itemCount: 64,
      itemBuilder: (context, index) {
        final row = index ~/ 8;
        final col = index % 8;
        final isLight = (row + col) % 2 == 0;
        return Container(
          color: isLight ? kLightSquare : kDarkSquare,
        );
      },
    );
  }
}
