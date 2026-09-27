import 'package:flutter/material.dart';

import '../constants.dart';

/// Ячейка-контейнер сетки: фиксированные размеры + рамка, чтобы колонки
/// поставщиков и фиксированная панель выстраивались в единую сетку.
class GridBox extends StatelessWidget {
  const GridBox({
    super.key,
    required this.width,
    required this.height,
    this.child,
    this.color,
    this.alignment = Alignment.centerLeft,
  });

  final double width;
  final double height;
  final Widget? child;
  final Color? color;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: alignment,
      decoration: BoxDecoration(
        color: color,
        border: const Border(
          left: kGridSide,
          right: kGridSide,
          top: kGridSide,
          bottom: kGridSide,
        ),
      ),
      child: child,
    );
  }
}