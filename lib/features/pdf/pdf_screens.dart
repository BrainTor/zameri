import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../measurements/app_state.dart';
import '../measurements/models.dart';
import '../rangefinder/rangefinder.dart';
import 'pdf_coordinate_mapper.dart';

Future<void> pickProjectPdf(BuildContext context, String projectId) async {
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final file = result?.files.single;
    final path = file?.path;
    if (file == null || path == null || !context.mounted) return;
    await context.read<AppState>().importPdf(projectId, path, file.name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF загружен')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить PDF: $error')),
      );
    }
  }
}

ProjectPdf? _primaryPdf(Project project) =>
    project.pdfs.isEmpty ? null : project.pdfs.first;

enum _PdfMarkupMode { draw, edit }

enum _LineDragHandle { start, end, body }

class _LineDragSession {
  const _LineDragSession({
    required this.lineId,
    required this.handle,
    required this.origin,
    required this.startX1,
    required this.startY1,
    required this.startX2,
    required this.startY2,
  });

  final String lineId;
  final _LineDragHandle handle;
  final Offset origin;
  final double startX1;
  final double startY1;
  final double startX2;
  final double startY2;
}

double _distanceToSegment(Offset point, Offset start, Offset end) {
  final ab = end - start;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (point - start).distance;
  final t = ((point.dx - start.dx) * ab.dx + (point.dy - start.dy) * ab.dy) / lengthSquared;
  final clamped = t.clamp(0.0, 1.0);
  final closest = Offset(start.dx + ab.dx * clamped, start.dy + ab.dy * clamped);
  return (point - closest).distance;
}

class PdfMarkupScreen extends StatefulWidget {
  const PdfMarkupScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<PdfMarkupScreen> createState() => _PdfMarkupScreenState();
}

class _PdfMarkupScreenState extends State<PdfMarkupScreen> {
  final PdfViewerController _controller = PdfViewerController();
  int _pageIndex = 0;
  int _pageCount = 0;
  _PdfMarkupMode _mode = _PdfMarkupMode.draw;
  String? _selectedLineId;
  Offset? _draftStart;
  Offset? _draftEnd;
  _LineDragSession? _dragSession;
  PdfLine? _dragPreview;
  bool _legacyWarningShown = false;

  PdfLine? _lineById(ProjectPdf pdf, String id) {
    for (final line in pdf.lines) {
      if (line.id == id) return line;
    }
    return null;
  }

  PdfLine _displayLine(PdfLine line) {
    if (_dragPreview?.id == line.id) return _dragPreview!;
    return line;
  }

