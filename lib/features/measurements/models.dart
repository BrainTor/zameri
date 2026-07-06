enum MeasurementUnit {
  millimeters('мм'),
  centimeters('см'),
  meters('м');

  const MeasurementUnit(this.label);

  final String label;
}

enum RoomElementType {
  wall('Стена'),
  door('Дверь'),
  window('Окно'),
  opening('Проём'),
  slope('Откос'),
  height('Высота');

  const RoomElementType(this.label);

  final String label;
}

String createId() => DateTime.now().microsecondsSinceEpoch.toString();

const Object _unset = Object();

class Measurement {
  const Measurement({
    required this.id,
    required this.valueMm,
    required this.createdAt,
    this.source = 'manual',
    this.isPrimary = true,
  });

  final String id;
  final int valueMm;
  final DateTime createdAt;
  final String source;
  final bool isPrimary;

  String get displayValue => '$valueMm мм';

  Map<String, dynamic> toJson() => {
        'id': id,
        'valueMm': valueMm,
        'createdAt': createdAt.toIso8601String(),
        'source': source,
        'isPrimary': isPrimary,
      };

  factory Measurement.fromJson(Map<String, dynamic> json) => Measurement(
        id: json['id'] as String,
        valueMm: json['valueMm'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        source: json['source'] as String? ?? 'manual',
        isPrimary: json['isPrimary'] as bool? ?? true,
      );
}

class WallFinishLayer {
  const WallFinishLayer({
    required this.id,
    required this.name,
    required this.heightMm,
  });

  final String id;
  final String name;
  final int heightMm;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'heightMm': heightMm,
      };

  factory WallFinishLayer.fromJson(Map<String, dynamic> json) => WallFinishLayer(
        id: json['id'] as String,
        name: json['name'] as String,
        heightMm: json['heightMm'] as int,
      );
}

class RoomElement {
  const RoomElement({
    required this.id,
    required this.name,
    required this.type,
    required this.measurements,
    this.heightMm,
    this.depthMm,
    this.windowsillMm,
    this.radiatorNicheMm,
    this.wallElementId,
    this.note = '',
    this.finishLayers = const [],
  });

  final String id;
  final String name;
  final RoomElementType type;
  final int? heightMm;
  final int? depthMm;
  final int? windowsillMm;
  final int? radiatorNicheMm;
  final String? wallElementId;
  final String note;
  final List<WallFinishLayer> finishLayers;
  final List<Measurement> measurements;

  Measurement? get primaryMeasurement {
    for (final measurement in measurements) {
      if (measurement.isPrimary) return measurement;
    }
    return measurements.isEmpty ? null : measurements.first;
  }

  int get requiredParameterCount {
    return switch (type) {
      RoomElementType.height => 1,
      RoomElementType.door => 3,
      RoomElementType.window => 5,
      RoomElementType.slope => 1,
      _ => 2,
    };
  }

  int get completedParameterCount {
    var count = primaryValueMm == null ? 0 : 1;
    if (type != RoomElementType.height && heightMm != null) {
      count++;
    }
    if ((type == RoomElementType.door ||
            type == RoomElementType.window ||
            type == RoomElementType.slope) &&
        depthMm != null) {
      count++;
    }
    if (type == RoomElementType.window) {
      if (windowsillMm != null) count++;
      if (radiatorNicheMm != null) count++;
    }
    return count;
  }

  bool get isComplete => completedParameterCount >= requiredParameterCount;

  int? get primaryValueMm => primaryMeasurement?.valueMm;

  double get openingAreaM2 {
    if (type != RoomElementType.door && type != RoomElementType.window && type != RoomElementType.opening) {
      return 0;
    }
    final width = primaryValueMm;
    final height = heightMm;
    if (width == null || height == null) return 0;
    return width * height / 1000000;
  }

