import 'package:flutter/material.dart';

/// Intrinsic-height tiles avoid fixed-height clipping at larger text scales.
class AkysResponsiveTiles extends StatelessWidget {
  const AkysResponsiveTiles({
    required this.children,
    this.minimumWidth = 140,
    this.maxColumns = 4,
    super.key,
  });
  final List<Widget> children;
  final double minimumWidth;
  final int maxColumns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      const gap = 12.0;
      final columns = MediaQuery.textScalerOf(context).scale(16) > 24
          ? 1
          : ((c.maxWidth + gap) / (minimumWidth + gap)).floor().clamp(
              1,
              maxColumns,
            );
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
