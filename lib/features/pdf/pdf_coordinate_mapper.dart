import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../measurements/models.dart';

/// Преобразование координат страницы PDF ↔ экран для режима single-page.
class PdfCoordinateMapper {
  PdfCoordinateMapper({
    required this.controller,
    required this.viewportSize,
    required this.pageSizes,
  });

  final PdfViewerController controller;
  final Size viewportSize;
  /// Ключ — номер страницы (1-based), как в Syncfusion.
  final Map<int, Size> pageSizes;

  double get zoomLevel => controller.zoomLevel;
  Offset get scrollOffset => controller.scrollOffset;

  Size? pageSizeForIndex(int pageIndex) => pageSizes[pageIndex + 1];

  Offset _letterboxOffset(Size pageSize) {
    final scaledWidth = pageSize.width * zoomLevel;
    final scaledHeight = pageSize.height * zoomLevel;
    return Offset(
      viewportSize.width > scaledWidth ? (viewportSize.width - scaledWidth) / 2 : 0,
      viewportSize.height > scaledHeight ? (viewportSize.height - scaledHeight) / 2 : 0,
    );
  }

  /// Нормализованные координаты линии (0..1) → экран.
  Offset pageNormToScreen(int pageIndex, double normX, double normY) {
    final pageSize = pageSizeForIndex(pageIndex);
    if (pageSize == null || viewportSize.isEmpty) {
      return Offset(normX * viewportSize.width, normY * viewportSize.height);
    }
    final pageX = normX * pageSize.width;
    final pageY = normY * pageSize.height;
    final letterbox = _letterboxOffset(pageSize);
    return Offset(
      (pageX - scrollOffset.dx) * zoomLevel + letterbox.dx,
      (pageY - scrollOffset.dy) * zoomLevel + letterbox.dy,
    );
  }

  /// Экран → нормализованные координаты страницы (0..1).
  Offset? screenToPageNorm(int pageIndex, Offset screen) {
    final pageSize = pageSizeForIndex(pageIndex);
    if (pageSize == null || viewportSize.isEmpty || zoomLevel == 0) return null;
    final letterbox = _letterboxOffset(pageSize);
    final pageX = (screen.dx - letterbox.dx) / zoomLevel + scrollOffset.dx;
    final pageY = (screen.dy - letterbox.dy) / zoomLevel + scrollOffset.dy;
    return Offset(
      (pageX / pageSize.width).clamp(0.0, 1.0),
      (pageY / pageSize.height).clamp(0.0, 1.0),
    );
  }

  /// PdfGestureDetails.pagePosition → нормализованные координаты.
  Offset pagePositionToNorm(PdfGestureDetails details) {
    final pageSize = pageSizes[details.pageNumber];
    if (pageSize == null || pageSize.width == 0 || pageSize.height == 0) {
      return Offset.zero;
    }
    return Offset(
      (details.pagePosition.dx / pageSize.width).clamp(0.0, 1.0),
      (details.pagePosition.dy / pageSize.height).clamp(0.0, 1.0),
    );
  }

  /// Для устаревших линий с coordSpace viewport — рисуем по старой схеме.
  Offset legacyToScreen(double normX, double normY) =>
      Offset(normX * viewportSize.width, normY * viewportSize.height);

  Offset lineStart(PdfLine line) {
    if (line.usesPageCoords) return pageNormToScreen(line.pageIndex, line.x1, line.y1);
    return legacyToScreen(line.x1, line.y1);
  }

  Offset lineEnd(PdfLine line) {
    if (line.usesPageCoords) return pageNormToScreen(line.pageIndex, line.x2, line.y2);
    return legacyToScreen(line.x2, line.y2);
  }
}