  RoomElement copyWith({
    String? name,
    RoomElementType? type,
    Object? heightMm = _unset,
    Object? depthMm = _unset,
    Object? windowsillMm = _unset,
    Object? radiatorNicheMm = _unset,
    Object? wallElementId = _unset,
    String? note,
    List<WallFinishLayer>? finishLayers,
    List<Measurement>? measurements,
  }) {
    return RoomElement(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      heightMm: identical(heightMm, _unset) ? this.heightMm : heightMm as int?,
      depthMm: identical(depthMm, _unset) ? this.depthMm : depthMm as int?,
      windowsillMm:
          identical(windowsillMm, _unset) ? this.windowsillMm : windowsillMm as int?,
      radiatorNicheMm: identical(radiatorNicheMm, _unset)
          ? this.radiatorNicheMm
          : radiatorNicheMm as int?,
      wallElementId: identical(wallElementId, _unset)
          ? this.wallElementId
          : wallElementId as String?,
      note: note ?? this.note,
      finishLayers: finishLayers ?? this.finishLayers,
      measurements: measurements ?? this.measurements,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'heightMm': heightMm,
        'depthMm': depthMm,
        'windowsillMm': windowsillMm,
        'radiatorNicheMm': radiatorNicheMm,
        'wallElementId': wallElementId,
        'note': note,
        'finishLayers': finishLayers.map((layer) => layer.toJson()).toList(),
        'measurements': measurements.map((measurement) => measurement.toJson()).toList(),
      };

  factory RoomElement.fromJson(Map<String, dynamic> json) => RoomElement(
        id: json['id'] as String,
        name: json['name'] as String,
        type: RoomElementType.values.byName(json['type'] as String),
        heightMm: json['heightMm'] as int?,
        depthMm: json['depthMm'] as int?,
        windowsillMm: json['windowsillMm'] as int?,
        radiatorNicheMm: json['radiatorNicheMm'] as int?,
        wallElementId: json['wallElementId'] as String?,
        note: json['note'] as String? ?? '',
        finishLayers: (json['finishLayers'] as List<dynamic>? ?? const [])
            .map((item) => WallFinishLayer.fromJson(item as Map<String, dynamic>))
            .toList(),
        measurements: (json['measurements'] as List<dynamic>? ?? const [])
            .map((item) => Measurement.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class Room {
  const Room({
    required this.id,
    required this.name,
    required this.elements,
    this.defaultHeightMm,
    this.isPolygonal = false,
  });

  final String id;
  final String name;
  final int? defaultHeightMm;
  final bool isPolygonal;
  final List<RoomElement> elements;

  GeometrySummary get geometry {
    final wallLengths = elements
        .where((element) => element.type == RoomElementType.wall)
        .map((element) => element.primaryValueMm)
        .whereType<int>()
        .toList();
    final perimeterMm = _perimeterFromWalls(wallLengths);
    final openingAreaM2 = elements.fold<double>(0, (sum, element) => sum + element.openingAreaM2);
    final wallAreaM2 = _wallAreaFromElements(elements, defaultHeightMm) - openingAreaM2;
    final floorAreaM2 = isPolygonal ? 0.0 : _floorAreaFromWalls(wallLengths);

    return GeometrySummary(
      floorAreaM2: floorAreaM2,
      wallAreaM2: wallAreaM2 < 0 ? 0.0 : wallAreaM2,
      perimeterMm: perimeterMm,
      openingAreaM2: openingAreaM2,
    );
  }

  Room copyWith({
    String? name,
    Object? defaultHeightMm = _unset,
    bool? isPolygonal,
    List<RoomElement>? elements,
  }) {
    return Room(
      id: id,
      name: name ?? this.name,
      defaultHeightMm: identical(defaultHeightMm, _unset)
          ? this.defaultHeightMm
          : defaultHeightMm as int?,
      isPolygonal: isPolygonal ?? this.isPolygonal,
      elements: elements ?? this.elements,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'defaultHeightMm': defaultHeightMm,
        'isPolygonal': isPolygonal,
        'elements': elements.map((element) => element.toJson()).toList(),
      };

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: json['id'] as String,
        name: json['name'] as String,
        defaultHeightMm: json['defaultHeightMm'] as int?,
        isPolygonal: json['isPolygonal'] as bool? ?? false,
        elements: (json['elements'] as List<dynamic>? ?? const [])
            .map((item) => RoomElement.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class GeometrySummary {
  const GeometrySummary({
    required this.floorAreaM2,
    required this.wallAreaM2,
    required this.perimeterMm,
    required this.openingAreaM2,
  });

  final double floorAreaM2;
  final double wallAreaM2;
  final int perimeterMm;
  final double openingAreaM2;
}

enum RouteStepTarget {
  width('Ширина'),
  height('Высота'),
  depth('Глубина откоса'),
  windowsill('Подоконник'),
  radiatorNiche('Ниша под радиатор'),
  roomHeight('Высота помещения');

  const RouteStepTarget(this.label);

  final String label;
}

class RouteBlueprintItem {
  const RouteBlueprintItem({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String name;
  final RoomElementType type;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
      };

  factory RouteBlueprintItem.fromJson(Map<String, dynamic> json) => RouteBlueprintItem(
        id: json['id'] as String,
        name: json['name'] as String,
        type: RoomElementType.values.byName(json['type'] as String),
      );
}

class RouteStepItem {
  const RouteStepItem({
    required this.id,
    required this.title,
    required this.roomId,
    required this.elementId,
    required this.target,
    this.isDone = false,
    this.isSkipped = false,
  });

  final String id;
  final String title;
  final String roomId;
  final String? elementId;
  final RouteStepTarget target;
  final bool isDone;
  final bool isSkipped;

  bool get isComplete => isDone || isSkipped;

  RouteStepItem copyWith({
    bool? isDone,
    bool? isSkipped,
  }) {
    return RouteStepItem(
      id: id,
      title: title,
      roomId: roomId,
      elementId: elementId,
      target: target,
      isDone: isDone ?? this.isDone,
      isSkipped: isSkipped ?? this.isSkipped,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'roomId': roomId,
        'elementId': elementId,
        'target': target.name,
        'isDone': isDone,
        'isSkipped': isSkipped,
      };

  factory RouteStepItem.fromJson(Map<String, dynamic> json) => RouteStepItem(
        id: json['id'] as String,
        title: json['title'] as String,
        roomId: json['roomId'] as String,
        elementId: json['elementId'] as String?,
        target: RouteStepTarget.values.byName(
          json['target'] as String? ?? RouteStepTarget.width.name,
        ),
        isDone: json['isDone'] as bool? ?? false,
        isSkipped: json['isSkipped'] as bool? ?? false,
      );
}

class MeasurementRoute {
  const MeasurementRoute({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.steps,
    this.blueprint = const [],
    this.currentStepIndex = 0,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int currentStepIndex;
  final List<RouteStepItem> steps;
  final List<RouteBlueprintItem> blueprint;

  bool get isTemplate => blueprint.isNotEmpty;

  int get completedCount => steps.where((step) => step.isComplete).length;

  bool get isComplete => steps.isNotEmpty && completedCount == steps.length;

  RouteStepItem? get currentStep {
    if (steps.isEmpty) return null;
    final pendingIndex = steps.indexWhere((step) => !step.isComplete);
    if (pendingIndex != -1) return steps[pendingIndex];
    return steps.last;
  }

  MeasurementRoute copyWith({
    String? name,
    int? currentStepIndex,
    List<RouteStepItem>? steps,
    List<RouteBlueprintItem>? blueprint,
  }) {
    return MeasurementRoute(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      steps: steps ?? this.steps,
      blueprint: blueprint ?? this.blueprint,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'currentStepIndex': currentStepIndex,
        'steps': steps.map((step) => step.toJson()).toList(),
        'blueprint': blueprint.map((item) => item.toJson()).toList(),
      };

  factory MeasurementRoute.fromJson(Map<String, dynamic> json) => MeasurementRoute(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        currentStepIndex: json['currentStepIndex'] as int? ?? 0,
        steps: (json['steps'] as List<dynamic>? ?? const [])
            .map((item) => RouteStepItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        blueprint: (json['blueprint'] as List<dynamic>? ?? const [])
            .map((item) => RouteBlueprintItem.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class PhotoAnnotation {
  const PhotoAnnotation({
    required this.id,
    required this.x,
    required this.y,
    this.roomId,
    this.elementId,
    this.measurement,
    this.comment,
  });

  final String id;
  final double x;
  final double y;
  final String? roomId;
  final String? elementId;
  final Measurement? measurement;
  final String? comment;

  bool get isLinked => roomId != null || elementId != null || measurement != null;

  PhotoAnnotation copyWith({
    String? roomId,
    String? elementId,
    Measurement? measurement,
    String? comment,
  }) {
    return PhotoAnnotation(
      id: id,
      x: x,
      y: y,
      roomId: roomId ?? this.roomId,
      elementId: elementId ?? this.elementId,
      measurement: measurement ?? this.measurement,
      comment: comment ?? this.comment,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'roomId': roomId,
        'elementId': elementId,
        'measurement': measurement?.toJson(),
        'comment': comment,
      };

  factory PhotoAnnotation.fromJson(Map<String, dynamic> json) => PhotoAnnotation(
        id: json['id'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        roomId: json['roomId'] as String?,
        elementId: json['elementId'] as String?,
        measurement: json['measurement'] == null
            ? null
            : Measurement.fromJson(json['measurement'] as Map<String, dynamic>),
        comment: json['comment'] as String?,
      );
}

class ProjectPhoto {
  const ProjectPhoto({
    required this.id,
    required this.path,
    required this.createdAt,
    required this.annotations,
  });

  final String id;
  final String path;
  final DateTime createdAt;
  final List<PhotoAnnotation> annotations;

  ProjectPhoto copyWith({List<PhotoAnnotation>? annotations}) {
    return ProjectPhoto(
      id: id,
      path: path,
      createdAt: createdAt,
      annotations: annotations ?? this.annotations,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'createdAt': createdAt.toIso8601String(),
        'annotations': annotations.map((annotation) => annotation.toJson()).toList(),
      };

  factory ProjectPhoto.fromJson(Map<String, dynamic> json) => ProjectPhoto(
        id: json['id'] as String,
        path: json['path'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        annotations: (json['annotations'] as List<dynamic>? ?? const [])
            .map((item) => PhotoAnnotation.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class PdfAnnotation {
  const PdfAnnotation({
    required this.id,
    required this.pageIndex,
    required this.x,
    required this.y,
    this.roomId,
    this.elementId,
    this.measurement,
  });

  final String id;
  final int pageIndex;
  final double x;
  final double y;
  final String? roomId;
  final String? elementId;
  final Measurement? measurement;

  bool get isLinked => roomId != null || elementId != null || measurement != null;

  PdfAnnotation copyWith({
    String? roomId,
    String? elementId,
    Measurement? measurement,
  }) {
    return PdfAnnotation(
      id: id,
      pageIndex: pageIndex,
      x: x,
      y: y,
      roomId: roomId ?? this.roomId,
      elementId: elementId ?? this.elementId,
      measurement: measurement ?? this.measurement,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'x': x,
        'y': y,
        'roomId': roomId,
        'elementId': elementId,
        'measurement': measurement?.toJson(),
      };

  factory PdfAnnotation.fromJson(Map<String, dynamic> json) => PdfAnnotation(
        id: json['id'] as String,
        pageIndex: json['pageIndex'] as int? ?? 0,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        roomId: json['roomId'] as String?,
        elementId: json['elementId'] as String?,
        measurement: json['measurement'] == null
            ? null
            : Measurement.fromJson(json['measurement'] as Map<String, dynamic>),
      );
}

/// Координаты линии: [page] — доли 0..1 от размера страницы PDF, [viewport] — устаревший формат.
enum PdfLineCoordSpace { page, viewport }

class PdfLine {
  const PdfLine({
    required this.id,
    required this.pageIndex,
    required this.name,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.orderIndex,
    this.coordSpace = PdfLineCoordSpace.page,
    this.measurementMm,
    this.isDone = false,
    this.isSkipped = false,
  });

  final String id;
  final int pageIndex;
  final String name;
  /// Доля 0..1 по ширине страницы PDF.
  final double x1;
  /// Доля 0..1 по высоте страницы PDF.
  final double y1;
  final double x2;
  final double y2;
  final int orderIndex;
  final PdfLineCoordSpace coordSpace;
  final int? measurementMm;
  final bool isDone;
  final bool isSkipped;

  bool get isComplete => isDone || isSkipped;
  bool get usesPageCoords => coordSpace == PdfLineCoordSpace.page;

  PdfLine copyWith({
    String? name,
    int? pageIndex,
    double? x1,
    double? y1,
    double? x2,
    double? y2,
    int? measurementMm,
    bool? isDone,
    bool? isSkipped,
    int? orderIndex,
    PdfLineCoordSpace? coordSpace,
    bool clearMeasurement = false,
  }) {
    return PdfLine(
      id: id,
      pageIndex: pageIndex ?? this.pageIndex,
      name: name ?? this.name,
      x1: x1 ?? this.x1,
      y1: y1 ?? this.y1,
      x2: x2 ?? this.x2,
      y2: y2 ?? this.y2,
      orderIndex: orderIndex ?? this.orderIndex,
      coordSpace: coordSpace ?? this.coordSpace,
      measurementMm: clearMeasurement ? null : (measurementMm ?? this.measurementMm),
      isDone: isDone ?? this.isDone,
      isSkipped: isSkipped ?? this.isSkipped,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'name': name,
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'orderIndex': orderIndex,
        'coordSpace': coordSpace.name,
        'measurementMm': measurementMm,
        'isDone': isDone,
        'isSkipped': isSkipped,
      };

  factory PdfLine.fromJson(Map<String, dynamic> json) {
    final coordRaw = json['coordSpace'] as String?;
    return PdfLine(
      id: json['id'] as String,
      pageIndex: json['pageIndex'] as int? ?? 0,
      name: json['name'] as String? ?? 'Линия',
      x1: (json['x1'] as num).toDouble(),
      y1: (json['y1'] as num).toDouble(),
      x2: (json['x2'] as num).toDouble(),
      y2: (json['y2'] as num).toDouble(),
      orderIndex: json['orderIndex'] as int? ?? 0,
      coordSpace: coordRaw == 'page'
          ? PdfLineCoordSpace.page
          : PdfLineCoordSpace.viewport,
      measurementMm: json['measurementMm'] as int?,
      isDone: json['isDone'] as bool? ?? false,
      isSkipped: json['isSkipped'] as bool? ?? false,
    );
  }
}

class ProjectPdf {
  const ProjectPdf({
    required this.id,
    required this.path,
    required this.name,
    required this.createdAt,
    required this.annotations,
    this.lines = const [],
    this.routeCursorLineId,
    this.pageCount = 0,
  });

  final String id;
  final String path;
  final String name;
  final DateTime createdAt;
  final List<PdfAnnotation> annotations;
  final List<PdfLine> lines;
  /// Явная текущая линия маршрута (tap jump без skip предыдущих).
  final String? routeCursorLineId;
  /// Кэш количества страниц из PDF-документа.
  final int pageCount;

  bool get hasLegacyViewportLines =>
      lines.any((line) => line.coordSpace == PdfLineCoordSpace.viewport);

  List<PdfLine> get sortedLines {
    final copy = [...lines];
    copy.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return copy;
  }

  PdfLine? lineById(String? id) {
    if (id == null) return null;
    for (final line in lines) {
      if (line.id == id) return line;
    }
    return null;
  }

  PdfLine? get currentLine {
    if (lines.isEmpty) return null;
    final cursor = lineById(routeCursorLineId);
    if (cursor != null && !cursor.isComplete) return cursor;
    for (final line in sortedLines) {
      if (!line.isComplete) return line;
    }
    return sortedLines.last;
  }

  int get completedLineCount => lines.where((line) => line.isComplete).length;

  bool get isRouteComplete => lines.isNotEmpty && lines.every((line) => line.isComplete);

  ProjectPdf copyWith({
    List<PdfAnnotation>? annotations,
    List<PdfLine>? lines,
    String? routeCursorLineId,
    bool clearRouteCursor = false,
    int? pageCount,
  }) {
    return ProjectPdf(
      id: id,
      path: path,
      name: name,
      createdAt: createdAt,
      annotations: annotations ?? this.annotations,
      lines: lines ?? this.lines,
      routeCursorLineId: clearRouteCursor ? null : (routeCursorLineId ?? this.routeCursorLineId),
      pageCount: pageCount ?? this.pageCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'annotations': annotations.map((annotation) => annotation.toJson()).toList(),
        'lines': lines.map((line) => line.toJson()).toList(),
        'routeCursorLineId': routeCursorLineId,
        'pageCount': pageCount,
      };

  factory ProjectPdf.fromJson(Map<String, dynamic> json) => ProjectPdf(
        id: json['id'] as String,
        path: json['path'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        annotations: (json['annotations'] as List<dynamic>? ?? const [])
            .map((item) => PdfAnnotation.fromJson(item as Map<String, dynamic>))
            .toList(),
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .map((item) => PdfLine.fromJson(item as Map<String, dynamic>))
            .toList(),
        routeCursorLineId: json['routeCursorLineId'] as String?,
        pageCount: json['pageCount'] as int? ?? 0,
      );
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.rooms,
    required this.photos,
    required this.pdfs,
    this.routes = const [],
    this.description = '',
    this.unit = MeasurementUnit.millimeters,
    this.precisionMm = 1,
  });

  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final MeasurementUnit unit;
  final int precisionMm;
  final List<Room> rooms;
  final List<ProjectPhoto> photos;
  final List<ProjectPdf> pdfs;
  final List<MeasurementRoute> routes;

  Project copyWith({
    String? name,
    String? description,
    MeasurementUnit? unit,
    int? precisionMm,
    List<Room>? rooms,
    List<ProjectPhoto>? photos,
    List<ProjectPdf>? pdfs,
    List<MeasurementRoute>? routes,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt,
      unit: unit ?? this.unit,
      precisionMm: precisionMm ?? this.precisionMm,
      rooms: rooms ?? this.rooms,
      photos: photos ?? this.photos,
      pdfs: pdfs ?? this.pdfs,
      routes: routes ?? this.routes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'unit': unit.name,
        'precisionMm': precisionMm,
        'rooms': rooms.map((room) => room.toJson()).toList(),
        'photos': photos.map((photo) => photo.toJson()).toList(),
        'pdfs': pdfs.map((pdf) => pdf.toJson()).toList(),
        'routes': routes.map((route) => route.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        unit: MeasurementUnit.values.byName(json['unit'] as String? ?? MeasurementUnit.millimeters.name),
        precisionMm: json['precisionMm'] as int? ?? 1,
        rooms: (json['rooms'] as List<dynamic>? ?? const [])
            .map((item) => Room.fromJson(item as Map<String, dynamic>))
            .toList(),
        photos: (json['photos'] as List<dynamic>? ?? const [])
            .map((item) => ProjectPhoto.fromJson(item as Map<String, dynamic>))
            .toList(),
        pdfs: (json['pdfs'] as List<dynamic>? ?? const [])
            .map((item) => ProjectPdf.fromJson(item as Map<String, dynamic>))
            .toList(),
        routes: (json['routes'] as List<dynamic>? ?? const [])
            .map((item) => MeasurementRoute.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

double _floorAreaFromWalls(List<int> wallLengths) {
  if (wallLengths.length < 2) return 0;
  if (wallLengths.length >= 4) {
    final width = (wallLengths[0] + wallLengths[2]) / 2;
    final length = (wallLengths[1] + wallLengths[3]) / 2;
    return width * length / 1000000;
  }
  return wallLengths[0] * wallLengths[1] / 1000000;
}

int _perimeterFromWalls(List<int> wallLengths) {
  if (wallLengths.length == 2) {
    return (wallLengths[0] + wallLengths[1]) * 2;
  }
  return wallLengths.fold<int>(0, (sum, value) => sum + value);
}

double _wallAreaFromElements(List<RoomElement> elements, int? defaultHeightMm) {
  final walls = elements.where((element) => element.type == RoomElementType.wall).toList();
  var area = 0.0;
  for (final wall in walls) {
    final width = wall.primaryValueMm;
    final height = wall.heightMm ?? defaultHeightMm;
    if (width == null || height == null) continue;
    area += width * height / 1000000;
  }
  if (walls.length == 2) {
    area *= 2;
  }
  return area;
}
