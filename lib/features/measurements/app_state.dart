import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import 'models.dart';

class AppState extends ChangeNotifier {
  static const int _undoLimit = 20;

  final List<Project> _projects = [];
  final List<List<Project>> _undoStack = [];
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLoaded = false;
  bool _showOnboarding = true;
  bool _onboardingPrompted = false;
  String? _activePhotoAnnotationId;
  String? _activePdfAnnotationId;

  List<Project> get projects => List.unmodifiable(_projects);
  ThemeMode get themeMode => _themeMode;
  bool get isLoaded => _isLoaded;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get showOnboarding => _showOnboarding;
  bool get shouldPromptOnboarding => _showOnboarding && !_onboardingPrompted;

  Future<File> get _storeFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}zameri_data.json');
  }

  Future<Directory> get _mediaDirectory async {
    final directory = await getApplicationDocumentsDirectory();
    final media = Directory('${directory.path}${Platform.pathSeparator}zameri_media');
    if (!media.existsSync()) {
      await media.create(recursive: true);
    }
    return media;
  }

  Future<void> load() async {
    final file = await _storeFile;
    if (!await file.exists()) {
      _projects.add(_seedProject());
      _isLoaded = true;
      await _save();
      notifyListeners();
      return;
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      _isLoaded = true;
      notifyListeners();
      return;
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;
    _themeMode = ThemeMode.values.byName(json['themeMode'] as String? ?? ThemeMode.system.name);
    _showOnboarding = json['showOnboarding'] as bool? ?? true;
    _projects
      ..clear()
      ..addAll(
        (json['projects'] as List<dynamic>? ?? const [])
            .map((item) => _migrateProject(Project.fromJson(item as Map<String, dynamic>))),
      );
    _isLoaded = true;
    notifyListeners();
  }

  Project _migrateProject(Project project) {
    final needsMigration = project.rooms.any(
          (room) => room.elements.any((element) => element.type == RoomElementType.slope),
        ) ||
        project.routes.any(
          (route) => route.blueprint.any((item) => item.type == RoomElementType.slope),
        );
    if (!needsMigration) return project;
    return project.copyWith(
      rooms: project.rooms.map(_migrateRoom).toList(growable: false),
      routes: project.routes.map(_migrateRoute).toList(growable: false),
    );
  }

  Room _migrateRoom(Room room) {
    final slopes = room.elements.where((element) => element.type == RoomElementType.slope).toList();
    if (slopes.isEmpty) return room;

    var elements = room.elements.where((element) => element.type != RoomElementType.slope).toList();
    for (final slope in slopes) {
      final targetIndex = elements.indexWhere(
        (element) =>
            (element.type == RoomElementType.door || element.type == RoomElementType.window) &&
            (slope.wallElementId == null || element.wallElementId == slope.wallElementId),
      );
      if (targetIndex == -1) continue;
      final target = elements[targetIndex];
      elements[targetIndex] = target.copyWith(
        depthMm: slope.depthMm ?? slope.primaryValueMm ?? target.depthMm,
      );
    }
    return room.copyWith(elements: elements);
  }

  MeasurementRoute _migrateRoute(MeasurementRoute route) {
    if (route.blueprint.isEmpty) return route;
    final blueprint = route.blueprint
        .where((item) => item.type != RoomElementType.slope)
        .toList(growable: false);
    if (blueprint.length == route.blueprint.length) return route;
    return route.copyWith(blueprint: blueprint);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _save();
  }

  void markOnboardingPrompted() {
    _onboardingPrompted = true;
    notifyListeners();
  }

  Future<void> setShowOnboarding(bool value) async {
    _showOnboarding = value;
    _onboardingPrompted = !value;
    notifyListeners();
    await _save();
  }

  Future<Project> createProject({
    required String name,
    required String description,
    required MeasurementUnit unit,
  }) async {
    _recordUndo();
    final project = Project(
      id: createId(),
      name: name,
      description: description,
      createdAt: DateTime.now(),
      unit: unit,
      rooms: const [],
      photos: const [],
      pdfs: const [],
    );
    _projects.insert(0, project);
    notifyListeners();
    await _save();
    return project;
  }

  Future<void> updateProject(
    String projectId, {
    required String name,
    required String description,
    required MeasurementUnit unit,
  }) async {
    final project = projectById(projectId);
    _replaceProject(
      project.copyWith(
        name: name,
        description: description,
        unit: unit,
      ),
    );
    await _save();
  }

  Future<void> deleteProject(String projectId) async {
    _recordUndo();
    _projects.removeWhere((project) => project.id == projectId);
    notifyListeners();
    await _save();
  }

  Future<void> addRoom(
    String projectId,
    String name, {
    int? defaultHeightMm,
    bool isPolygonal = false,
    int? wall1WidthMm,
    int? wall1HeightMm,
    int? wall2WidthMm,
    int? wall2HeightMm,
  }) async {
    final project = projectById(projectId);
    final now = DateTime.now();
    final elements = <RoomElement>[];
    if (wall1WidthMm != null &&
        wall1HeightMm != null &&
        wall2WidthMm != null &&
        wall2HeightMm != null) {
      RoomElement makeWall(int index, int widthMm, int heightMm) {
        return RoomElement(
          id: '${createId()}_wall_$index',
          name: 'Стена $index',
          type: RoomElementType.wall,
          heightMm: heightMm,
          measurements: [
            Measurement(
              id: '${createId()}_wall_${index}_m',
              valueMm: widthMm,
              createdAt: now,
              source: 'manual',
            ),
          ],
        );
      }

      elements
        ..add(makeWall(1, wall1WidthMm, wall1HeightMm))
        ..add(makeWall(2, wall2WidthMm, wall2HeightMm));
    }
    final room = Room(
      id: createId(),
      name: name,
      defaultHeightMm: defaultHeightMm,
      isPolygonal: isPolygonal,
      elements: elements,
    );
    _replaceProject(project.copyWith(rooms: [...project.rooms, room]));
    await _save();
  }

  Future<void> updateRoom(
    String projectId,
    String roomId, {
    required String name,
    required int? defaultHeightMm,
    bool? isPolygonal,
  }) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      return room.copyWith(
        name: name,
        defaultHeightMm: defaultHeightMm,
        isPolygonal: isPolygonal,
      );
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> deleteRoom(String projectId, String roomId) async {
    final project = projectById(projectId);
    final rooms = project.rooms.where((room) => room.id != roomId).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> updateRoomHeight(String projectId, String roomId, int? heightMm) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      return room.copyWith(defaultHeightMm: heightMm);
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> addElement(
    String projectId,
    String roomId,
    RoomElementType type, {
    String? name,
    required int valueMm,
    int? heightMm,
    int? depthMm,
    int? windowsillMm,
    int? radiatorNicheMm,
    String? wallElementId,
    String note = '',
  }) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      final index = room.elements.where((element) => element.type == type).length + 1;
      final primaryMeasurement = Measurement(
        id: createId(),
        valueMm: valueMm,
        createdAt: DateTime.now(),
        source: 'manual',
      );
      final element = RoomElement(
        id: createId(),
        name: name?.trim().isNotEmpty == true ? name!.trim() : '${type.label} $index',
        type: type,
        heightMm: heightMm ?? room.defaultHeightMm,
        depthMm: depthMm,
        windowsillMm: windowsillMm,
        radiatorNicheMm: radiatorNicheMm,
        wallElementId: _openingWallId(type, wallElementId),
        note: note,
        measurements: [primaryMeasurement],
      );
      return room.copyWith(elements: [...room.elements, element]);
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> addRectangularRoomWalls(
    String projectId,
    String roomId, {
    required int wall1WidthMm,
    required int wall1HeightMm,
    required int wall2WidthMm,
    required int wall2HeightMm,
  }) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      final existingWalls = room.elements.where((element) => element.type == RoomElementType.wall).length;
      final now = DateTime.now();

      RoomElement makeWall(int index, int widthMm, int heightMm) {
        return RoomElement(
          id: '${createId()}_$index',
          name: 'Стена ${existingWalls + index}',
          type: RoomElementType.wall,
          heightMm: heightMm,
          measurements: [
            Measurement(
              id: '${createId()}_m$index',
              valueMm: widthMm,
              createdAt: now,
              source: 'manual',
            ),
          ],
        );
      }

      final newWalls = [
        makeWall(1, wall1WidthMm, wall1HeightMm),
        makeWall(2, wall2WidthMm, wall2HeightMm),
      ];
      return room.copyWith(elements: [...room.elements, ...newWalls]);
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> updateElement(
    String projectId,
    String roomId,
    String elementId, {
    required String name,
    required RoomElementType type,
    required int? heightMm,
    required int primaryValueMm,
    int? depthMm,
    int? windowsillMm,
    int? radiatorNicheMm,
    String? wallElementId,
    String note = '',
  }) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      final elements = room.elements.map((element) {
        if (element.id != elementId) return element;
        final existing = element.measurements;
        final measurements = existing.isEmpty
            ? [
                Measurement(
                  id: createId(),
                  valueMm: primaryValueMm,
                  createdAt: DateTime.now(),
                ),
              ]
            : [
                Measurement(
                  id: existing.first.id,
                  valueMm: primaryValueMm,
                  createdAt: existing.first.createdAt,
                  source: existing.first.source,
                  isPrimary: true,
                ),
                ...existing.skip(1).map(
                      (measurement) => Measurement(
                        id: measurement.id,
                        valueMm: measurement.valueMm,
                        createdAt: measurement.createdAt,
                        source: measurement.source,
                        isPrimary: false,
                      ),
                    ),
              ];
        return element.copyWith(
          name: name.trim().isEmpty ? element.name : name.trim(),
          type: type,
          heightMm: heightMm,
          depthMm: depthMm,
          windowsillMm: windowsillMm,
          radiatorNicheMm: radiatorNicheMm,
          wallElementId: _openingWallId(type, wallElementId),
          note: note,
          measurements: measurements,
        );
      }).toList();
      return room.copyWith(elements: elements);
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> deleteElement(String projectId, String roomId, String elementId) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      RoomElement? removed;
      for (final element in room.elements) {
        if (element.id == elementId) {
          removed = element;
          break;
        }
      }
      final removedWall = removed?.type == RoomElementType.wall;
      return room.copyWith(
        elements: room.elements
            .where((element) => element.id != elementId)
            .map((element) => removedWall && element.wallElementId == elementId
                ? element.copyWith(wallElementId: null)
                : element)
            .toList(),
      );
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> addMeasurement(String projectId, String roomId, String elementId, int valueMm) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      final elements = room.elements.map((element) {
        if (element.id != elementId) return element;
        return element.copyWith(
          measurements: [
            ...element.measurements,
            Measurement(
              id: createId(),
              valueMm: valueMm,
              createdAt: DateTime.now(),
              isPrimary: element.measurements.isEmpty,
            ),
          ],
        );
      }).toList();
      return room.copyWith(elements: elements);
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> deleteMeasurement(String projectId, String roomId, String elementId, String measurementId) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      final elements = room.elements.map((element) {
        if (element.id != elementId) return element;
        final filtered = element.measurements.where((measurement) => measurement.id != measurementId).toList();
        final normalized = filtered.asMap().entries.map((entry) {
          final measurement = entry.value;
          return Measurement(
            id: measurement.id,
            valueMm: measurement.valueMm,
            createdAt: measurement.createdAt,
            source: measurement.source,
            isPrimary: entry.key == 0,
          );
        }).toList();
        return element.copyWith(measurements: normalized);
      }).toList();
      return room.copyWith(elements: elements);
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> setPrimaryMeasurement(
    String projectId,
    String roomId,
    String elementId,
    String measurementId,
  ) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      final elements = room.elements.map((element) {
        if (element.id != elementId) return element;
        return element.copyWith(
          measurements: element.measurements
              .map(
                (measurement) => Measurement(
                  id: measurement.id,
                  valueMm: measurement.valueMm,
                  createdAt: measurement.createdAt,
                  source: measurement.source,
                  isPrimary: measurement.id == measurementId,
                ),
              )
              .toList(),
        );
      }).toList();
      return room.copyWith(elements: elements);
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> createRouteFromProject(String projectId) async {
    final project = projectById(projectId);
    final steps = <RouteStepItem>[];
    for (final room in project.rooms) {
      if (room.elements.isEmpty) {
        steps.add(
          RouteStepItem(
            id: '${createId()}_${steps.length}',
            title: '${room.name}: задать элементы и высоту',
            roomId: room.id,
            elementId: null,
            target: RouteStepTarget.width,
          ),
        );
      } else {
        for (final element in room.elements) {
          _addElementRouteSteps(steps, room, element);
        }
      }
    }

    final route = MeasurementRoute(
      id: createId(),
      name: 'Маршрут ${project.routes.length + 1}',
      createdAt: DateTime.now(),
      steps: steps,
    );
    _replaceProject(project.copyWith(routes: [route, ...project.routes]));
    await _save();
  }

  Future<void> createRouteFromRoom(
    String projectId,
    String roomId,
    List<String> orderedElementIds,
  ) async {
    final project = projectById(projectId);
    final room = project.rooms.firstWhere((item) => item.id == roomId);
    final elementsById = {
      for (final element in room.elements) element.id: element,
    };
    final orderedElements = orderedElementIds
        .map((id) => elementsById[id])
        .whereType<RoomElement>()
        .toList();
    final steps = <RouteStepItem>[];
    for (final element in orderedElements) {
      _addElementRouteSteps(steps, room, element);
    }

    final route = MeasurementRoute(
      id: createId(),
      name: '${room.name}: маршрут ${project.routes.length + 1}',
      createdAt: DateTime.now(),
      steps: steps,
    );
    _replaceProject(project.copyWith(routes: [route, ...project.routes]));
    await _save();
  }

  Future<MeasurementRoute> createRouteTemplate(
    String projectId, {
    required String name,
    required List<RouteBlueprintItem> blueprint,
  }) async {
    final project = projectById(projectId);
    final route = MeasurementRoute(
      id: createId(),
      name: name.trim(),
      createdAt: DateTime.now(),
      blueprint: blueprint,
      steps: const [],
    );
    _replaceProject(project.copyWith(routes: [route, ...project.routes]));
    await _save();
    return route;
  }

  Future<void> updateRouteTemplate(
    String projectId,
    String routeId, {
    required String name,
    required List<RouteBlueprintItem> blueprint,
  }) async {
    final project = projectById(projectId);
    final routes = project.routes.map((route) {
      if (route.id != routeId) return route;
      return route.copyWith(
        name: name.trim(),
        blueprint: blueprint,
        steps: const [],
        currentStepIndex: 0,
      );
    }).toList();
    _replaceProject(project.copyWith(routes: routes));
    await _save();
  }

  Future<void> deleteRoute(String projectId, String routeId) async {
    final project = projectById(projectId);
    _replaceProject(
      project.copyWith(
        routes: project.routes.where((route) => route.id != routeId).toList(),
      ),
    );
    await _save();
  }

  Future<void> clearRouteRunState(String projectId, String routeId) async {
    final project = projectById(projectId);
    final routes = project.routes.map((route) {
      if (route.id != routeId || !route.isTemplate) return route;
      return route.copyWith(steps: const [], currentStepIndex: 0);
    }).toList();
    _replaceProject(project.copyWith(routes: routes), recordUndo: false);
    await _save();
  }

  Future<MeasurementRoute> launchRouteInRoom(
    String projectId,
    String routeId,
    String roomId,
  ) async {
    var project = projectById(projectId);
    final routeIndex = project.routes.indexWhere((route) => route.id == routeId);
    if (routeIndex == -1) {
      throw StateError('Маршрут не найден');
    }
    var route = project.routes[routeIndex];
    if (route.blueprint.isEmpty) {
      final steps = route.steps
          .map((step) => step.copyWith(isDone: false, isSkipped: false))
          .toList();
      route = route.copyWith(steps: steps, currentStepIndex: 0);
      final routes = [...project.routes];
      routes[routeIndex] = route;
      _replaceProject(project.copyWith(routes: routes));
      await _save();
      return route;
    }

    var room = project.rooms.firstWhere((item) => item.id == roomId);
    var updatedElements = List<RoomElement>.from(room.elements);
    final steps = <RouteStepItem>[];
    final now = DateTime.now();

    for (final item in route.blueprint) {
      if (item.type == RoomElementType.height) {
        room = room.copyWith(elements: updatedElements);
        if (room.defaultHeightMm == null) {
          _addRoomHeightRouteStep(steps, room);
        }
        continue;
      }

      final existingIndex = updatedElements.indexWhere(
        (element) => element.name == item.name && element.type == item.type,
      );
      late RoomElement element;
      if (existingIndex >= 0) {
        element = updatedElements[existingIndex];
        if (_skipHeightStep(element, room) &&
            element.heightMm == null &&
            room.defaultHeightMm != null) {
          element = element.copyWith(heightMm: room.defaultHeightMm);
          updatedElements[existingIndex] = element;
        }
      } else {
        element = RoomElement(
          id: createId(),
          name: item.name,
          type: item.type,
          heightMm: item.type == RoomElementType.wall ? room.defaultHeightMm : null,
          measurements: item.type == RoomElementType.height
              ? const []
              : [
                  Measurement(
                    id: createId(),
                    valueMm: 0,
                    createdAt: now,
                    source: 'route',
                  ),
                ],
        );
        updatedElements.add(element);
      }
      room = room.copyWith(elements: updatedElements);
      _addElementRouteSteps(steps, room, element);
    }

    final updatedRoom = room.copyWith(elements: updatedElements);
    final rooms = project.rooms
        .map((item) => item.id == roomId ? updatedRoom : item)
        .toList();
    route = route.copyWith(steps: steps, currentStepIndex: 0);
    final routes = [...project.routes];
    routes[routeIndex] = route;
    _replaceProject(project.copyWith(rooms: rooms, routes: routes));
    await _save();
    return route;
  }

  Future<bool> revertRouteStep(String projectId, String routeId) async {
    var project = projectById(projectId);
    final routeIndex = project.routes.indexWhere((route) => route.id == routeId);
    if (routeIndex == -1) return false;

    final route = project.routes[routeIndex];
    if (route.steps.isEmpty) return false;

    final pendingIndex = route.steps.indexWhere((step) => !step.isComplete);
    final revertIndex = pendingIndex == -1 ? route.steps.length - 1 : pendingIndex - 1;
    if (revertIndex < 0) return false;

    final stepToRevert = route.steps[revertIndex];
    final steps = route.steps.map((step) {
      if (step.id != stepToRevert.id) return step;
      return step.copyWith(isDone: false, isSkipped: false);
    }).toList();
    final routes = [...project.routes];
    routes[routeIndex] = route.copyWith(steps: steps, currentStepIndex: revertIndex);
    project = project.copyWith(routes: routes);
    project = _clearRouteMeasurement(project, stepToRevert);
    _replaceProject(project);
    await _save();
    return true;
  }

  Future<void> completeRouteStep(
    String projectId,
    String routeId,
    String stepId, {
    int? valueMm,
    bool skipped = false,
  }) async {
    var project = projectById(projectId);
    RouteStepItem? completedStep;
    final routes = project.routes.map((route) {
      if (route.id != routeId) return route;
      final steps = route.steps.map((step) {
        if (step.id != stepId) return step;
        completedStep = step;
        return step.copyWith(isDone: !skipped, isSkipped: skipped);
      }).toList();
      final nextIndex = steps.indexWhere((step) => !step.isComplete);
      return route.copyWith(
        steps: steps,
        currentStepIndex: nextIndex == -1 ? steps.length - 1 : nextIndex,
      );
    }).toList();
    project = project.copyWith(routes: routes);
    if (!skipped && valueMm != null && completedStep != null) {
      project = _applyRouteMeasurement(project, completedStep!, valueMm);
    }
    _replaceProject(project);
    await _save();
  }

  Future<void> resetRouteProgress(String projectId, String routeId) async {
    final project = projectById(projectId);
    final route = project.routes.firstWhere((item) => item.id == routeId);
    if (route.isTemplate) {
      await clearRouteRunState(projectId, routeId);
      return;
    }
    final routes = project.routes.map((item) {
      if (item.id != routeId) return item;
      final steps = item.steps
          .map((step) => step.copyWith(isDone: false, isSkipped: false))
          .toList();
      return item.copyWith(steps: steps, currentStepIndex: 0);
    }).toList();
    _replaceProject(project.copyWith(routes: routes));
    await _save();
  }

  Future<void> addFinishLayer(
    String projectId,
    String roomId,
    String elementId, {
    required String name,
    required int heightMm,
  }) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      final elements = room.elements.map((element) {
        if (element.id != elementId) return element;
        return element.copyWith(
          finishLayers: [
            ...element.finishLayers,
            WallFinishLayer(
              id: createId(),
              name: name.trim().isEmpty ? 'Слой отделки' : name.trim(),
              heightMm: heightMm,
            ),
          ],
        );
      }).toList();
      return room.copyWith(elements: elements);
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  Future<void> deleteFinishLayer(
    String projectId,
    String roomId,
    String elementId,
    String layerId,
  ) async {
    final project = projectById(projectId);
    final rooms = project.rooms.map((room) {
      if (room.id != roomId) return room;
      final elements = room.elements.map((element) {
        if (element.id != elementId) return element;
        return element.copyWith(
          finishLayers: element.finishLayers
              .where((layer) => layer.id != layerId)
              .toList(),
        );
      }).toList();
      return room.copyWith(elements: elements);
    }).toList();
    _replaceProject(project.copyWith(rooms: rooms));
    await _save();
  }

  void _addRoomHeightRouteStep(List<RouteStepItem> steps, Room room) {
    steps.add(
      RouteStepItem(
        id: '${createId()}_${steps.length}',
        title: '${room.name}: высота помещения',
        roomId: room.id,
        elementId: null,
        target: RouteStepTarget.roomHeight,
      ),
    );
  }

  void _addElementRouteSteps(
    List<RouteStepItem> steps,
    Room room,
    RoomElement element,
  ) {
    final isSingleValue = element.type == RoomElementType.height;
    steps.add(
      RouteStepItem(
        id: '${createId()}_${steps.length}',
        title: '${room.name}: ${element.name} - ${isSingleValue ? 'значение' : 'ширина'}',
        roomId: room.id,
        elementId: element.id,
        target: RouteStepTarget.width,
      ),
    );
    if (!isSingleValue && !_skipHeightStep(element, room)) {
      steps.add(
        RouteStepItem(
          id: '${createId()}_${steps.length}',
          title: '${room.name}: ${element.name} - высота',
          roomId: room.id,
          elementId: element.id,
          target: RouteStepTarget.height,
        ),
      );
    }
    if (element.type == RoomElementType.door || element.type == RoomElementType.window) {
      steps.add(
        RouteStepItem(
          id: '${createId()}_${steps.length}',
          title: '${room.name}: ${element.name} - глубина откоса',
          roomId: room.id,
          elementId: element.id,
          target: RouteStepTarget.depth,
        ),
      );
    }
    if (element.type == RoomElementType.window) {
      steps.add(
        RouteStepItem(
          id: '${createId()}_${steps.length}',
          title: '${room.name}: ${element.name} - подоконник',
          roomId: room.id,
          elementId: element.id,
          target: RouteStepTarget.windowsill,
        ),
      );
      steps.add(
        RouteStepItem(
          id: '${createId()}_${steps.length}',
          title: '${room.name}: ${element.name} - ниша под радиатор',
          roomId: room.id,
          elementId: element.id,
          target: RouteStepTarget.radiatorNiche,
        ),
      );
    }
  }

  bool _skipHeightStep(RoomElement element, Room room) {
    return element.type == RoomElementType.wall && room.defaultHeightMm != null;
  }

  Project _clearRouteMeasurement(Project project, RouteStepItem step) {
    if (step.elementId == null) {
      if (step.target != RouteStepTarget.roomHeight) return project;
      final rooms = project.rooms.map((room) {
        if (room.id != step.roomId) return room;
        return room.copyWith(defaultHeightMm: null);
      }).toList();
      return project.copyWith(rooms: rooms);
    }

    final rooms = project.rooms.map((room) {
      if (room.id != step.roomId) return room;
      final elements = room.elements.map((element) {
        if (element.id != step.elementId) return element;
        return switch (step.target) {
          RouteStepTarget.height => element.copyWith(heightMm: null),
          RouteStepTarget.depth => element.copyWith(depthMm: null),
          RouteStepTarget.windowsill => element.copyWith(windowsillMm: null),
          RouteStepTarget.radiatorNiche => element.copyWith(radiatorNicheMm: null),
          RouteStepTarget.width => element.copyWith(
              measurements: element.measurements.isEmpty
                  ? const []
                  : [
                      Measurement(
                        id: element.measurements.first.id,
                        valueMm: 0,
                        createdAt: DateTime.now(),
                        source: 'route',
                        isPrimary: true,
                      ),
                      ...element.measurements.skip(1).map(
                            (item) => Measurement(
                              id: item.id,
                              valueMm: item.valueMm,
                              createdAt: item.createdAt,
                              source: item.source,
                              isPrimary: false,
                            ),
                          ),
                    ],
            ),
          RouteStepTarget.roomHeight => element,
        };
      }).toList();
      return room.copyWith(elements: elements);
    }).toList();
    return project.copyWith(rooms: rooms);
  }

  Project _applyRouteMeasurement(
    Project project,
    RouteStepItem step,
    int valueMm,
  ) {
    if (step.elementId == null) {
      if (step.target != RouteStepTarget.roomHeight) return project;
      final rooms = project.rooms.map((room) {
        if (room.id != step.roomId) return room;
        return room.copyWith(defaultHeightMm: valueMm);
      }).toList();
      return project.copyWith(rooms: rooms);
    }

    final rooms = project.rooms.map((room) {
      if (room.id != step.roomId) return room;
      final elements = room.elements.map((element) {
        if (element.id != step.elementId) return element;
        if (step.target == RouteStepTarget.height) {
          return element.copyWith(heightMm: valueMm);
        }
        if (step.target == RouteStepTarget.depth) {
          return element.copyWith(depthMm: valueMm);
        }
        if (step.target == RouteStepTarget.windowsill) {
          return element.copyWith(windowsillMm: valueMm);
        }
        if (step.target == RouteStepTarget.radiatorNiche) {
          return element.copyWith(radiatorNicheMm: valueMm);
        }
        final existing = element.measurements;
        final measurement = Measurement(
          id: existing.isEmpty ? createId() : existing.first.id,
          valueMm: valueMm,
          createdAt: DateTime.now(),
          source: 'route',
          isPrimary: true,
        );
        return element.copyWith(
          measurements: [
            measurement,
            ...existing.skip(1).map(
                  (item) => Measurement(
                    id: item.id,
                    valueMm: item.valueMm,
                    createdAt: item.createdAt,
                    source: item.source,
                    isPrimary: false,
                  ),
                ),
          ],
        );
      }).toList();
      return room.copyWith(elements: elements);
    }).toList();
    return project.copyWith(rooms: rooms);
  }

  Future<String> exportProjectToExcel(String projectId) async {
    final project = projectById(projectId);
    final directory = await getApplicationDocumentsDirectory();
    final fileName = _safeFileName('${project.name}_${DateTime.now().millisecondsSinceEpoch}.xlsx');
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');

    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Замеры';
    _writeHeader(sheet, project);

    var row = 5;
    for (final room in project.rooms) {
      final geometry = room.geometry;
      _setText(sheet, row, 1, room.name);
      _setText(sheet, row, 2, 'Итого');
      _setNumber(sheet, row, 11, geometry.perimeterMm.toDouble());
      _setNumber(sheet, row, 12, geometry.floorAreaM2);
      _setNumber(sheet, row, 13, geometry.wallAreaM2);
      _setNumber(sheet, row, 14, geometry.openingAreaM2);
      sheet.getRangeByIndex(row, 1, row, 15).cellStyle.bold = true;
      row++;

      for (final element in room.elements) {
        _setText(sheet, row, 1, room.name);
        _setText(sheet, row, 2, element.name);
        _setText(sheet, row, 3, element.type.label);
        _setText(sheet, row, 4, _wallNameForElement(room, element));
        _setNumber(sheet, row, 5, (element.primaryValueMm ?? 0).toDouble());
        _setNumber(sheet, row, 6, (element.heightMm ?? room.defaultHeightMm ?? 0).toDouble());
        _setNumber(sheet, row, 7, (element.depthMm ?? 0).toDouble());
        _setText(sheet, row, 8, element.note);
        _setText(sheet, row, 9, element.measurements.map((item) => item.valueMm).join(', '));
        _setText(sheet, row, 10, element.primaryMeasurement?.source ?? '');
        _setNumber(sheet, row, 11, element.type == RoomElementType.wall ? (element.primaryValueMm ?? 0).toDouble() : 0);
        _setNumber(sheet, row, 14, element.openingAreaM2);
        row++;
        for (final layer in element.finishLayers) {
          _setText(sheet, row, 1, room.name);
          _setText(sheet, row, 2, '${element.name}: ${layer.name}');
          _setText(sheet, row, 3, 'Слой отделки');
          _setNumber(sheet, row, 6, layer.heightMm.toDouble());
          _setNumber(sheet, row, 15, finishLayerAreaM2(room, element, layer));
          row++;
        }
      }
      row++;
    }

    sheet.getRangeByIndex(1, 1, row, 15).autoFitColumns();
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<ProjectPhoto> importPhoto(String projectId, String sourcePath) async {
    final media = await _mediaDirectory;
    final id = createId();
    final extension = sourcePath.split('.').last;
    final destination = File('${media.path}${Platform.pathSeparator}photo_$id.$extension');
    await File(sourcePath).copy(destination.path);

    final project = projectById(projectId);
    final photo = ProjectPhoto(
      id: id,
      path: destination.path,
      createdAt: DateTime.now(),
      annotations: const [],
    );
    _replaceProject(project.copyWith(photos: [photo, ...project.photos]));
    await _save();
    return photo;
  }

  Future<ProjectPdf> importPdf(String projectId, String sourcePath, String name) async {
    final media = await _mediaDirectory;
    final id = createId();
    final destination = File('${media.path}${Platform.pathSeparator}pdf_$id.pdf');
    await File(sourcePath).copy(destination.path);

    final project = projectById(projectId);
    final pdf = ProjectPdf(
      id: id,
      path: destination.path,
      name: name,
      createdAt: DateTime.now(),
      annotations: const [],
      lines: const [],
    );
    _replaceProject(project.copyWith(pdfs: [pdf, ...project.pdfs]));
    await _save();
    return pdf;
  }

  Future<void> addPhotoAnnotation(
    String projectId,
    String photoId, {
    required double x,
    required double y,
  }) async {
    final annotation = PhotoAnnotation(id: createId(), x: x, y: y);
    _activePhotoAnnotationId = annotation.id;
    final project = projectById(projectId);
    final photos = project.photos.map((photo) {
      if (photo.id != photoId) return photo;
      return photo.copyWith(annotations: [...photo.annotations, annotation]);
    }).toList();
    _replaceProject(project.copyWith(photos: photos));
    await _save();
  }

  Future<void> linkPhotoAnnotation(
    String projectId,
    String photoId,
    String annotationId, {
    String? roomId,
    String? elementId,
    String? comment,
    int? measurementMm,
  }) async {
    final measurement = measurementMm == null
        ? null
        : Measurement(
            id: createId(),
            valueMm: measurementMm,
            createdAt: DateTime.now(),
            source: 'rangefinder',
          );
    final project = projectById(projectId);
    final photos = project.photos.map((photo) {
      if (photo.id != photoId) return photo;
      final annotations = photo.annotations.map((annotation) {
        if (annotation.id != annotationId) return annotation;
        return annotation.copyWith(
          roomId: roomId,
          elementId: elementId,
          comment: comment,
          measurement: measurement,
        );
      }).toList();
      return photo.copyWith(annotations: annotations);
    }).toList();
    _activePhotoAnnotationId = annotationId;
    _replaceProject(project.copyWith(photos: photos));
    await _save();
  }

  Future<void> addPdfAnnotation(
    String projectId,
    String pdfId, {
    required int pageIndex,
    required double x,
    required double y,
  }) async {
    final annotation = PdfAnnotation(id: createId(), pageIndex: pageIndex, x: x, y: y);
    _activePdfAnnotationId = annotation.id;
    final project = projectById(projectId);
    final pdfs = project.pdfs.map((pdf) {
      if (pdf.id != pdfId) return pdf;
      return pdf.copyWith(annotations: [...pdf.annotations, annotation]);
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  Future<void> linkPdfAnnotation(
    String projectId,
    String pdfId,
    String annotationId, {
    String? roomId,
    String? elementId,
    int? measurementMm,
  }) async {
    final measurement = measurementMm == null
        ? null
        : Measurement(
            id: createId(),
            valueMm: measurementMm,
            createdAt: DateTime.now(),
            source: 'rangefinder',
          );
    final project = projectById(projectId);
    final pdfs = project.pdfs.map((pdf) {
      if (pdf.id != pdfId) return pdf;
      final annotations = pdf.annotations.map((annotation) {
        if (annotation.id != annotationId) return annotation;
        return annotation.copyWith(
          roomId: roomId,
          elementId: elementId,
          measurement: measurement,
        );
      }).toList();
      return pdf.copyWith(annotations: annotations);
    }).toList();
    _activePdfAnnotationId = annotationId;
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  PhotoAnnotation? activePhotoAnnotation(ProjectPhoto photo) {
    final id = _activePhotoAnnotationId;
    if (id == null) return null;
    for (final annotation in photo.annotations) {
      if (annotation.id == id) return annotation;
    }
    return null;
  }

  PdfAnnotation? activePdfAnnotation(ProjectPdf pdf) {
    final id = _activePdfAnnotationId;
    if (id == null) return null;
    for (final annotation in pdf.annotations) {
      if (annotation.id == id) return annotation;
    }
    return null;
  }

  ProjectPdf? pdfById(Project project, String pdfId) {
    for (final pdf in project.pdfs) {
      if (pdf.id == pdfId) return pdf;
    }
    return null;
  }

  Future<PdfLine> addPdfLine(
    String projectId,
    String pdfId, {
    required int pageIndex,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required String name,
  }) async {
    final project = projectById(projectId);
    final pdf = pdfById(project, pdfId);
    if (pdf == null) throw StateError('PDF не найден');

    final line = PdfLine(
      id: createId(),
      pageIndex: pageIndex,
      name: name.trim(),
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      orderIndex: pdf.lines.length,
    );
    final pdfs = project.pdfs.map((item) {
      if (item.id != pdfId) return item;
      return item.copyWith(lines: [...item.lines, line]);
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
    return line;
  }

  Future<void> updatePdfLineName(
    String projectId,
    String pdfId,
    String lineId,
    String name,
  ) async {
    final project = projectById(projectId);
    final pdfs = project.pdfs.map((pdf) {
      if (pdf.id != pdfId) return pdf;
      final lines = pdf.lines.map((line) {
        if (line.id != lineId) return line;
        return line.copyWith(name: name.trim());
      }).toList();
      return pdf.copyWith(lines: lines);
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  Future<void> updatePdfLineGeometry(
    String projectId,
    String pdfId,
    String lineId, {
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) async {
    final project = projectById(projectId);
    final pdfs = project.pdfs.map((pdf) {
      if (pdf.id != pdfId) return pdf;
      final lines = pdf.lines.map((line) {
        if (line.id != lineId) return line;
        return line.copyWith(
          x1: x1.clamp(0.0, 1.0),
          y1: y1.clamp(0.0, 1.0),
          x2: x2.clamp(0.0, 1.0),
          y2: y2.clamp(0.0, 1.0),
          coordSpace: PdfLineCoordSpace.page,
        );
      }).toList();
      return pdf.copyWith(lines: lines);
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  Future<void> deletePdfLine(String projectId, String pdfId, String lineId) async {
    final project = projectById(projectId);
    final pdfs = project.pdfs.map((pdf) {
      if (pdf.id != pdfId) return pdf;
      final lines = pdf.lines.where((line) => line.id != lineId).toList();
      final reordered = lines.asMap().entries.map((entry) {
        return entry.value.copyWith(orderIndex: entry.key);
      }).toList();
      return pdf.copyWith(lines: reordered);
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  Future<void> reorderPdfLines(
    String projectId,
    String pdfId,
    int oldIndex,
    int newIndex,
  ) async {
    final project = projectById(projectId);
    final pdfs = project.pdfs.map((pdf) {
      if (pdf.id != pdfId) return pdf;
      final lines = [...pdf.sortedLines];
      if (newIndex > oldIndex) newIndex--;
      final item = lines.removeAt(oldIndex);
      lines.insert(newIndex, item);
      final reordered = lines.asMap().entries.map((entry) {
        return entry.value.copyWith(orderIndex: entry.key);
      }).toList();
      return pdf.copyWith(lines: reordered);
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  Future<void> completePdfLineStep(
    String projectId,
    String pdfId,
    String lineId, {
    int? valueMm,
    bool skipped = false,
  }) async {
    final project = projectById(projectId);
    final pdfs = project.pdfs.map((pdf) {
      if (pdf.id != pdfId) return pdf;
      final lines = pdf.lines.map((line) {
        if (line.id != lineId) return line;
        return line.copyWith(
          isDone: !skipped,
          isSkipped: skipped,
          measurementMm: skipped ? line.measurementMm : valueMm,
        );
      }).toList();
      return pdf.copyWith(lines: lines);
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
    await advancePdfRouteAfterLine(projectId, pdfId, lineId);
  }

  Future<void> updatePdfLineMeasurement(
    String projectId,
    String pdfId,
    String lineId, {
    int? valueMm,
    bool clear = false,
    bool remeasure = false,
  }) async {
    final project = projectById(projectId);
    final pdfs = project.pdfs.map((pdf) {
      if (pdf.id != pdfId) return pdf;
      final lines = pdf.lines.map((line) {
        if (line.id != lineId) return line;
        if (clear || remeasure) {
          return line.copyWith(
            clearMeasurement: true,
            isDone: false,
            isSkipped: false,
          );
        }
        return line.copyWith(
          measurementMm: valueMm,
          isDone: valueMm != null,
          isSkipped: false,
        );
      }).toList();
      return pdf.copyWith(
        lines: lines,
        routeCursorLineId: remeasure ? lineId : pdf.routeCursorLineId,
      );
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  Future<void> jumpToPdfLine(
    String projectId,
    String pdfId,
    String lineId,
  ) async {
    final project = projectById(projectId);
    final pdf = pdfById(project, pdfId);
    if (pdf == null || pdf.lineById(lineId) == null) return;

    final pdfs = project.pdfs.map((item) {
      if (item.id != pdfId) return item;
      return item.copyWith(routeCursorLineId: lineId);
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  Future<void> setPdfPageCount(
    String projectId,
    String pdfId,
    int pageCount,
  ) async {
    if (pageCount <= 0) return;
    final project = projectById(projectId);
    final pdfs = project.pdfs.map((pdf) {
      if (pdf.id != pdfId) return pdf;
      if (pdf.pageCount == pageCount) return pdf;
      return pdf.copyWith(pageCount: pageCount);
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  Future<void> advancePdfRouteAfterLine(
    String projectId,
    String pdfId,
    String completedLineId,
  ) async {
    final project = projectById(projectId);
    final pdf = pdfById(project, pdfId);
    if (pdf == null) return;

    final sorted = pdf.sortedLines;
    final completedIndex = sorted.indexWhere((line) => line.id == completedLineId);
    PdfLine? nextLine;
    if (completedIndex != -1) {
      for (var i = completedIndex + 1; i < sorted.length; i++) {
        if (!sorted[i].isComplete) {
          nextLine = sorted[i];
          break;
        }
      }
    }
    if (nextLine == null) {
      for (final item in sorted) {
        if (!item.isComplete) {
          nextLine = item;
          break;
        }
      }
    }

    final pdfs = project.pdfs.map((item) {
      if (item.id != pdfId) return item;
      return item.copyWith(
        routeCursorLineId: nextLine?.id,
        clearRouteCursor: nextLine == null,
      );
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  Future<bool> revertPdfLineStep(String projectId, String pdfId) async {
    final project = projectById(projectId);
    final pdf = pdfById(project, pdfId);
    if (pdf == null || pdf.lines.isEmpty) return false;

    final pendingIndex = pdf.sortedLines.indexWhere((line) => !line.isComplete);
    final revertIndex = pendingIndex == -1 ? pdf.sortedLines.length - 1 : pendingIndex - 1;
    if (revertIndex < 0) return false;

    final lineToRevert = pdf.sortedLines[revertIndex];
    final pdfs = project.pdfs.map((item) {
      if (item.id != pdfId) return item;
      final lines = item.lines.map((line) {
        if (line.id != lineToRevert.id) return line;
        return line.copyWith(
          isDone: false,
          isSkipped: false,
          clearMeasurement: true,
        );
      }).toList();
      return item.copyWith(
        lines: lines,
        routeCursorLineId: lineToRevert.id,
      );
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
    return true;
  }

  Future<void> resetPdfRouteProgress(String projectId, String pdfId) async {
    final project = projectById(projectId);
    final pdfs = project.pdfs.map((pdf) {
      if (pdf.id != pdfId) return pdf;
      final lines = pdf.lines
          .map(
            (line) => line.copyWith(
              isDone: false,
              isSkipped: false,
              measurementMm: null,
            ),
          )
          .toList();
      return pdf.copyWith(
        lines: lines,
        clearRouteCursor: true,
      );
    }).toList();
    _replaceProject(project.copyWith(pdfs: pdfs));
    await _save();
  }

  Project projectById(String id) => _projects.firstWhere((project) => project.id == id);

  Room roomById(Project project, String id) => project.rooms.firstWhere((room) => room.id == id);

  RoomElement? elementById(Project project, String? id) {
    if (id == null) return null;
    for (final room in project.rooms) {
      for (final element in room.elements) {
        if (element.id == id) return element;
      }
    }
    return null;
  }

  Future<void> undoLast() async {
    if (_undoStack.isEmpty) return;
    _projects
      ..clear()
      ..addAll(_undoStack.removeLast());
    notifyListeners();
    await _save();
  }

  void _replaceProject(Project project, {bool recordUndo = true}) {
    final index = _projects.indexWhere((item) => item.id == project.id);
    if (index == -1) return;
    if (recordUndo) _recordUndo();
    _projects[index] = project;
    notifyListeners();
  }

  void _recordUndo() {
    final snapshot = _projects
        .map((project) => Project.fromJson(project.toJson()))
        .toList(growable: false);
    _undoStack.add(snapshot);
    if (_undoStack.length > _undoLimit) {
      _undoStack.removeAt(0);
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final file = await _storeFile;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'themeMode': _themeMode.name,
        'showOnboarding': _showOnboarding,
        'projects': _projects.map((project) => project.toJson()).toList(),
      }),
    );
  }

  Project _seedProject() {
    final room = Room(
      id: createId(),
      name: 'Пом 1',
      defaultHeightMm: 2450,
      elements: [
        _seedElement(RoomElementType.door, 'Дверь 1', 2100),
        _seedElement(RoomElementType.wall, 'Стена 1', 2450),
        _seedElement(RoomElementType.wall, 'Стена 2', 2450),
      ],
    );
    return Project(
      id: createId(),
      name: 'Проект 1',
      description: 'Демо-проект для проверки фото, PDF и замеров',
      createdAt: DateTime.now(),
      rooms: [room],
      photos: const [],
      pdfs: const [],
    );
  }

  RoomElement _seedElement(RoomElementType type, String name, int valueMm) {
    return RoomElement(
      id: createId(),
      name: name,
      type: type,
      heightMm: valueMm,
      measurements: [
        Measurement(id: createId(), valueMm: valueMm, createdAt: DateTime.now(), source: 'seed'),
        Measurement(
          id: createId(),
          valueMm: valueMm,
          createdAt: DateTime.now(),
          source: 'seed',
          isPrimary: false,
        ),
      ],
    );
  }

  void _writeHeader(xlsio.Worksheet sheet, Project project) {
    _setText(sheet, 1, 1, 'Проект');
    _setText(sheet, 1, 2, project.name);
    _setText(sheet, 2, 1, 'Дата экспорта');
    _setText(sheet, 2, 2, DateTime.now().toIso8601String());
    final headers = [
      'Помещение',
      'Элемент',
      'Тип',
      'Стена',
      'Ширина/длина, мм',
      'Высота, мм',
      'Глубина, мм',
      'Примечание',
      'Серия замеров, мм',
      'Источник',
      'Периметр, мм',
      'Площадь пола, м2',
      'Площадь стен, м2',
      'Площадь проёмов, м2',
      'Площадь слоя, м2',
    ];
    for (var index = 0; index < headers.length; index++) {
      _setText(sheet, 4, index + 1, headers[index]);
    }
    sheet.getRangeByIndex(4, 1, 4, headers.length).cellStyle.bold = true;
  }

  void _setText(xlsio.Worksheet sheet, int row, int column, String value) {
    sheet.getRangeByIndex(row, column).setText(value);
  }

  void _setNumber(xlsio.Worksheet sheet, int row, int column, double value) {
    sheet.getRangeByIndex(row, column).setNumber(value);
  }

  String _safeFileName(String value) {
    return value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String? _openingWallId(RoomElementType type, String? wallElementId) {
    return switch (type) {
      RoomElementType.door || RoomElementType.window || RoomElementType.opening || RoomElementType.slope =>
        wallElementId,
      RoomElementType.wall || RoomElementType.height => null,
    };
  }

  String _wallNameForElement(Room room, RoomElement element) {
    final wallId = element.wallElementId;
    if (wallId == null) return '';
    for (final wall in room.elements) {
      if (wall.id == wallId) return wall.name;
    }
    return '';
  }

  double finishLayerAreaM2(Room room, RoomElement wall, WallFinishLayer layer) {
    final width = wall.primaryValueMm;
    if (width == null || wall.type != RoomElementType.wall) return 0;
    final wallOpeningArea = room.elements
        .where((element) => element.wallElementId == wall.id)
        .fold<double>(0, (sum, element) => sum + element.openingAreaM2);
    final area = width * layer.heightMm / 1000000 - wallOpeningArea;
    return area < 0 ? 0 : area;
  }
}