  void _maybeShowLegacyWarning(ProjectPdf pdf) {
    if (_legacyWarningShown || !pdf.hasLegacyViewportLines) return;
    _legacyWarningShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Старые линии привязаны к экрану — переразметьте их на PDF'),
          duration: Duration(seconds: 5),
        ),
      );
    });
  }

  Future<void> _handleDrawTap(Offset norm, int pageIndex) async {
    if (pageIndex != _pageIndex) return;
    if (_draftStart == null) {
      setState(() {
        _draftStart = norm;
        _draftEnd = null;
      });
      return;
    }

    setState(() => _draftEnd = norm);
    final name = await _askLineName(context, 'Линия ${_lineCount() + 1}');
    if (!mounted) {
      setState(() {
        _draftStart = null;
        _draftEnd = null;
      });
      return;
    }
    if (name == null || name.trim().isEmpty) {
      setState(() {
        _draftStart = null;
        _draftEnd = null;
      });
      return;
    }

    final pdf = _primaryPdf(context.read<AppState>().projectById(widget.projectId));
    if (pdf == null) return;

    await context.read<AppState>().addPdfLine(
          widget.projectId,
          pdf.id,
          pageIndex: _pageIndex,
          x1: _draftStart!.dx,
          y1: _draftStart!.dy,
          x2: _draftEnd!.dx,
          y2: _draftEnd!.dy,
          name: name.trim(),
        );
    if (mounted) {
      setState(() {
        _draftStart = null;
        _draftEnd = null;
      });
    }
  }

  PdfLine? _hitTestLine(
    ProjectPdf pdf,
    PdfCoordinateMapper mapper,
    Offset screenPoint,
  ) {
    PdfLine? closest;
    var closestDistance = double.infinity;
    for (final line in pdf.lines.where((item) => item.pageIndex == _pageIndex)) {
      final start = mapper.lineStart(line);
      final end = mapper.lineEnd(line);
      final distance = _distanceToSegment(screenPoint, start, end);
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = line;
      }
    }
    if (closest == null || closestDistance > 28) return null;
    return closest;
  }

  _LineDragHandle? _hitTestHandle(PdfCoordinateMapper mapper, PdfLine line, Offset screenPoint) {
    final start = mapper.lineStart(line);
    final end = mapper.lineEnd(line);
    if ((screenPoint - start).distance < 36) return _LineDragHandle.start;
    if ((screenPoint - end).distance < 36) return _LineDragHandle.end;
    if (_distanceToSegment(screenPoint, start, end) < 28) return _LineDragHandle.body;
    return null;
  }

  void _beginEditDrag(Offset screenPoint, PdfCoordinateMapper mapper, ProjectPdf pdf) {
    final line = _hitTestLine(pdf, mapper, screenPoint);
    if (line == null) {
      setState(() => _selectedLineId = null);
      return;
    }
    final handle = _hitTestHandle(mapper, line, screenPoint);
    if (handle == null) {
      setState(() => _selectedLineId = line.id);
      return;
    }
    final norm = mapper.screenToPageNorm(_pageIndex, screenPoint) ?? Offset(line.x1, line.y1);
    setState(() {
      _selectedLineId = line.id;
      _dragSession = _LineDragSession(
        lineId: line.id,
        handle: handle,
        origin: norm,
        startX1: line.x1,
        startY1: line.y1,
        startX2: line.x2,
        startY2: line.y2,
      );
      _dragPreview = line;
    });
  }

  void _updateEditDrag(Offset screenPoint, PdfCoordinateMapper mapper, ProjectPdf pdf) {
    final session = _dragSession;
    if (session == null) return;
    final current = mapper.screenToPageNorm(_pageIndex, screenPoint);
    if (current == null) return;

    final delta = current - session.origin;
    late double x1;
    late double y1;
    late double x2;
    late double y2;
    switch (session.handle) {
      case _LineDragHandle.start:
        x1 = (session.startX1 + delta.dx).clamp(0.0, 1.0);
        y1 = (session.startY1 + delta.dy).clamp(0.0, 1.0);
        x2 = session.startX2;
        y2 = session.startY2;
      case _LineDragHandle.end:
        x1 = session.startX1;
        y1 = session.startY1;
        x2 = (session.startX2 + delta.dx).clamp(0.0, 1.0);
        y2 = (session.startY2 + delta.dy).clamp(0.0, 1.0);
      case _LineDragHandle.body:
        x1 = (session.startX1 + delta.dx).clamp(0.0, 1.0);
        y1 = (session.startY1 + delta.dy).clamp(0.0, 1.0);
        x2 = (session.startX2 + delta.dx).clamp(0.0, 1.0);
        y2 = (session.startY2 + delta.dy).clamp(0.0, 1.0);
    }

    final original = _lineById(pdf, session.lineId);
    if (original == null) return;
    setState(() => _dragPreview = original.copyWith(x1: x1, y1: y1, x2: x2, y2: y2));
  }

  Future<void> _finishEditDrag(ProjectPdf pdf) async {
    final preview = _dragPreview;
    final session = _dragSession;
    if (session == null) return;
    if (preview != null) {
      await context.read<AppState>().updatePdfLineGeometry(
            widget.projectId,
            pdf.id,
            preview.id,
            x1: preview.x1,
            y1: preview.y1,
            x2: preview.x2,
            y2: preview.y2,
          );
    }
    if (mounted) {
      setState(() {
        _dragSession = null;
        _dragPreview = null;
      });
    }
  }

  void _handleEditTap(Offset screenPoint, PdfCoordinateMapper mapper, ProjectPdf pdf) {
    final line = _hitTestLine(pdf, mapper, screenPoint);
    setState(() => _selectedLineId = line?.id);
  }

  Future<void> _renameSelectedLine(ProjectPdf pdf) async {
    final line = _selectedLineId == null ? null : _lineById(pdf, _selectedLineId!);
    if (line == null) return;
    final name = await _askLineName(context, line.name);
    if (name == null || name.trim().isEmpty || !mounted) return;
    await context.read<AppState>().updatePdfLineName(
          widget.projectId,
          pdf.id,
          line.id,
          name.trim(),
        );
  }

  Future<void> _deleteSelectedLine(ProjectPdf pdf) async {
    final line = _selectedLineId == null ? null : _lineById(pdf, _selectedLineId!);
    if (line == null) return;
    final confirmed = await _confirmDelete(context, 'Удалить линию «${line.name}»?');
    if (!confirmed || !mounted) return;
    await context.read<AppState>().deletePdfLine(widget.projectId, pdf.id, line.id);
    if (mounted) setState(() => _selectedLineId = null);
  }

  String _modeHint() {
    return switch (_mode) {
      _PdfMarkupMode.draw => _draftStart == null
          ? 'Нажмите начало линии на PDF, затем конец'
          : 'Нажмите конец линии на PDF',
      _PdfMarkupMode.edit => _selectedLineId == null
          ? 'Выберите линию. Тяните концы — длина, центр — перемещение'
          : 'Тяните маркеры или перемещайте линию целиком',
    };
  }

  int _lineCount() {
    final pdf = _primaryPdf(context.read<AppState>().projectById(widget.projectId));
    return pdf?.lines.length ?? 0;
  }

  void _goToPage(int index) {
    if (index < 0 || (_pageCount > 0 && index >= _pageCount)) return;
    _controller.jumpToPage(index + 1);
    setState(() {
      _pageIndex = index;
      _draftStart = null;
      _draftEnd = null;
      _dragSession = null;
      _dragPreview = null;
    });
  }

  Future<void> _showPagePicker(ProjectPdf pdf) async {
    final pagesWithLines = pdf.lines.map((line) => line.pageIndex).toSet();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        var onlyWithLines = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final total = _pageCount > 0 ? _pageCount : pdf.pageCount;
            final pages = List.generate(total, (index) => index)
                .where((index) => !onlyWithLines || pagesWithLines.contains(index))
                .toList();
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Выбор страницы',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Только страницы с линиями'),
                      value: onlyWithLines,
                      onChanged: (value) => setSheetState(() => onlyWithLines = value),
                    ),
                    Flexible(
                      child: GridView.builder(
                        shrinkWrap: true,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.4,
                        ),
                        itemCount: pages.length,
                        itemBuilder: (context, index) {
                          final page = pages[index];
                          final selected = page == _pageIndex;
                          final hasLines = pagesWithLines.contains(page);
                          return OutlinedButton(
                            onPressed: () {
                              _goToPage(page);
                              Navigator.pop(context);
                            },
                            style: OutlinedButton.styleFrom(
                              backgroundColor: selected
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : null,
                              side: hasLines
                                  ? BorderSide(color: Theme.of(context).colorScheme.primary)
                                  : null,
                            ),
                            child: Text('${page + 1}'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showLinesSheet(ProjectPdf pdf) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          final lines = context.watch<AppState>().pdfById(
                context.read<AppState>().projectById(widget.projectId),
                pdf.id,
              )?.sortedLines ??
              pdf.sortedLines;
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Линии маршрута (${lines.length})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: lines.isEmpty
                      ? const Center(child: Text('Добавьте линии на PDF'))
                      : ReorderableListView.builder(
                          scrollController: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                          itemCount: lines.length,
                          onReorder: (oldIndex, newIndex) => context
                              .read<AppState>()
                              .reorderPdfLines(widget.projectId, pdf.id, oldIndex, newIndex),
                          itemBuilder: (context, index) {
                            final line = lines[index];
                            return ListTile(
                              key: ValueKey(line.id),
                              leading: CircleAvatar(child: Text('${index + 1}')),
                              title: Text(line.name),
                              subtitle: Text(
                                'Стр. ${line.pageIndex + 1}'
                                '${line.measurementMm == null ? '' : ' · ${line.measurementMm} мм'}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      final name = await _askLineName(context, line.name);
                                      if (name == null || name.trim().isEmpty || !context.mounted) {
                                        return;
                                      }
                                      await context.read<AppState>().updatePdfLineName(
                                            widget.projectId,
                                            pdf.id,
                                            line.id,
                                            name.trim(),
                                          );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      final confirmed = await _confirmDelete(
                                        context,
                                        'Удалить линию «${line.name}»?',
                                      );
                                      if (!confirmed || !context.mounted) return;
                                      await context.read<AppState>().deletePdfLine(
                                            widget.projectId,
                                            pdf.id,
                                            line.id,
                                          );
                                    },
                                  ),
                                  const Icon(Icons.drag_handle),
                                ],
                              ),
                              onTap: () {
                                _goToPage(line.pageIndex);
                                setState(() {
                                  _mode = _PdfMarkupMode.edit;
                                  _selectedLineId = line.id;
                                });
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = context.watch<AppState>().projectById(widget.projectId);
    final pdf = _primaryPdf(project);
    if (pdf != null) _maybeShowLegacyWarning(pdf);

    final totalPages = _pageCount > 0 ? _pageCount : pdf?.pageCount ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF разметка'),
        actions: [
          if (pdf != null) ...[
            IconButton(
              tooltip: 'Заменить PDF',
              onPressed: () => pickProjectPdf(context, widget.projectId),
              icon: const Icon(Icons.upload_file),
            ),
            if (pdf.lines.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PdfRouteRunScreen(projectId: widget.projectId),
                  ),
                ),
                child: const Text('Маршрут'),
              ),
            TextButton(
              onPressed: () => _showLinesSheet(pdf),
              child: Text('${pdf.lines.length} линий'),
            ),
          ],
        ],
      ),
      body: pdf == null
          ? const _PdfPlaceholder(
              icon: Icons.picture_as_pdf_outlined,
              text: 'Загрузите PDF-чертёж для разметки линий',
            )
          : Column(
              children: [
                _PdfPageToolbar(
                  pageIndex: _pageIndex,
                  pageCount: totalPages,
                  onPrevious: _pageIndex > 0 ? () => _goToPage(_pageIndex - 1) : null,
                  onNext: totalPages > 0 && _pageIndex < totalPages - 1
                      ? () => _goToPage(_pageIndex + 1)
                      : null,
                  onPickPage: totalPages > 0 ? () => _showPagePicker(pdf) : null,
                ),
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<_PdfMarkupMode>(
                          segments: const [
                            ButtonSegment(
                              value: _PdfMarkupMode.draw,
                              icon: Icon(Icons.edit_outlined),
                              label: Text('Рисовать'),
                            ),
                            ButtonSegment(
                              value: _PdfMarkupMode.edit,
                              icon: Icon(Icons.open_with),
                              label: Text('Правка'),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (selection) {
                            setState(() {
                              _mode = selection.first;
                              _draftStart = null;
                              _draftEnd = null;
                              _dragSession = null;
                              _dragPreview = null;
                              if (_mode != _PdfMarkupMode.edit) {
                                _selectedLineId = null;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _mode == _PdfMarkupMode.draw
                                  ? Icons.edit_outlined
                                  : Icons.open_with,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_modeHint(), style: Theme.of(context).textTheme.bodyMedium),
                            ),
                            if (_mode == _PdfMarkupMode.draw && _draftStart != null)
                              TextButton(
                                onPressed: () => setState(() {
                                  _draftStart = null;
                                  _draftEnd = null;
                                }),
                                child: const Text('Отмена'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_mode == _PdfMarkupMode.edit && _selectedLineId != null)
                  Material(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _lineById(pdf, _selectedLineId!)?.name ?? 'Линия',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Переименовать',
                            onPressed: () => _renameSelectedLine(pdf),
                            icon: const Icon(Icons.drive_file_rename_outline),
                          ),
                          IconButton(
                            tooltip: 'Удалить',
                            onPressed: () => _deleteSelectedLine(pdf),
                            icon: const Icon(Icons.delete_outline),
                          ),
                          IconButton(
                            tooltip: 'Снять выделение',
                            onPressed: () => setState(() => _selectedLineId = null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _PdfInteractiveCanvas(
                    pdf: pdf,
                    projectId: widget.projectId,
                    controller: _controller,
                    pageIndex: _pageIndex,
                    mode: _PdfCanvasMode.markup,
                    markupMode: _mode,
                    selectedLineId: _selectedLineId,
                    draftStart: _draftStart,
                    draftEnd: _draftEnd,
                    displayLine: _displayLine,
                    onPageChanged: (index) => setState(() {
                      _pageIndex = index;
                      _draftStart = null;
                      _draftEnd = null;
                      _dragSession = null;
                      _dragPreview = null;
                    }),
                    onPageCountLoaded: (count) async {
                      if (_pageCount == count) return;
                      setState(() => _pageCount = count);
                      await context.read<AppState>().setPdfPageCount(
                            widget.projectId,
                            pdf.id,
                            count,
                          );
                    },
                    onDrawTap: _handleDrawTap,
                    onEditTap: (screen, mapper) => _handleEditTap(screen, mapper, pdf),
                    onEditDragStart: (screen, mapper) => _beginEditDrag(screen, mapper, pdf),
                    onEditDragUpdate: (screen, mapper) => _updateEditDrag(screen, mapper, pdf),
                    onEditDragEnd: () => _finishEditDrag(pdf),
                  ),
                ),
              ],
            ),
      floatingActionButton: pdf == null
          ? FloatingActionButton.extended(
              onPressed: () => pickProjectPdf(context, widget.projectId),
              icon: const Icon(Icons.upload_file),
              label: const Text('Загрузить PDF'),
            )
          : FloatingActionButton.extended(
              heroTag: 'pdf-lines',
              onPressed: () => _showLinesSheet(pdf),
              icon: const Icon(Icons.format_list_numbered),
              label: const Text('Список линий'),
            ),
    );
  }
}

class PdfRouteRunScreen extends StatefulWidget {
  const PdfRouteRunScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<PdfRouteRunScreen> createState() => _PdfRouteRunScreenState();
}

class _PdfRouteRunScreenState extends State<PdfRouteRunScreen> {
  final PdfViewerController _controller = PdfViewerController();
  int _pageIndex = 0;
  int _pageCount = 0;
  StreamSubscription<RangefinderReading>? _readingSub;
  String? _armedLineId;
  String? _trackedLineId;
  DateTime _armedAt = DateTime.now();
  bool _busy = false;
  int? _lastAppliedValue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureAutoMode();
    });
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    super.dispose();
  }

  ProjectPdf? _currentPdf() {
    final project = context.read<AppState>().projectById(widget.projectId);
    return _primaryPdf(project);
  }

  void _goToPage(int index) {
    if (index < 0 || (_pageCount > 0 && index >= _pageCount)) return;
    _controller.jumpToPage(index + 1);
    setState(() => _pageIndex = index);
  }

  Future<void> _ensureAutoMode() async {
    final pdf = _currentPdf();
    final line = pdf?.currentLine;
    if (pdf == null || line == null || pdf.isRouteComplete || line.isComplete) {
      _readingSub?.cancel();
      _readingSub = null;
      return;
    }

    if (_pageIndex != line.pageIndex) {
      _controller.jumpToPage(line.pageIndex + 1);
      setState(() => _pageIndex = line.pageIndex);
    }

    if (_armedLineId != line.id) {
      _armedLineId = line.id;
      _armedAt = DateTime.now();
      _lastAppliedValue = null;
    }

    _readingSub ??= context.read<RangefinderController>().readings.listen(_onReading);

    final rangefinder = context.read<RangefinderController>();
    if (rangefinder.status != RangefinderStatus.connected && !rangefinder.testMode) {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => const _PdfRangefinderScreen()),
      );
      if (!mounted) return;
    }
    if (rangefinder.status == RangefinderStatus.connected || rangefinder.testMode) {
      unawaited(
        rangefinder.requestMeasurement(
          onBluetoothOff: () => _promptEnableBluetooth(context),
        ),
      );
      if (rangefinder.testMode) {
        unawaited(
          rangefinder.captureNext(
            timeout: const Duration(seconds: 3),
            requestShot: true,
            onBluetoothOff: () => _promptEnableBluetooth(context),
          ),
        );
      }
    }
  }

  Future<void> _onReading(RangefinderReading reading) async {
    if (_busy) return;
    if (reading.timestamp.isBefore(_armedAt)) return;
    if (DateTime.now().difference(_armedAt) < const Duration(milliseconds: 800)) return;
    if (_lastAppliedValue == reading.valueMm) return;

    final pdf = _currentPdf();
    final line = pdf?.currentLine;
    if (pdf == null || line == null || line.isComplete || pdf.isRouteComplete) return;
    if (_armedLineId != line.id) return;

    _busy = true;
    _lastAppliedValue = reading.valueMm;
    await context.read<AppState>().completePdfLineStep(
          widget.projectId,
          pdf.id,
          line.id,
          valueMm: reading.valueMm,
        );
    _busy = false;
    if (!mounted) return;
    _armedLineId = null;
    _ensureAutoMode();
  }

  Future<void> _skipLine(ProjectPdf pdf, PdfLine line) async {
    await context.read<AppState>().completePdfLineStep(
          widget.projectId,
          pdf.id,
          line.id,
          skipped: true,
        );
    if (!mounted) return;
    _armedLineId = null;
    _ensureAutoMode();
  }

  Future<void> _revertLine(ProjectPdf pdf) async {
    final reverted = await context.read<AppState>().revertPdfLineStep(
          widget.projectId,
          pdf.id,
        );
    if (!mounted) return;
    if (!reverted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нечего откатывать')),
      );
      return;
    }
    _armedLineId = null;
    _lastAppliedValue = null;
    _ensureAutoMode();
  }

  Future<void> _jumpToLine(ProjectPdf pdf, PdfLine line) async {
    await context.read<AppState>().jumpToPdfLine(widget.projectId, pdf.id, line.id);
    if (!mounted) return;
    _goToPage(line.pageIndex);
    _armedLineId = null;
    _lastAppliedValue = null;
    _ensureAutoMode();
  }

  Future<void> _showMeasurementSheet(ProjectPdf pdf, PdfLine line) async {
    final valueController = TextEditingController(
      text: line.measurementMm?.toString() ?? '',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(line.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Страница ${line.pageIndex + 1}'),
                const SizedBox(height: 16),
                TextField(
                  controller: valueController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Длина, мм',
                    suffixText: 'мм',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final value = int.tryParse(valueController.text.trim());
                    if (value == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Введите значение в мм')),
                      );
                      return;
                    }
                    await context.read<AppState>().updatePdfLineMeasurement(
                          widget.projectId,
                          pdf.id,
                          line.id,
                          valueMm: value,
                        );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Сохранить'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    await context.read<AppState>().updatePdfLineMeasurement(
                          widget.projectId,
                          pdf.id,
                          line.id,
                          remeasure: true,
                        );
                    if (context.mounted) {
                      Navigator.pop(context);
                      _armedLineId = null;
                      _ensureAutoMode();
                    }
                  },
                  child: const Text('Переснять'),
                ),
                if (!line.isComplete) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _skipLine(pdf, line);
                    },
                    child: const Text('Пропустить'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showLinesSheet(ProjectPdf pdf) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          final lines = context.watch<AppState>().pdfById(
                context.read<AppState>().projectById(widget.projectId),
                pdf.id,
              )?.sortedLines ??
              pdf.sortedLines;
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text('Линии (${lines.length})', style: Theme.of(context).textTheme.titleLarge),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      final line = lines[index];
                      final isCurrent = pdf.currentLine?.id == line.id;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : line.isComplete
                                  ? Colors.green
                                  : null,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(line.name),
                        subtitle: Text(
                          'Стр. ${line.pageIndex + 1}'
                          '${line.measurementMm == null ? '' : ' · ${line.measurementMm} мм'}',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _jumpToLine(pdf, line);
                        },
                        trailing: line.measurementMm != null
                            ? IconButton(
                                icon: const Icon(Icons.info_outline),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showMeasurementSheet(pdf, line);
                                },
                              )
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = context.watch<AppState>().projectById(widget.projectId);
    final rangefinder = context.watch<RangefinderController>();
    final pdf = _primaryPdf(project);

    if (pdf == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF маршрут')),
        body: const _PdfPlaceholder(
          icon: Icons.route_outlined,
          text: 'Сначала загрузите PDF в разметке',
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => pickProjectPdf(context, widget.projectId),
          icon: const Icon(Icons.upload_file),
          label: const Text('Загрузить PDF'),
        ),
      );
    }

    if (pdf.lines.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF маршрут')),
        body: const _PdfPlaceholder(
          icon: Icons.route_outlined,
          text: 'Нет линий. Добавьте их в PDF разметке',
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(
              builder: (_) => PdfMarkupScreen(projectId: widget.projectId),
            ),
          ),
          icon: const Icon(Icons.edit),
          label: const Text('PDF разметка'),
        ),
      );
    }

    final line = pdf.currentLine!;
    final progress = pdf.lines.isEmpty ? 0.0 : pdf.completedLineCount / pdf.lines.length;
    final totalPages = _pageCount > 0 ? _pageCount : pdf.pageCount;

    if (!pdf.isRouteComplete && line.id != _trackedLineId) {
      _trackedLineId = line.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureAutoMode();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF маршрут'),
        actions: [
          IconButton(
            tooltip: 'Список линий',
            onPressed: () => _showLinesSheet(pdf),
            icon: const Icon(Icons.format_list_numbered),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text('${pdf.completedLineCount}/${pdf.lines.length} линий'),
                if (!pdf.isRouteComplete) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        rangefinder.status == RangefinderStatus.connected || rangefinder.testMode
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        size: 18,
                        color: rangefinder.status == RangefinderStatus.connected || rangefinder.testMode
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _busy
                              ? 'Записываю замер...'
                              : rangefinder.status == RangefinderStatus.connected || rangefinder.testMode
                                  ? 'Стреляйте дальномером или нажмите на линию'
                                  : 'Подключите дальномер',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          _PdfPageToolbar(
            pageIndex: _pageIndex,
            pageCount: totalPages,
            onPrevious: _pageIndex > 0 ? () => _goToPage(_pageIndex - 1) : null,
            onNext: totalPages > 0 && _pageIndex < totalPages - 1
                ? () => _goToPage(_pageIndex + 1)
                : null,
          ),
          Expanded(
            child: _PdfInteractiveCanvas(
              pdf: pdf,
              projectId: widget.projectId,
              controller: _controller,
              pageIndex: _pageIndex,
              mode: _PdfCanvasMode.route,
              activeLineId: pdf.isRouteComplete ? null : line.id,
              onPageChanged: (index) => setState(() => _pageIndex = index),
              onPageCountLoaded: (count) async {
                if (_pageCount == count) return;
                setState(() => _pageCount = count);
                await context.read<AppState>().setPdfPageCount(
                      widget.projectId,
                      pdf.id,
                      count,
                    );
              },
              onLineTap: (screen, mapper) async {
                final hit = _hitTestLine(pdf, mapper, screen);
                if (hit == null) return;
                if (hit.measurementMm != null && hit.isComplete) {
                  await _showMeasurementSheet(pdf, hit);
                  return;
                }
                await _jumpToLine(pdf, hit);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.viewPaddingOf(context).bottom + 16,
              ),
              child: pdf.isRouteComplete
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: () async {
                            await context.read<AppState>().resetPdfRouteProgress(
                                  widget.projectId,
                                  pdf.id,
                                );
                            if (mounted) _ensureAutoMode();
                          },
                          icon: const Icon(Icons.replay),
                          label: const Text('Пройти заново'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('Закрыть'),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.name,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 8),
                                  _PdfMetricRow(
                                    label: 'Страница',
                                    value: '${line.pageIndex + 1}',
                                  ),
                                  _PdfMetricRow(
                                    label: 'Текущий замер',
                                    value: line.measurementMm == null ? 'не задан' : '${line.measurementMm} мм',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (line.measurementMm != null)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _showMeasurementSheet(pdf, line),
                              icon: const Icon(Icons.info_outline),
                              label: const Text('Подробнее / изменить'),
                            ),
                          if (line.measurementMm != null) const SizedBox(height: 8),
                          if (pdf.completedLineCount > 0)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _revertLine(pdf),
                              icon: const Icon(Icons.undo),
                              label: const Text('Шаг назад / перемерить'),
                            ),
                          if (pdf.completedLineCount > 0) const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _skipLine(pdf, line),
                            icon: const Icon(Icons.skip_next),
                            label: const Text('Пропустить линию'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  PdfLine? _hitTestLine(
    ProjectPdf pdf,
    PdfCoordinateMapper mapper,
    Offset screenPoint,
  ) {
    PdfLine? closest;
    var closestDistance = double.infinity;
    for (final item in pdf.lines.where((line) => line.pageIndex == _pageIndex)) {
      final start = mapper.lineStart(item);
      final end = mapper.lineEnd(item);
      final distance = _distanceToSegment(screenPoint, start, end);
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = item;
      }
    }
    if (closest == null || closestDistance > 28) return null;
    return closest;
  }
}

enum _PdfCanvasMode { markup, route }

class _PdfInteractiveCanvas extends StatefulWidget {
  const _PdfInteractiveCanvas({
    required this.pdf,
    required this.projectId,
    required this.controller,
    required this.pageIndex,
    required this.mode,
    required this.onPageChanged,
    this.markupMode,
    this.selectedLineId,
    this.activeLineId,
    this.draftStart,
    this.draftEnd,
    PdfLine Function(PdfLine line)? displayLine,
    this.onPageCountLoaded,
    this.onDrawTap,
    this.onEditTap,
    this.onEditDragStart,
    this.onEditDragUpdate,
    this.onEditDragEnd,
    this.onLineTap,
  }) : displayLine = displayLine ?? _identityLine;

  static PdfLine _identityLine(PdfLine line) => line;

  final ProjectPdf pdf;
  final String projectId;
  final PdfViewerController controller;
  final int pageIndex;
  final _PdfCanvasMode mode;
  final _PdfMarkupMode? markupMode;
  final String? selectedLineId;
  final String? activeLineId;
  final Offset? draftStart;
  final Offset? draftEnd;
  final PdfLine Function(PdfLine line) displayLine;
  final ValueChanged<int> onPageChanged;
  final Future<void> Function(int pageCount)? onPageCountLoaded;
  final Future<void> Function(Offset norm, int pageIndex)? onDrawTap;
  final void Function(Offset screen, PdfCoordinateMapper mapper)? onEditTap;
  final void Function(Offset screen, PdfCoordinateMapper mapper)? onEditDragStart;
  final void Function(Offset screen, PdfCoordinateMapper mapper)? onEditDragUpdate;
  final VoidCallback? onEditDragEnd;
  final Future<void> Function(Offset screen, PdfCoordinateMapper mapper)? onLineTap;

  @override
  State<_PdfInteractiveCanvas> createState() => _PdfInteractiveCanvasState();
}

class _PdfInteractiveCanvasState extends State<_PdfInteractiveCanvas> {
  final Map<int, Size> _pageSizes = {};
  double _zoomLevel = 1;
  Offset _scrollOffset = Offset.zero;
  bool _editDragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onViewerChanged);
  }

  @override
  void didUpdateWidget(covariant _PdfInteractiveCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onViewerChanged);
      widget.controller.addListener(_onViewerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onViewerChanged);
    super.dispose();
  }

  void _onViewerChanged() {
    final zoom = widget.controller.zoomLevel;
    final scroll = widget.controller.scrollOffset;
    if (zoom != _zoomLevel || scroll != _scrollOffset) {
      setState(() {
        _zoomLevel = zoom;
        _scrollOffset = scroll;
      });
    }
  }

  void _onDocumentLoaded(PdfDocumentLoadedDetails details) {
    final sizes = <int, Size>{};
    for (var i = 0; i < details.document.pages.count; i++) {
      final page = details.document.pages[i];
      sizes[i + 1] = Size(page.size.width, page.size.height);
    }
    setState(() => _pageSizes
      ..clear()
      ..addAll(sizes));
    unawaited(widget.onPageCountLoaded?.call(details.document.pages.count));
  }

  void _handleViewerTap(PdfGestureDetails details, PdfCoordinateMapper mapper) {
    if (details.pageNumber <= 0) return;
    final pageIndex = details.pageNumber - 1;

    if (widget.mode == _PdfCanvasMode.markup) {
      final mode = widget.markupMode;
      if (mode == _PdfMarkupMode.draw) {
        final norm = mapper.pagePositionToNorm(details);
        unawaited(widget.onDrawTap?.call(norm, pageIndex));
      } else if (mode == _PdfMarkupMode.edit && !_editDragging) {
        widget.onEditTap?.call(details.position, mapper);
      }
      return;
    }

    if (widget.mode == _PdfCanvasMode.route) {
      unawaited(widget.onLineTap?.call(details.position, mapper));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageLines = widget.pdf.lines
        .where((line) => line.pageIndex == widget.pageIndex)
        .map(widget.displayLine)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final mapper = PdfCoordinateMapper(
          controller: widget.controller,
          viewportSize: viewport,
          pageSizes: _pageSizes,
        );

        final selectedLine = widget.selectedLineId == null
            ? null
            : pageLines.cast<PdfLine?>().firstWhere(
                  (line) => line?.id == widget.selectedLineId,
                  orElse: () => null,
                );

        return Stack(
          fit: StackFit.expand,
          children: [
            SfPdfViewer.file(
              File(widget.pdf.path),
              controller: widget.controller,
              pageLayoutMode: PdfPageLayoutMode.single,
              enableTextSelection: false,
              onDocumentLoaded: _onDocumentLoaded,
              onPageChanged: (details) => widget.onPageChanged(details.newPageNumber - 1),
              onZoomLevelChanged: (_) => setState(() {
                _zoomLevel = widget.controller.zoomLevel;
                _scrollOffset = widget.controller.scrollOffset;
              }),
              onTap: (details) => _handleViewerTap(details, mapper),
            ),
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _PdfLinesPainter(
                    lines: pageLines,
                    mapper: mapper,
                    selectedLineId: widget.selectedLineId ?? widget.activeLineId,
                    showHandles: widget.mode == _PdfCanvasMode.markup &&
                        widget.markupMode == _PdfMarkupMode.edit,
                    draftStart: widget.draftStart,
                    draftEnd: widget.draftEnd,
                    pageIndex: widget.pageIndex,
                  ),
                  child: Stack(
                    children: [
                      ...pageLines.map(
                        (line) => _PdfLineLabel(
                          line: line,
                          mapper: mapper,
                          highlighted: line.id == (widget.selectedLineId ?? widget.activeLineId),
                        ),
                      ),
                      if (widget.draftStart != null)
                        _DraftDot(at: mapper.pageNormToScreen(
                          widget.pageIndex,
                          widget.draftStart!.dx,
                          widget.draftStart!.dy,
                        )),
                    ],
                  ),
                ),
              ),
            ),
            if (selectedLine != null &&
                widget.mode == _PdfCanvasMode.markup &&
                widget.markupMode == _PdfMarkupMode.edit)
              ..._buildEditHandles(selectedLine, mapper),
          ],
        );
      },
    );
  }

  List<Widget> _buildEditHandles(PdfLine line, PdfCoordinateMapper mapper) {
    Widget handle(Offset screen, _LineDragHandle kind) {
      return Positioned(
        left: screen.dx - 22,
        top: screen.dy - 22,
        child: Listener(
          onPointerDown: (event) {
            setState(() => _editDragging = true);
            widget.onEditDragStart?.call(event.position, mapper);
          },
          onPointerMove: (event) => widget.onEditDragUpdate?.call(event.position, mapper),
          onPointerUp: (_) {
            setState(() => _editDragging = false);
            widget.onEditDragEnd?.call();
          },
          onPointerCancel: (_) {
            setState(() => _editDragging = false);
            widget.onEditDragEnd?.call();
          },
          child: const SizedBox(width: 44, height: 44, child: _HandleDot()),
        ),
      );
    }

    final start = mapper.lineStart(line);
    final end = mapper.lineEnd(line);
    return [
      handle(start, _LineDragHandle.start),
      handle(end, _LineDragHandle.end),
      Positioned(
        left: (start.dx + end.dx) / 2 - 22,
        top: (start.dy + end.dy) / 2 - 22,
        child: Listener(
          onPointerDown: (event) {
            setState(() => _editDragging = true);
            widget.onEditDragStart?.call(event.position, mapper);
          },
          onPointerMove: (event) => widget.onEditDragUpdate?.call(event.position, mapper),
          onPointerUp: (_) {
            setState(() => _editDragging = false);
            widget.onEditDragEnd?.call();
          },
          onPointerCancel: (_) {
            setState(() => _editDragging = false);
            widget.onEditDragEnd?.call();
          },
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFFE65100).withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _PdfPageToolbar extends StatelessWidget {
  const _PdfPageToolbar({
    required this.pageIndex,
    required this.pageCount,
    this.onPrevious,
    this.onNext,
    this.onPickPage,
  });

  final int pageIndex;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPickPage;

  @override
  Widget build(BuildContext context) {
    final label = pageCount > 0 ? 'Стр. ${pageIndex + 1} / $pageCount' : 'Стр. ${pageIndex + 1}';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Предыдущая',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: InkWell(
                onTap: onPickPage,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Следующая',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfLinesPainter extends CustomPainter {
  _PdfLinesPainter({
    required this.lines,
    required this.mapper,
    this.selectedLineId,
    this.showHandles = false,
    this.draftStart,
    this.draftEnd,
    required this.pageIndex,
  });

  final List<PdfLine> lines;
  final PdfCoordinateMapper mapper;
  final String? selectedLineId;
  final bool showHandles;
  final Offset? draftStart;
  final Offset? draftEnd;
  final int pageIndex;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final start = mapper.lineStart(line);
      final end = mapper.lineEnd(line);
      final isSelected = line.id == selectedLineId;
      final paint = Paint()
        ..color = line.isComplete
            ? const Color(0xFF2E7D32)
            : isSelected
                ? const Color(0xFFE65100)
                : const Color(0xFF1565C0)
        ..strokeWidth = isSelected ? 5 : 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, paint);

      if (showHandles && isSelected) {
        _drawHandle(canvas, start, const Color(0xFFE65100));
        _drawHandle(canvas, end, const Color(0xFFE65100));
      }
    }

    if (draftStart != null && draftEnd != null) {
      final start = mapper.pageNormToScreen(pageIndex, draftStart!.dx, draftStart!.dy);
      final end = mapper.pageNormToScreen(pageIndex, draftEnd!.dx, draftEnd!.dy);
      final paint = Paint()
        ..color = const Color(0xFFE65100)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawLine(start, end, paint);
    }
  }

  void _drawHandle(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(
      center,
      12,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      12,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _PdfLinesPainter oldDelegate) {
    return oldDelegate.lines != lines ||
        oldDelegate.mapper.viewportSize != mapper.viewportSize ||
        oldDelegate.mapper.zoomLevel != mapper.zoomLevel ||
        oldDelegate.mapper.scrollOffset != mapper.scrollOffset ||
        oldDelegate.selectedLineId != selectedLineId ||
        oldDelegate.showHandles != showHandles ||
        oldDelegate.draftStart != draftStart ||
        oldDelegate.draftEnd != draftEnd;
  }
}

class _PdfLineLabel extends StatelessWidget {
  const _PdfLineLabel({
    required this.line,
    required this.mapper,
    required this.highlighted,
  });

  final PdfLine line;
  final PdfCoordinateMapper mapper;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final start = mapper.lineStart(line);
    final end = mapper.lineEnd(line);
    final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    return Positioned(
      left: center.dx - 40,
      top: center.dy - 14,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: highlighted
                ? const Color(0xFFE65100)
                : line.isComplete
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF1565C0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            line.name,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _DraftDot extends StatelessWidget {
  const _DraftDot({required this.at});

  final Offset at;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: at.dx - 8,
      top: at.dy - 8,
      child: const IgnorePointer(
        child: SizedBox(width: 16, height: 16, child: _HandleDot(color: Color(0xFFE65100))),
      ),
    );
  }
}

class _HandleDot extends StatelessWidget {
  const _HandleDot({this.color = const Color(0xFFE65100)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}

class _PdfMetricRow extends StatelessWidget {
  const _PdfMetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PdfPlaceholder extends StatelessWidget {
  const _PdfPlaceholder({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

Future<String?> _askLineName(BuildContext context, String initial) async {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Название линии'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Название',
          hintText: 'Например: Стена 1',
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

Future<bool> _confirmDelete(BuildContext context, String message) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Подтверждение'),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
          ],
        ),
      ) ??
      false;
}

Future<bool> _promptEnableBluetooth(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bluetooth выключен'),
          content: const Text('Для подключения дальномера нужно включить Bluetooth на телефоне.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Нет')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Включить')),
          ],
        ),
      ) ??
      false;
}

class _PdfRangefinderScreen extends StatelessWidget {
  const _PdfRangefinderScreen();

  @override
  Widget build(BuildContext context) {
    final rangefinder = context.watch<RangefinderController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Дальномер')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        rangefinder.status == RangefinderStatus.connected
                            ? Icons.check_circle
                            : Icons.bluetooth_searching,
                        color: rangefinder.status == RangefinderStatus.connected
                            ? Colors.green
                            : colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rangefinder.currentBackendLabel,
                                style: Theme.of(context).textTheme.titleMedium),
                            Text(rangefinder.status.label, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Тестовый режим'),
                    subtitle: const Text('Случайные значения для проверки UI'),
                    value: rangefinder.testMode,
                    onChanged: (value) async => rangefinder.setTestMode(value),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: rangefinder.status == RangefinderStatus.connected ||
                                rangefinder.status == RangefinderStatus.scanning ||
                                rangefinder.status == RangefinderStatus.connecting
                            ? null
                            : () => rangefinder.connect(
                                  onBluetoothOff: () => _promptEnableBluetooth(context),
                                ),
                        icon: const Icon(Icons.power_settings_new),
                        label: Text(rangefinder.testMode ? 'Тестовый режим' : 'Подключиться'),
                      ),
                      OutlinedButton.icon(
                        onPressed: rangefinder.status == RangefinderStatus.disconnected
                            ? null
                            : () => rangefinder.disconnect(),
                        icon: const Icon(Icons.stop),
                        label: const Text('Отключить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Найденные устройства', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (rangefinder.devices.isEmpty)
                    const Text('Нажмите «Подключиться» и подождите')
                  else
                    ...rangefinder.devices.take(12).map(
                          (device) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(device.label),
                            subtitle: Text(device.id),
                            trailing: OutlinedButton(
                              onPressed: rangefinder.status == RangefinderStatus.connecting
                                  ? null
                                  : () => rangefinder.connectToDevice(
                                        device.id,
                                        onBluetoothOff: () => _promptEnableBluetooth(context),
                                      ),
                              child: const Text('Выбрать'),
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
