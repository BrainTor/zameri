import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'core/theme/app_theme.dart';
import 'features/measurements/app_state.dart';
import 'features/measurements/models.dart';
import 'features/pdf/pdf_screens.dart';
import 'features/rangefinder/rangefinder.dart';

const _roomAddElementTypes = [
  RoomElementType.wall,
  RoomElementType.door,
  RoomElementType.window,
  RoomElementType.opening,
];

const _routeBlueprintTypes = [
  RoomElementType.wall,
  RoomElementType.door,
  RoomElementType.window,
  RoomElementType.opening,
  RoomElementType.height,
];

const _routeRoomTemplate = '__template__';
const _routeRoomNew = '__new__';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.load();
  final rangefinder = RangefinderController();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: rangefinder),
      ],
      child: const ZameriApp(),
    ),
  );
}

class ZameriApp extends StatelessWidget {
  const ZameriApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppState, ThemeMode>((state) => state.themeMode);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'Замеры',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const ProjectsScreen(),
    );
  }
}

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.shouldPromptOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.read<AppState>().markOnboardingPrompted();
        _showOnboarding(context);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Проекты'),
        actions: [
          IconButton(
            tooltip: 'Тема',
            onPressed: () => _showThemeSheet(context),
            icon: const Icon(Icons.settings_outlined),
          ),
          const _UndoButton(),
          const _RangefinderStatusIcon(),
        ],
      ),
      body: state.projects.isEmpty
          ? const _EmptyState(icon: Icons.folder_open, text: 'Нет проектов')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              itemBuilder: (context, index) => _ProjectCard(project: state.projects[index]),
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemCount: state.projects.length,
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProjectDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Проект'),
      ),
    );
  }

  Future<void> _showThemeSheet(BuildContext context) async {
    final state = context.read<AppState>();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Тема приложения', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                groupValue: state.themeMode,
                onChanged: (value) {
                  if (value != null) state.setThemeMode(value);
                  Navigator.pop(context);
                },
                title: const Text('Как в системе'),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                groupValue: state.themeMode,
                onChanged: (value) {
                  if (value != null) state.setThemeMode(value);
                  Navigator.pop(context);
                },
                title: const Text('Светлая'),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                groupValue: state.themeMode,
                onChanged: (value) {
                  if (value != null) state.setThemeMode(value);
                  Navigator.pop(context);
                },
                title: const Text('Тёмная'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('Показать обучалку'),
                onTap: () {
                  Navigator.pop(context);
                  _showOnboarding(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showProjectDialog(BuildContext context) async {
    final name = TextEditingController(text: 'Проект ${context.read<AppState>().projects.length + 1}');
    final description = TextEditingController();
    MeasurementUnit unit = MeasurementUnit.millimeters;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Новый проект'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Описание'),
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MeasurementUnit>(
                value: unit,
                decoration: const InputDecoration(labelText: 'Единицы измерения'),
                items: MeasurementUnit.values
                    .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => unit = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => _closeUnsavedForm(context), child: const Text('Отмена')),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                await context.read<AppState>().createProject(
                      name: name.text.trim(),
                      description: description.text.trim(),
                      unit: unit,
                    );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showOnboarding(BuildContext context) {
  var dontShowAgain = false;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Как работать с приложением', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const _OnboardingLine(icon: Icons.folder_outlined, text: 'Создайте проект, затем помещение и элементы.'),
              const _OnboardingLine(icon: Icons.straighten, text: 'Активное поле размера автоматически принимает новый замер дальномера.'),
              const _OnboardingLine(icon: Icons.star, text: 'В серии замеров звезда выбирает основной замер для расчётов.'),
              const _OnboardingLine(icon: Icons.route_outlined, text: 'Маршрут ведёт по шагам: снять или пропустить.'),
              const _OnboardingLine(icon: Icons.undo, text: 'Кнопка Undo отменяет последнее сохранённое действие.'),
              CheckboxListTile(
                value: dontShowAgain,
                contentPadding: EdgeInsets.zero,
                title: const Text('Больше не показывать'),
                onChanged: (value) => setState(() => dontShowAgain = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (dontShowAgain) {
                      await context.read<AppState>().setShowOnboarding(false);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Понятно'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OnboardingLine extends StatelessWidget {
  const _OnboardingLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => ProjectScreen(projectId: project.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showProjectEditor(context, project: project);
                      }
                      if (value == 'delete') {
                        _confirmDeleteProject(context, project);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                      PopupMenuItem(value: 'delete', child: Text('Удалить')),
                    ],
                  ),
                ],
              ),
              if (project.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(project.description),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(icon: Icons.calendar_month_outlined, text: _formatDate(project.createdAt)),
                  _InfoChip(icon: Icons.straighten, text: project.unit.label),
                  _InfoChip(icon: Icons.door_front_door_outlined, text: '${project.rooms.length} пом.'),
                  _InfoChip(icon: Icons.photo_outlined, text: '${project.photos.length} фото'),
                  _InfoChip(icon: Icons.picture_as_pdf_outlined, text: '${project.pdfs.length} PDF'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProjectScreen extends StatelessWidget {
  const ProjectScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = _projectOrNull(state, projectId);
    if (project == null) {
      return const _MissingEntityScreen(message: 'Проект больше недоступен');
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          IconButton(
            tooltip: 'Редактировать проект',
            onPressed: () => _showProjectEditor(context, project: project),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Удалить проект',
            onPressed: () => _confirmDeleteProject(context, project, popAfterDelete: true),
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Экспорт Excel',
            onPressed: () => _exportProject(context, project.id),
            icon: const Icon(Icons.ios_share),
          ),
          const _UndoButton(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Параметры', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text('Единицы: ${project.unit.label}'),
                  Text('Точность: ${project.precisionMm} мм'),
                  Text('Помещений: ${project.rooms.length}'),
                  Text('Маршрутов: ${project.routes.length}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 52) / 2,
                child: _ActionTile(
                  icon: Icons.photo_camera_outlined,
                  label: 'Фото',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => PhotosScreen(projectId: project.id)),
                  ),
                ),
              ),
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 52) / 2,
                child: _ActionTile(
                  icon: Icons.draw_outlined,
                  label: 'PDF разметка',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => PdfMarkupScreen(projectId: project.id)),
                  ),
                ),
              ),
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 52) / 2,
                child: _ActionTile(
                  icon: Icons.route_outlined,
                  label: 'PDF маршрут',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => PdfRouteRunScreen(projectId: project.id)),
                  ),
                ),
              ),
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 52) / 2,
                child: _ActionTile(
                  icon: Icons.route_outlined,
                  label: 'Маршрут',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => RoutesScreen(projectId: project.id)),
                  ),
                ),
              ),
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 52) / 2,
                child: _ActionTile(
                  icon: Icons.table_chart_outlined,
                  label: 'Excel',
                  onTap: () => _exportProject(context, project.id),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _ProjectGeometryCard(project: project),
          if (project.routes.isNotEmpty) ...[
            const SizedBox(height: 24),
            _RoutePreviewCard(projectId: project.id, route: project.routes.first),
          ],
          const SizedBox(height: 24),
          Text('Помещения', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (project.rooms.isEmpty)
            const _EmptyState(icon: Icons.meeting_room_outlined, text: 'Нет помещений')
          else
            ...project.rooms.map(
              (room) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    title: Text(room.name),
                    subtitle: Text('Высота по умолчанию: ${room.defaultHeightMm == null ? 'не задана' : '${room.defaultHeightMm} мм'}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _showRoomEditor(context, project.id, room);
                        }
                        if (value == 'delete') {
                          _confirmDeleteRoom(context, project.id, room);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                        PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => RoomScreen(projectId: project.id, roomId: room.id),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRoomDialog(context, project.id),
        icon: const Icon(Icons.add),
        label: const Text('Помещение'),
      ),
    );
  }

  Future<void> _showRoomDialog(BuildContext context, String projectId) async {
    final name = TextEditingController(text: 'Пом ${context.read<AppState>().projectById(projectId).rooms.length + 1}');
    final height = TextEditingController();
    final wall1Width = TextEditingController();
    final wall1Height = TextEditingController();
    final wall2Width = TextEditingController();
    final wall2Height = TextEditingController();
    var rectangular = false;
    var polygonal = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final roomHeightMm = int.tryParse(height.text.trim());
          return AlertDialog(
          title: const Text('Новое помещение'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
                const SizedBox(height: 12),
                TextField(
                  controller: height,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Высота потолка, мм',
                    helperText: 'Применяется ко всем стенам помещения по умолчанию',
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: rectangular,
                  onChanged: (value) => setState(() {
                    rectangular = value ?? false;
                    if (rectangular) polygonal = false;
                  }),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Прямоугольное помещение'),
                  subtitle: Text(
                    roomHeightMm == null
                        ? 'Сразу задать ширину и высоту двух стен'
                        : 'Сразу задать ширину двух стен — высота возьмётся из поля выше',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: polygonal,
                  onChanged: (value) => setState(() {
                    polygonal = value ?? false;
                    if (polygonal) rectangular = false;
                  }),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Многоугольное помещение'),
                  subtitle: const Text('Стороны задаются стенами по порядку. Периметр считается точно, площадь не рассчитывается без координат.'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (rectangular) ...[
                  const SizedBox(height: 8),
                  _MeasureTextField(
                    controller: wall1Width,
                    labelText: 'Ширина стены 1, мм',
                  ),
                  const SizedBox(height: 12),
                  _MeasureTextField(
                    controller: wall2Width,
                    labelText: 'Ширина стены 2, мм',
                  ),
                  if (roomHeightMm == null) ...[
                    const SizedBox(height: 12),
                    _MeasureTextField(
                      controller: wall1Height,
                      labelText: 'Высота стены 1, мм',
                    ),
                    const SizedBox(height: 12),
                    _MeasureTextField(
                      controller: wall2Height,
                      labelText: 'Высота стены 2, мм',
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => _closeUnsavedForm(context), child: const Text('Отмена')),
            FilledButton(
              onPressed: () async {
                final wall1WidthMm = int.tryParse(wall1Width.text.trim());
                final roomHeightMm = int.tryParse(height.text.trim());
                final wall1HeightMm = int.tryParse(wall1Height.text.trim()) ?? roomHeightMm;
                final wall2WidthMm = int.tryParse(wall2Width.text.trim());
                final wall2HeightMm = int.tryParse(wall2Height.text.trim()) ?? roomHeightMm;
                if (rectangular) {
                  if (wall1WidthMm == null || wall2WidthMm == null) {
                    _showSnack(context, 'Введите ширину двух стен');
                    return;
                  }
                  if (wall1HeightMm == null || wall2HeightMm == null) {
                    _showSnack(context, 'Укажите высоту помещения или высоту каждой стены');
                    return;
                  }
                }
                await context.read<AppState>().addRoom(
                      projectId,
                      name.text.trim().isEmpty ? 'Помещение' : name.text.trim(),
                      defaultHeightMm: roomHeightMm,
                      isPolygonal: polygonal,
                      wall1WidthMm: rectangular ? wall1WidthMm : null,
                      wall1HeightMm: rectangular ? wall1HeightMm : null,
                      wall2WidthMm: rectangular ? wall2WidthMm : null,
                      wall2HeightMm: rectangular ? wall2HeightMm : null,
                    );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Создать'),
            ),
          ],
        );
        },
      ),
    );
  }

  Future<void> _exportProject(BuildContext context, String projectId) async {
    try {
      // TODO: спрашивать путь сохранения или отправку (Telegram, почта).
      final path = await context.read<AppState>().exportProjectToExcel(projectId);
      if (context.mounted) _showSnack(context, 'Excel сохранён: $path');
    } catch (error) {
      if (context.mounted) _showSnack(context, 'Не удалось экспортировать Excel: $error');
    }
  }
}

class _ProjectGeometryCard extends StatelessWidget {
  const _ProjectGeometryCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final floorArea = project.rooms.fold<double>(0, (sum, room) => sum + room.geometry.floorAreaM2);
    final wallArea = project.rooms.fold<double>(0, (sum, room) => sum + room.geometry.wallAreaM2);
    final openings = project.rooms.fold<double>(0, (sum, room) => sum + room.geometry.openingAreaM2);
    final perimeter = project.rooms.fold<int>(0, (sum, room) => sum + room.geometry.perimeterMm);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Автоматические расчёты', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _MetricRow(label: 'Площадь пола', value: _formatArea(floorArea)),
            _MetricRow(label: 'Площадь стен', value: _formatArea(wallArea)),
            _MetricRow(label: 'Периметр', value: _formatLength(perimeter)),
            _MetricRow(label: 'Площадь проёмов', value: _formatArea(openings)),
          ],
        ),
      ),
    );
  }
}

class _RoutePreviewCard extends StatelessWidget {
  const _RoutePreviewCard({required this.projectId, required this.route});

  final String projectId;
  final MeasurementRoute route;

  @override
  Widget build(BuildContext context) {
    final currentStep = route.currentStep;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(route.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Chip(label: Text('${route.completedCount}/${route.steps.length}')),
              ],
            ),
            const SizedBox(height: 8),
            Text(currentStep == null ? 'Нет шагов' : 'Текущий шаг: ${currentStep.title}'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => RouteRunScreen(projectId: projectId, routeId: route.id),
                ),
              ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Пойти по маршруту'),
            ),
          ],
        ),
      ),
    );
  }
}

class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final project = context.watch<AppState>().projectById(projectId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Маршруты'),
        actions: const [_UndoButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.route_outlined, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Маршрут — шаблон замеров для типовых помещений. Один раз настройте последовательность, '
                      'затем в каждом помещении нажмите «Старт» и просто стреляйте дальномером — приложение само запишет размеры.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CreateRouteScreen(projectId: project.id),
                        ),
                      ),
                  icon: const Icon(Icons.add_task),
                  label: const Text('Создать маршрут'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: project.routes.isEmpty
                      ? null
                      : () => _showRoutePicker(context, project),
                  icon: const Icon(Icons.directions_walk),
                  label: const Text('Пойти по маршруту'),
                ),
              ),
            ],
            ),
          const SizedBox(height: 16),
          if (project.routes.isEmpty)
            const _EmptyState(icon: Icons.route_outlined, text: 'Нет маршрутов')
          else
            ...project.routes.map(
              (route) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RouteCard(projectId: project.id, route: route),
              ),
            ),
        ],
      ),
    );
  }

  void _showRoutePicker(BuildContext context, Project project) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            Text('Выберите маршрут', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...project.routes.map(
              (route) => ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text(route.name),
                subtitle: Text(route.isComplete
                    ? 'Готово, можно запустить заново'
                    : '${route.completedCount}/${route.steps.length} шагов'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  if (route.isTemplate && route.steps.isEmpty) {
                    _startTemplateRoute(context, project.id, route);
                  } else {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => RouteRunScreen(projectId: project.id, routeId: route.id),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.projectId, required this.route});

  final String projectId;
  final MeasurementRoute route;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentStep = route.currentStep;
    final isTemplateRoute = route.isTemplate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(route.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (isTemplateRoute)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(label: Text('Шаблон · ${route.blueprint.length}')),
                  ),
                if (!isTemplateRoute)
                  Chip(label: Text(route.isComplete ? 'Готово' : '${route.completedCount}/${route.steps.length}')),
                if (isTemplateRoute)
                  IconButton(
                    tooltip: 'Редактировать маршрут',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CreateRouteScreen(projectId: projectId, routeId: route.id),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                IconButton(
                  tooltip: 'Удалить маршрут',
                  onPressed: () async {
                    final confirmed = await _confirm(context, 'Удалить маршрут «${route.name}»?');
                    if (!confirmed || !context.mounted) return;
                    _dismissAllSnacks(context);
                    await context.read<AppState>().deleteRoute(projectId, route.id);
                    if (context.mounted) _showBriefSnack(context, 'Маршрут удалён');
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (isTemplateRoute) ...[
              const SizedBox(height: 10),
              Text(
                route.blueprint.isEmpty
                    ? 'Пустой шаблон'
                    : 'Последовательность: ${route.blueprint.map((item) => item.type == RoomElementType.height ? 'высота' : item.name).join(' → ')}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ] else ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: route.steps.isEmpty ? 0 : route.completedCount / route.steps.length,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 14),
              Text(currentStep == null ? 'Шагов нет' : 'Текущий шаг: ${currentStep.title}'),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isTemplateRoute
                        ? () => _startTemplateRoute(context, projectId, route)
                        : () {
                            _dismissAllSnacks(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => RouteRunScreen(projectId: projectId, routeId: route.id),
                              ),
                            );
                          },
                    icon: const Icon(Icons.directions_walk),
                    label: Text(isTemplateRoute ? 'Запустить' : route.isComplete ? 'Открыть' : 'Пойти'),
                  ),
                ),
                if (!isTemplateRoute && route.completedCount > 0) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await context.read<AppState>().resetRouteProgress(projectId, route.id);
                        if (!context.mounted) return;
                        _dismissAllSnacks(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => RouteRunScreen(projectId: projectId, routeId: route.id),
                          ),
                        );
                      },
                      icon: const Icon(Icons.replay),
                      label: const Text('Заново'),
                    ),
                  ),
                ],
              ],
            ),
            if (route.isComplete && !isTemplateRoute) ...[
              const SizedBox(height: 8),
              Text(
                'Маршрут завершён. Нажмите «Заново», чтобы пройти его повторно.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (!isTemplateRoute) ...[
              const SizedBox(height: 8),
              ...route.steps.map(
                (step) => CheckboxListTile(
                  value: step.isComplete,
                  contentPadding: EdgeInsets.zero,
                  title: Text(step.title),
                  subtitle: step.isSkipped
                      ? const Text('Пропущено')
                      : step.id == currentStep?.id && !step.isComplete
                          ? const Text('Текущий шаг')
                          : null,
                  onChanged: step.isComplete
                      ? null
                      : (_) => context.read<AppState>().completeRouteStep(projectId, route.id, step.id),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CreateRouteScreen extends StatefulWidget {
  const CreateRouteScreen({super.key, required this.projectId, this.routeId});

  final String projectId;
  final String? routeId;

  @override
  State<CreateRouteScreen> createState() => _CreateRouteScreenState();
}

class _CreateRouteScreenState extends State<CreateRouteScreen> {
  final _nameController = TextEditingController(text: 'Маршрут прямоугольник');
  final _newRoomNameController = TextEditingController(text: 'Помещение');
  final _newRoomHeightController = TextEditingController();
  String _roomMode = _routeRoomTemplate;
  List<RouteBlueprintItem> _blueprintItems = [];
  bool _loadedExistingRoute = false;

  bool get _isEditing => widget.routeId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExistingRoute());
    }
  }

  void _loadExistingRoute() {
    if (!mounted || _loadedExistingRoute) return;
    final project = context.read<AppState>().projectById(widget.projectId);
    final matches = project.routes.where((item) => item.id == widget.routeId);
    if (matches.isEmpty) return;
    final route = matches.first;
    setState(() {
      _loadedExistingRoute = true;
      _nameController.text = route.name;
      _blueprintItems = [...route.blueprint];
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _newRoomNameController.dispose();
    _newRoomHeightController.dispose();
    super.dispose();
  }

  Future<void> _addBlueprintItem() async {
    var selectedType = RoomElementType.wall;
    final count = _blueprintItems.where((item) => item.type == selectedType).length + 1;
    final nameController = TextEditingController(text: '${selectedType.label} $count');
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Добавить элемент'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<RoomElementType>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Тип'),
                items: _routeBlueprintTypes
                    .map((type) => DropdownMenuItem(value: type, child: Text(type.label)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    selectedType = value;
                    final nextCount = _blueprintItems.where((item) => item.type == value).length + 1;
                    nameController.text = value == RoomElementType.height
                        ? 'Высота помещения'
                        : '${value.label} $nextCount';
                  });
                },
              ),
              const SizedBox(height: 12),
              _MeasureTextField(controller: nameController, labelText: 'Название', enableRangefinder: false),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Добавить')),
          ],
        ),
      ),
    );
    if (added != true || !mounted) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _blueprintItems = [
        ..._blueprintItems,
        RouteBlueprintItem(id: createId(), name: name, type: selectedType),
      ];
    });
  }

  Future<void> _saveTemplate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack(context, 'Введите название маршрута');
      return;
    }
    if (_blueprintItems.isEmpty) {
      _showSnack(context, 'Добавьте хотя бы один элемент');
      return;
    }
    if (_isEditing) {
      await context.read<AppState>().updateRouteTemplate(
            widget.projectId,
            widget.routeId!,
            name: name,
            blueprint: _blueprintItems,
          );
    } else {
      await context.read<AppState>().createRouteTemplate(
            widget.projectId,
            name: name,
            blueprint: _blueprintItems,
          );
    }
    if (!mounted) return;
    _dismissAllSnacks(context);
    Navigator.pop(context);
    _showBriefSnack(context, _isEditing ? 'Маршрут обновлён' : 'Шаблон сохранён');
  }

  void _fillRectanglePreset() {
    setState(() {
      _nameController.text = 'Прямоугольное помещение';
      _blueprintItems = [
        RouteBlueprintItem(id: createId(), name: 'Стена 1', type: RoomElementType.wall),
        RouteBlueprintItem(id: createId(), name: 'Стена 2', type: RoomElementType.wall),
        RouteBlueprintItem(id: createId(), name: 'Высота помещения', type: RoomElementType.height),
        RouteBlueprintItem(id: createId(), name: 'Дверь 1', type: RoomElementType.door),
        RouteBlueprintItem(id: createId(), name: 'Окно 1', type: RoomElementType.window),
      ];
    });
  }

  Future<void> _startRoute() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack(context, 'Введите название маршрута');
      return;
    }
    if (_blueprintItems.isEmpty) {
      _showSnack(context, 'Добавьте хотя бы один элемент');
      return;
    }
    if (_roomMode == _routeRoomTemplate) {
      _showSnack(context, 'Выберите помещение или «Создать новое»');
      return;
    }

    final appState = context.read<AppState>();
    var project = appState.projectById(widget.projectId);
    String roomId;
    if (_roomMode == _routeRoomNew) {
      final roomName = _newRoomNameController.text.trim();
      if (roomName.isEmpty) {
        _showSnack(context, 'Введите название помещения');
        return;
      }
      await appState.addRoom(
        widget.projectId,
        roomName,
        defaultHeightMm: int.tryParse(_newRoomHeightController.text.trim()),
      );
      project = appState.projectById(widget.projectId);
      roomId = project.rooms.last.id;
    } else {
      roomId = _roomMode;
    }

    final route = await appState.createRouteTemplate(
      widget.projectId,
      name: name,
      blueprint: _blueprintItems,
    );
    await appState.launchRouteInRoom(widget.projectId, route.id, roomId);
    if (!mounted) return;
    _dismissAllSnacks(context);
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RouteRunScreen(projectId: widget.projectId, routeId: route.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = context.watch<AppState>().projectById(widget.projectId);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Редактировать маршрут' : 'Создать маршрут')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          _MeasureTextField(
            controller: _nameController,
            labelText: 'Название маршрута',
            hintText: 'Например: Прямоугольник или Буква Г',
            enableRangefinder: false,
          ),
          if (!_isEditing) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _roomMode,
              decoration: const InputDecoration(labelText: 'Помещение'),
              items: [
                const DropdownMenuItem(value: _routeRoomTemplate, child: Text('Только шаблон (без помещения)')),
                const DropdownMenuItem(value: _routeRoomNew, child: Text('Создать новое помещение')),
                ...project.rooms.map(
                  (room) => DropdownMenuItem(value: room.id, child: Text(room.name)),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _roomMode = value);
              },
            ),
            if (_roomMode == _routeRoomNew) ...[
              const SizedBox(height: 12),
              _MeasureTextField(
                controller: _newRoomNameController,
                labelText: 'Название помещения',
                enableRangefinder: false,
              ),
              const SizedBox(height: 12),
              _MeasureTextField(
                controller: _newRoomHeightController,
                labelText: 'Высота помещения, мм',
                helperText: 'Задайте один раз — высота подставится ко всем стенам в маршруте',
              ),
            ],
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Элементы и порядок',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _addBlueprintItem,
                icon: const Icon(Icons.add),
                label: const Text('Элемент'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Добавьте стены, проёмы и шаг «Высота» для замера потолка. Перетащите в порядке обхода. Для стен с заданной высотой помещения маршрут попросит только ширину.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'На объекте: зайдите в помещение → нажмите «Старт» у маршрута → просто стреляйте дальномером. Приложение само запишет размер и перейдёт к следующему шагу.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _fillRectanglePreset,
            icon: const Icon(Icons.crop_square),
            label: const Text('Шаблон: прямоугольник (2 стены + дверь + окно)'),
          ),
          const SizedBox(height: 12),
          if (_blueprintItems.isEmpty)
            const _EmptyState(icon: Icons.playlist_add, text: 'Добавьте элементы маршрута')
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _blueprintItems.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _blueprintItems.removeAt(oldIndex);
                  _blueprintItems.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final item = _blueprintItems[index];
                return Card(
                  key: ValueKey(item.id),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(item.name),
                    subtitle: Text(
                      item.type == RoomElementType.height ? 'Высота помещения' : item.type.label,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() {
                            _blueprintItems = _blueprintItems.where((entry) => entry.id != item.id).toList();
                          }),
                        ),
                        const Icon(Icons.drag_handle),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: _isEditing
              ? FilledButton.icon(
                  onPressed: _blueprintItems.isEmpty ? null : _saveTemplate,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Сохранить изменения'),
                )
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _blueprintItems.isEmpty ? null : _saveTemplate,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Сохранить шаблон'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _blueprintItems.isEmpty ? null : _startRoute,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Начать маршрут'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class RouteRunScreen extends StatefulWidget {
  const RouteRunScreen({super.key, required this.projectId, required this.routeId});

  final String projectId;
  final String routeId;

  @override
  State<RouteRunScreen> createState() => _RouteRunScreenState();
}

class _RouteRunScreenState extends State<RouteRunScreen> {
  StreamSubscription<RangefinderReading>? _readingSub;
  String? _armedStepId;
  String? _trackedStepId;
  DateTime _armedAt = DateTime.now();
  bool _busy = false;
  int? _lastAppliedValue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _dismissAllSnacks(context);
        _ensureAutoMode();
      }
    });
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    super.dispose();
  }

  Future<void> _leaveRoute() async {
    final route = _currentRoute();
    if (route?.isTemplate ?? false) {
      await context.read<AppState>().clearRouteRunState(widget.projectId, widget.routeId);
    }
    if (mounted) Navigator.pop(context);
  }

  MeasurementRoute? _currentRoute() {
    final state = context.read<AppState>();
    final project = _projectOrNull(state, widget.projectId);
    if (project == null) return null;
    return _routeOrNull(project, widget.routeId);
  }

  Future<void> _ensureAutoMode() async {
    final route = _currentRoute();
    final step = route?.currentStep;
    if (route == null || step == null || route.isComplete) {
      _readingSub?.cancel();
      _readingSub = null;
      return;
    }

    if (_armedStepId != step.id) {
      _armedStepId = step.id;
      _armedAt = DateTime.now();
      _lastAppliedValue = null;
    }

    _readingSub ??= context.read<RangefinderController>().readings.listen(_onReading);

    final rangefinder = context.read<RangefinderController>();
    if (rangefinder.status != RangefinderStatus.connected && !rangefinder.testMode) {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => const RangefinderScreen()),
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

    final route = _currentRoute();
    final step = route?.currentStep;
    if (route == null || step == null || step.isComplete || route.isComplete) return;
    if (_armedStepId != step.id) return;

    _busy = true;
    _lastAppliedValue = reading.valueMm;
    await context.read<AppState>().completeRouteStep(
          widget.projectId,
          route.id,
          step.id,
          valueMm: reading.valueMm,
        );
    _busy = false;
    if (!mounted) return;
    _armedStepId = null;
    _ensureAutoMode();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final rangefinder = context.watch<RangefinderController>();
    final project = _projectOrNull(state, widget.projectId);
    final route = project == null ? null : _routeOrNull(project, widget.routeId);
    if (project == null || route == null) {
      return const _MissingEntityScreen(message: 'Маршрут больше недоступен');
    }
    final step = route.currentStep;
    final room = step == null ? null : _roomOrNull(project, step.roomId);
    final element = step?.elementId == null ? null : _elementOrNull(room, step!.elementId!);
    final progress = route.steps.isEmpty ? 0.0 : route.completedCount / route.steps.length;

    if (step != null && !route.isComplete && step.id != _trackedStepId) {
      _trackedStepId = step.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureAutoMode();
      });
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          final route = _currentRoute();
          if (route?.isTemplate ?? false) {
            context.read<AppState>().clearRouteRunState(widget.projectId, widget.routeId);
          }
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(route.name),
        actions: [
          TextButton(
            onPressed: _busy ? null : _leaveRoute,
            child: const Text('Отменить'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: step == null
            ? const _EmptyState(icon: Icons.route_outlined, text: 'В маршруте нет шагов')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 12),
                  Text('${route.completedCount}/${route.steps.length} шагов'),
                  if (!route.isComplete) ...[
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
                                    ? 'Автоматический режим: стреляйте дальномером'
                                    : 'Подключите дальномер для автоматических замеров',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.isComplete ? 'Маршрут завершён' : step.target.label,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          _MetricRow(label: 'Помещение', value: room?.name ?? '-'),
                          _MetricRow(label: 'Элемент', value: element?.name ?? (step.target == RouteStepTarget.roomHeight ? 'Помещение' : '-')),
                          _MetricRow(label: 'Тип', value: element?.type.label ?? step.target.label),
                          _MetricRow(label: 'Текущее значение', value: _routeStepCurrentValue(step, element, room)),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (route.isComplete)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _restartRoute(context, route),
                          icon: const Icon(Icons.replay),
                          label: const Text('Пройти заново'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _leaveRoute,
                          icon: const Icon(Icons.close),
                          label: const Text('Закрыть'),
                        ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (route.completedCount > 0)
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _revertStep(context, route),
                            icon: const Icon(Icons.undo),
                            label: const Text('Шаг назад / перемерить'),
                          ),
                        if (route.completedCount > 0) const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _skipStep(context, route, step),
                          icon: const Icon(Icons.skip_next),
                          label: const Text('Пропустить шаг'),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _busy ? null : _leaveRoute,
                          icon: const Icon(Icons.close),
                          label: const Text('Отменить прохождение'),
                        ),
                      ],
                    ),
                ],
              ),
      ),
    ),
    );
  }

  Future<void> _restartRoute(BuildContext context, MeasurementRoute route) async {
    final appState = context.read<AppState>();
    final roomId = route.steps.isEmpty ? null : route.steps.first.roomId;
    if (route.isTemplate && roomId != null) {
      await appState.launchRouteInRoom(widget.projectId, route.id, roomId);
    } else {
      await appState.resetRouteProgress(widget.projectId, route.id);
    }
    if (mounted) {
      _armedStepId = null;
      _ensureAutoMode();
    }
  }

  Future<void> _revertStep(BuildContext context, MeasurementRoute route) async {
    final reverted = await context.read<AppState>().revertRouteStep(widget.projectId, route.id);
    if (!mounted) return;
    if (!reverted) {
      _showBriefSnack(context, 'Нечего откатывать');
      return;
    }
    _armedStepId = null;
    _lastAppliedValue = null;
    _ensureAutoMode();
  }

  Future<void> _skipStep(
    BuildContext context,
    MeasurementRoute route,
    RouteStepItem step,
  ) async {
    await context.read<AppState>().completeRouteStep(
          widget.projectId,
          route.id,
          step.id,
          skipped: true,
        );
    if (!mounted) return;
    _armedStepId = null;
    _ensureAutoMode();
  }

  String _routeStepCurrentValue(RouteStepItem step, RoomElement? element, Room? room) {
    if (step.target == RouteStepTarget.roomHeight) {
      return room?.defaultHeightMm == null ? 'не задано' : '${room!.defaultHeightMm} мм';
    }
    if (element == null) return '-';
    final value = switch (step.target) {
      RouteStepTarget.height => element.heightMm,
      RouteStepTarget.depth => element.depthMm,
      RouteStepTarget.windowsill => element.windowsillMm,
      RouteStepTarget.radiatorNiche => element.radiatorNicheMm,
      RouteStepTarget.width => element.primaryValueMm,
      RouteStepTarget.roomHeight => room?.defaultHeightMm,
    };
    return value == null ? 'не задано' : '$value мм';
  }
}

class _RoomGeometryCard extends StatelessWidget {
  const _RoomGeometryCard({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final geometry = room.geometry;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Расчёты помещения', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _MetricRow(
              label: 'Площадь пола',
              value: room.isPolygonal ? 'не рассчитана' : _formatArea(geometry.floorAreaM2),
            ),
            _MetricRow(label: 'Площадь стен', value: _formatArea(geometry.wallAreaM2)),
            _MetricRow(label: 'Периметр', value: _formatLength(geometry.perimeterMm)),
            _MetricRow(label: 'Площадь проёмов', value: _formatArea(geometry.openingAreaM2)),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

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

class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key, required this.projectId, required this.roomId});

  final String projectId;
  final String roomId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = _projectOrNull(state, projectId);
    final room = project == null ? null : _roomOrNull(project, roomId);
    if (project == null || room == null) {
      return const _MissingEntityScreen(message: 'Помещение больше недоступно');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(room.name),
        actions: [
          const _UndoButton(),
          IconButton(
            tooltip: 'Редактировать помещение',
            onPressed: () => _showRoomEditor(context, projectId, room),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Удалить помещение',
            onPressed: () => _confirmDeleteRoom(context, projectId, room, popAfterDelete: true),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Параметры', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Высота: ${room.defaultHeightMm == null ? 'не задана' : '${room.defaultHeightMm} мм'}'),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => _showHeightDialog(context, projectId, room),
                        icon: const Icon(Icons.edit),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Геометрия: ${room.isPolygonal ? 'многоугольник по сторонам' : 'обычная'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _RoomGeometryCard(room: room),
          if (project.routes.any((route) => route.isTemplate)) ...[
            const SizedBox(height: 20),
            Text('Маршруты', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Выберите шаблон — приложение проведёт по элементам и попросит только нужные размеры.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ...project.routes.where((route) => route.isTemplate).map(
                  (route) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.route_outlined),
                        title: Text(route.name),
                        subtitle: Text('${route.blueprint.length} элементов · ${route.blueprint.map((item) => item.name).join(', ')}'),
                        trailing: FilledButton(
                          onPressed: () async {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            await context.read<AppState>().launchRouteInRoom(projectId, route.id, room.id);
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => RouteRunScreen(projectId: projectId, routeId: route.id),
                              ),
                            );
                          },
                          child: const Text('Старт'),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 20),
          Text('Добавить элемент', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _roomAddElementTypes
                .map(
                  (type) => SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 50) / 2,
                    child: _ActionTile(
                      icon: _elementIcon(type),
                      label: '+ ${type.label}',
                      onTap: () => _showElementEditor(context, projectId, room, type: type),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
          Text('Серии замеров', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (room.elements.isEmpty)
            const _EmptyState(icon: Icons.straighten, text: 'Добавьте первый элемент')
          else
            ...room.elements.where((element) => element.type != RoomElementType.slope).map(
                  (element) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        leading: CircleAvatar(child: Icon(_elementIcon(element.type))),
                        title: Text(element.name),
                        subtitle: Text(
                          [
                            element.type.label,
                            if (_openingWallName(room, element) != null)
                              'стена ${_openingWallName(room, element)}',
                            if (element.heightMm != null) 'высота ${element.heightMm} мм',
                            if (element.depthMm != null) 'откос ${element.depthMm} мм',
                            if (element.windowsillMm != null) 'подоконник ${element.windowsillMm} мм',
                            if (element.radiatorNicheMm != null) 'ниша ${element.radiatorNicheMm} мм',
                            element.primaryMeasurement?.displayValue ?? 'нет замера',
                            if (element.note.isNotEmpty) element.note,
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              avatar: Icon(
                                element.isComplete ? Icons.check_circle : Icons.pending_outlined,
                                color: element.isComplete ? Colors.green : null,
                              ),
                              label: Text('${element.completedParameterCount} / ${element.requiredParameterCount}'),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (action) async {
                                if (action == 'edit') {
                                  await _showElementEditor(context, projectId, room, element: element);
                                } else if (action == 'delete') {
                                  await _confirmDeleteElement(
                                    context,
                                    projectId,
                                    room.id,
                                    element,
                                    popAfterDelete: false,
                                  );
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                                PopupMenuItem(value: 'delete', child: Text('Удалить')),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ElementScreen(
                              projectId: projectId,
                              roomId: room.id,
                              elementId: element.id,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _showHeightDialog(BuildContext context, String projectId, Room room) async {
    final controller = TextEditingController(text: room.defaultHeightMm?.toString() ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Высота помещения'),
        content: _MeasureTextField(
          controller: controller,
          labelText: 'Высота потолка, мм',
        ),
        actions: [
          TextButton(onPressed: () => _closeUnsavedForm(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              final value = int.tryParse(controller.text.trim());
              await context.read<AppState>().updateRoomHeight(projectId, room.id, value);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}

class ElementScreen extends StatelessWidget {
  const ElementScreen({
    super.key,
    required this.projectId,
    required this.roomId,
    required this.elementId,
  });

  final String projectId;
  final String roomId;
  final String elementId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = _projectOrNull(state, projectId);
    final room = project == null ? null : _roomOrNull(project, roomId);
    final element = room == null ? null : _elementOrNull(room, elementId);
    if (project == null || room == null || element == null) {
      return const _MissingEntityScreen(message: 'Элемент больше недоступен');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(element.name),
        actions: [
          const _UndoButton(),
          IconButton(
            tooltip: 'Редактировать элемент',
            onPressed: () => _showElementEditor(context, projectId, room, element: element),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Удалить элемент',
            onPressed: () => _confirmDeleteElement(
              context,
              projectId,
              room.id,
              element,
              popAfterDelete: true,
            ),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Параметры', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _MetricRow(label: 'Тип', value: element.type.label),
                  if (_openingWallName(room, element) != null)
                    _MetricRow(label: 'Стена', value: _openingWallName(room, element)!),
                  _MetricRow(label: _primaryDimensionLabel(element.type), value: element.primaryMeasurement?.displayValue ?? 'нет замера'),
                  if (element.type != RoomElementType.height)
                    _MetricRow(
                      label: element.type == RoomElementType.wall ? 'Высота' : 'Высота проёма',
                      value: element.heightMm == null ? 'не задана' : '${element.heightMm} мм',
                    ),
                  if (element.type == RoomElementType.door || element.type == RoomElementType.window)
                    _MetricRow(
                      label: 'Глубина откоса',
                      value: element.depthMm == null ? 'не задана' : '${element.depthMm} мм',
                    ),
                  if (element.type == RoomElementType.window) ...[
                    _MetricRow(
                      label: 'Подоконник',
                      value: element.windowsillMm == null ? 'не задан' : '${element.windowsillMm} мм',
                    ),
                    _MetricRow(
                      label: 'Ниша под радиатор',
                      value: element.radiatorNicheMm == null ? 'не задана' : '${element.radiatorNicheMm} мм',
                    ),
                  ],
                  if (element.note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Примечание', style: Theme.of(context).textTheme.labelLarge),
                    Text(element.note),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Серия замеров хранит несколько значений. Звёздочка выбирает основной замер — он идёт в расчёты и экспорт. Это не среднее значение.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Серия замеров', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (element.measurements.isEmpty)
            const _EmptyState(icon: Icons.straighten, text: 'Нет замеров')
          else
            ...element.measurements.map(
              (measurement) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    leading: IconButton(
                      tooltip: measurement.isPrimary
                          ? 'Основной замер'
                          : 'Сделать основным',
                      icon: Icon(measurement.isPrimary ? Icons.star : Icons.star_border),
                      onPressed: measurement.isPrimary
                          ? null
                          : () => context.read<AppState>().setPrimaryMeasurement(
                                projectId,
                                room.id,
                                element.id,
                                measurement.id,
                              ),
                    ),
                    title: Text(measurement.displayValue),
                    subtitle: Text(measurement.isPrimary ? 'Основной замер' : 'Дополнительный замер'),
                    trailing: IconButton(
                      tooltip: 'Удалить замер',
                      onPressed: () => context.read<AppState>().deleteMeasurement(projectId, room.id, element.id, measurement.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              ),
            ),
          if (element.type == RoomElementType.wall) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Слои отделки', style: Theme.of(context).textTheme.headlineSmall),
                ),
                IconButton.filledTonal(
                  tooltip: 'Добавить слой отделки',
                  onPressed: () => _showFinishLayerDialog(context, projectId, room.id, element.id),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (element.finishLayers.isEmpty)
              const _EmptyState(icon: Icons.layers_outlined, text: 'Слои отделки не заданы')
            else
              ...element.finishLayers.map(
                (layer) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      leading: const Icon(Icons.layers_outlined),
                      title: Text(layer.name),
                      subtitle: Text(
                        'Высота ${layer.heightMm} мм - площадь ${_formatArea(state.finishLayerAreaM2(room, element, layer))}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Удалить слой',
                        onPressed: () => context.read<AppState>().deleteFinishLayer(
                              projectId,
                              room.id,
                              element.id,
                              layer.id,
                            ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showMeasurementDialog(context, projectId, room.id, element.id),
        icon: const Icon(Icons.add),
        label: const Text('Замер'),
      ),
    );
  }
}

class PhotosScreen extends StatelessWidget {
  const PhotosScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final project = context.watch<AppState>().projectById(projectId);
    return Scaffold(
      appBar: AppBar(title: const Text('Фотографии')),
      body: project.photos.isEmpty
          ? const _EmptyState(icon: Icons.photo_outlined, text: 'Нет фотографий')
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: project.photos.length,
              itemBuilder: (context, index) {
                final photo = project.photos[index];
                return InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PhotoViewerScreen(projectId: project.id, photoId: photo.id),
                    ),
                  ),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(photo.path), fit: BoxFit.cover),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Chip(label: Text('${photo.annotations.length} точ.')),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'gallery',
            onPressed: () => _pickPhoto(context, ImageSource.gallery),
            tooltip: 'Выбрать фото',
            child: const Icon(Icons.photo_library_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'camera',
            onPressed: () => _pickPhoto(context, ImageSource.camera),
            tooltip: 'Сделать фото',
            child: const Icon(Icons.add_a_photo_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto(BuildContext context, ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(source: source, imageQuality: 90);
      if (image == null || !context.mounted) return;
      await context.read<AppState>().importPhoto(projectId, image.path);
      if (context.mounted) _showSnack(context, 'Фото сохранено', showUndo: true);
    } catch (error) {
      if (context.mounted) _showSnack(context, 'Не удалось сохранить фото: $error');
    }
  }
}

class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.projectId, required this.photoId});

  final String projectId;
  final String photoId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = state.projectById(projectId);
    final photo = project.photos.firstWhere((item) => item.id == photoId);

    return Scaffold(
      appBar: AppBar(title: const Text('Фото-подложка')),
      body: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          onTapUp: (details) async {
            final x = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            final y = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
            await context.read<AppState>().addPhotoAnnotation(project.id, photo.id, x: x, y: y);
            if (context.mounted) {
              final updated = context.read<AppState>().projectById(project.id).photos.firstWhere((item) => item.id == photo.id);
              final annotation = context.read<AppState>().activePhotoAnnotation(updated);
              if (annotation != null) {
                await _showPhotoAnnotationSheet(context, project.id, photo.id, annotation);
              }
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(child: Image.file(File(photo.path), fit: BoxFit.contain)),
              ),
              ...photo.annotations.map(
                (annotation) => Positioned(
                  left: annotation.x * constraints.maxWidth - 14,
                  top: annotation.y * constraints.maxHeight - 14,
                  child: _AnnotationMarker(
                    linked: annotation.isLinked,
                    onTap: () => _showPhotoAnnotationSheet(context, project.id, photo.id, annotation),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PdfScreen extends StatelessWidget {
  const PdfScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final project = context.watch<AppState>().projectById(projectId);
    final pdf = project.pdfs.isEmpty ? null : project.pdfs.first;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF-подложка')),
      body: pdf == null
          ? const _EmptyState(icon: Icons.picture_as_pdf_outlined, text: 'PDF не загружен')
          : PdfViewer(projectId: project.id, pdfId: pdf.id),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickPdf(context),
        icon: const Icon(Icons.upload_file),
        label: Text(pdf == null ? 'PDF' : 'Заменить'),
      ),
    );
  }

  Future<void> _pickPdf(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      final file = result?.files.single;
      final path = file?.path;
      if (file == null || path == null || !context.mounted) return;
      await context.read<AppState>().importPdf(projectId, path, file.name);
      if (context.mounted) _showSnack(context, 'PDF загружен', showUndo: true);
    } catch (error) {
      if (context.mounted) _showSnack(context, 'Не удалось загрузить PDF: $error');
    }
  }
}

class PdfViewer extends StatefulWidget {
  const PdfViewer({super.key, required this.projectId, required this.pdfId});

  final String projectId;
  final String pdfId;

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  final PdfViewerController _controller = PdfViewerController();
  int _pageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = state.projectById(widget.projectId);
    final pdf = project.pdfs.firstWhere((item) => item.id == widget.pdfId);

    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          SfPdfViewer.file(
            File(pdf.path),
            controller: _controller,
            onPageChanged: (details) => setState(() => _pageIndex = details.newPageNumber - 1),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) async {
              final x = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
              final y = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
              await context.read<AppState>().addPdfAnnotation(
                    project.id,
                    pdf.id,
                    pageIndex: _pageIndex,
                    x: x,
                    y: y,
                  );
              if (context.mounted) {
                final updated = context.read<AppState>().projectById(project.id).pdfs.firstWhere((item) => item.id == pdf.id);
                final annotation = context.read<AppState>().activePdfAnnotation(updated);
                if (annotation != null) {
                  await _showPdfAnnotationSheet(context, project.id, pdf.id, annotation);
                }
              }
            },
          ),
          ...pdf.annotations.where((annotation) => annotation.pageIndex == _pageIndex).map(
                (annotation) => Positioned(
                  left: annotation.x * constraints.maxWidth - 14,
                  top: annotation.y * constraints.maxHeight - 14,
                  child: _AnnotationMarker(
                    linked: annotation.isLinked,
                    onTap: () => _showPdfAnnotationSheet(context, project.id, pdf.id, annotation),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

Future<void> _showPhotoAnnotationSheet(
  BuildContext context,
  String projectId,
  String photoId,
  PhotoAnnotation annotation,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AnnotationSheet(
      projectId: projectId,
      title: 'Привязать точку фото',
      initialRoomId: annotation.roomId,
      initialElementId: annotation.elementId,
      initialComment: annotation.comment,
      onSave: (roomId, elementId, comment, measurementMm) => context.read<AppState>().linkPhotoAnnotation(
        projectId,
        photoId,
        annotation.id,
        roomId: roomId,
        elementId: elementId,
        comment: comment,
        measurementMm: measurementMm,
      ),
    ),
  );
}

Future<void> _showPdfAnnotationSheet(
  BuildContext context,
  String projectId,
  String pdfId,
  PdfAnnotation annotation,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AnnotationSheet(
      projectId: projectId,
      title: 'Привязать точку PDF',
      initialRoomId: annotation.roomId,
      initialElementId: annotation.elementId,
      onSave: (roomId, elementId, _, measurementMm) => context.read<AppState>().linkPdfAnnotation(
        projectId,
        pdfId,
        annotation.id,
        roomId: roomId,
        elementId: elementId,
        measurementMm: measurementMm,
      ),
    ),
  );
}

class _AnnotationSheet extends StatefulWidget {
  const _AnnotationSheet({
    required this.projectId,
    required this.title,
    required this.onSave,
    this.initialRoomId,
    this.initialElementId,
    this.initialComment,
  });

  final String projectId;
  final String title;
  final String? initialRoomId;
  final String? initialElementId;
  final String? initialComment;
  final Future<void> Function(String? roomId, String? elementId, String? comment, int? measurementMm) onSave;

  @override
  State<_AnnotationSheet> createState() => _AnnotationSheetState();
}

class _AnnotationSheetState extends State<_AnnotationSheet> {
  late String? _roomId = widget.initialRoomId;
  late String? _elementId = widget.initialElementId;
  late final TextEditingController _comment = TextEditingController(text: widget.initialComment ?? '');
  final TextEditingController _measurement = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    _measurement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = context.watch<AppState>().projectById(widget.projectId);
    final selectedRoom = _roomId == null ? null : _firstRoomById(project, _roomId!);
    final elements = selectedRoom?.elements ?? const <RoomElement>[];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _roomId,
              decoration: const InputDecoration(labelText: 'Помещение'),
              items: project.rooms.map((room) => DropdownMenuItem(value: room.id, child: Text(room.name))).toList(),
              onChanged: (value) => setState(() {
                _roomId = value;
                _elementId = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: elements.any((element) => element.id == _elementId) ? _elementId : null,
              decoration: const InputDecoration(labelText: 'Элемент'),
              items: elements.map((element) => DropdownMenuItem(value: element.id, child: Text(element.name))).toList(),
              onChanged: (value) => setState(() => _elementId = value),
            ),
            const SizedBox(height: 12),
            _MeasureTextField(
              controller: _measurement,
              labelText: 'Следующий замер дальномера, мм',
              hintText: 'Например 2450',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _comment,
              decoration: const InputDecoration(labelText: 'Комментарий'),
              minLines: 2,
              maxLines: 3,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await widget.onSave(
                    _roomId,
                    _elementId,
                    _comment.text.trim().isEmpty ? null : _comment.text.trim(),
                    int.tryParse(_measurement.text.trim()),
                  );
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Сохранить привязку'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnotationMarker extends StatelessWidget {
  const _AnnotationMarker({required this.linked, required this.onTap});

  final bool linked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: linked ? colorScheme.primary : colorScheme.tertiary,
          border: Border.all(color: colorScheme.onPrimary, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38)],
        ),
        child: Icon(linked ? Icons.check : Icons.add, size: 16, color: colorScheme.onPrimary),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

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
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Future<void> _showProjectEditor(BuildContext context, {required Project project}) async {
  final name = TextEditingController(text: project.name);
  final description = TextEditingController(text: project.description);
  var unit = project.unit;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Редактировать проект'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Описание'),
              minLines: 2,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MeasurementUnit>(
              value: unit,
              decoration: const InputDecoration(labelText: 'Единицы измерения'),
              items: MeasurementUnit.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
              onChanged: (value) {
                if (value != null) setState(() => unit = value);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => _closeUnsavedForm(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await context.read<AppState>().updateProject(
                    project.id,
                    name: name.text.trim(),
                    description: description.text.trim(),
                    unit: unit,
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmDeleteProject(
  BuildContext context,
  Project project, {
  bool popAfterDelete = false,
}) async {
  final confirmed = await _confirm(context, 'Удалить проект "${project.name}"?');
  if (!confirmed || !context.mounted) return;
  await context.read<AppState>().deleteProject(project.id);
  if (!context.mounted) return;
  if (popAfterDelete) Navigator.pop(context);
  _showSnack(context, 'Проект удалён', showUndo: true);
}

Future<void> _showRoomEditor(BuildContext context, String projectId, Room room) async {
  final name = TextEditingController(text: room.name);
  final height = TextEditingController(text: room.defaultHeightMm?.toString() ?? '');
  var polygonal = room.isPolygonal;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Редактировать помещение'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 12),
            _MeasureTextField(
              controller: height,
              labelText: 'Высота потолка, мм',
              helperText: 'Применяется ко всем стенам помещения по умолчанию',
            ),
            CheckboxListTile(
              value: polygonal,
              onChanged: (value) => setState(() => polygonal = value ?? false),
              contentPadding: EdgeInsets.zero,
              title: const Text('Многоугольное помещение'),
              subtitle: const Text('Площадь без координат не рассчитывается'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => _closeUnsavedForm(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              await context.read<AppState>().updateRoom(
                    projectId,
                    room.id,
                    name: name.text.trim().isEmpty ? room.name : name.text.trim(),
                    defaultHeightMm: int.tryParse(height.text.trim()),
                    isPolygonal: polygonal,
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmDeleteRoom(
  BuildContext context,
  String projectId,
  Room room, {
  bool popAfterDelete = false,
}) async {
  final confirmed = await _confirm(context, 'Удалить помещение "${room.name}" и все его элементы?');
  if (!confirmed || !context.mounted) return;
  _dismissAllSnacks(context);
  await context.read<AppState>().deleteRoom(projectId, room.id);
  if (!context.mounted) return;
  if (popAfterDelete) Navigator.pop(context);
  if (context.mounted) _showBriefSnack(context, 'Помещение удалено');
}

Future<void> _showElementEditor(
  BuildContext context,
  String projectId,
  Room room, {
  RoomElementType? type,
  RoomElement? element,
}) async {
  var selectedType = element?.type ?? type ?? RoomElementType.wall;
  final name = TextEditingController(
      text: element?.name ?? '${selectedType.label} ${room.elements.where((item) => item.type == selectedType).length + 1}');
  final primary = TextEditingController(text: element?.primaryValueMm?.toString() ?? '');
  final secondary = TextEditingController();
  final height = TextEditingController(text: element?.heightMm?.toString() ?? '');
  final depth = TextEditingController(text: element?.depthMm?.toString() ?? '');
  final windowsill = TextEditingController(text: element?.windowsillMm?.toString() ?? '');
  final radiatorNiche = TextEditingController(text: element?.radiatorNicheMm?.toString() ?? '');
  final note = TextEditingController(text: element?.note ?? '');
  final secondaryHeight = TextEditingController();
  final wallOptions = room.elements
      .where((item) => item.type == RoomElementType.wall && item.id != element?.id)
      .toList();
  String? selectedWallId = wallOptions.any((wall) => wall.id == element?.wallElementId)
      ? element?.wallElementId
      : null;
  var rectangular = false;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(element == null ? 'Новый элемент' : 'Редактировать элемент'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<RoomElementType>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'Тип элемента'),
                items: RoomElementType.values
                    .where((item) => item != RoomElementType.slope && item != RoomElementType.height)
                    .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    selectedType = value;
                    if (value != RoomElementType.wall) rectangular = false;
                    if (!_isOpeningType(value)) selectedWallId = null;
                    if (element == null) {
                      name.text = '${value.label} ${room.elements.where((item) => item.type == value).length + 1}';
                    }
                  });
                },
              ),
              if (selectedType == RoomElementType.wall && element == null) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: rectangular,
                  onChanged: (value) => setState(() => rectangular = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Помещение прямоугольное'),
                  subtitle: Text(
                    room.defaultHeightMm == null
                        ? 'Ввести ширину и высоту двух стен'
                        : 'Ввести ширину двух стен — высота возьмётся из помещения (${room.defaultHeightMm} мм)',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              const SizedBox(height: 12),
              if (rectangular) ...[
                _MeasureTextField(
                  controller: primary,
                  labelText: 'Ширина стены 1, мм',
                ),
                const SizedBox(height: 12),
                _MeasureTextField(
                  controller: secondary,
                  labelText: 'Ширина стены 2, мм',
                ),
                if (room.defaultHeightMm == null) ...[
                  const SizedBox(height: 12),
                  _MeasureTextField(
                    controller: height,
                    labelText: 'Высота стены 1, мм',
                  ),
                  const SizedBox(height: 12),
                  _MeasureTextField(
                    controller: secondaryHeight,
                    labelText: 'Высота стены 2, мм',
                  ),
                ],
              ] else ...[
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                const SizedBox(height: 12),
                _MeasureTextField(
                  controller: primary,
                  labelText: '${_primaryDimensionLabel(selectedType)}, мм',
                ),
                const SizedBox(height: 12),
                _MeasureTextField(
                  controller: height,
                  labelText: selectedType == RoomElementType.wall
                      ? 'Высота элемента, мм'
                      : 'Высота проёма, мм',
                  helperText: selectedType == RoomElementType.wall
                      ? 'Можно оставить пустым — возьмётся высота помещения'
                      : null,
                ),
                if (selectedType == RoomElementType.door || selectedType == RoomElementType.window) ...[
                  const SizedBox(height: 12),
                  _MeasureTextField(
                    controller: depth,
                    labelText: 'Глубина откоса, мм',
                    helperText: 'Ширина и высота откоса берутся из размеров проёма',
                  ),
                ],
                if (selectedType == RoomElementType.window) ...[
                  const SizedBox(height: 12),
                  _MeasureTextField(
                    controller: windowsill,
                    labelText: 'Подоконник, мм',
                  ),
                  const SizedBox(height: 12),
                  _MeasureTextField(
                    controller: radiatorNiche,
                    labelText: 'Ниша под радиатор, мм',
                  ),
                ],
                if (_isOpeningType(selectedType) && wallOptions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedWallId,
                    decoration: const InputDecoration(labelText: 'К какой стене относится'),
                    items: wallOptions
                        .map((wall) => DropdownMenuItem(value: wall.id, child: Text(wall.name)))
                        .toList(),
                    onChanged: (value) => setState(() => selectedWallId = value),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Примечание'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => _closeUnsavedForm(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              if (rectangular && element == null) {
                final wall1Width = int.tryParse(primary.text.trim());
                final wall1Height = int.tryParse(height.text.trim()) ?? room.defaultHeightMm;
                final wall2Width = int.tryParse(secondary.text.trim());
                final wall2Height = int.tryParse(secondaryHeight.text.trim()) ?? room.defaultHeightMm;
                if (wall1Width == null || wall2Width == null) {
                  _showSnack(context, 'Введите ширину двух стен');
                  return;
                }
                if (wall1Height == null || wall2Height == null) {
                  _showSnack(context, 'Укажите высоту помещения или высоту каждой стены');
                  return;
                }
                await context.read<AppState>().addRectangularRoomWalls(
                      projectId,
                      room.id,
                      wall1WidthMm: wall1Width,
                      wall1HeightMm: wall1Height,
                      wall2WidthMm: wall2Width,
                      wall2HeightMm: wall2Height,
                    );
                if (context.mounted) Navigator.pop(context);
                return;
              }

              final value = int.tryParse(primary.text.trim());
              if (value == null) {
                _showSnack(context, 'Введите основной размер элемента');
                return;
              }
              final heightMm = int.tryParse(height.text.trim());
              final depthMm = int.tryParse(depth.text.trim());
              final windowsillMm = int.tryParse(windowsill.text.trim());
              final radiatorNicheMm = int.tryParse(radiatorNiche.text.trim());
              if (element == null) {
                await context.read<AppState>().addElement(
                      projectId,
                      room.id,
                      selectedType,
                      name: name.text,
                      valueMm: value,
                      heightMm: heightMm,
                      depthMm: depthMm,
                      windowsillMm: windowsillMm,
                      radiatorNicheMm: radiatorNicheMm,
                      wallElementId: selectedWallId,
                      note: note.text.trim(),
                    );
              } else {
                await context.read<AppState>().updateElement(
                      projectId,
                      room.id,
                      element.id,
                      name: name.text,
                      type: selectedType,
                      heightMm: heightMm,
                      primaryValueMm: value,
                      depthMm: depthMm,
                      windowsillMm: windowsillMm,
                      radiatorNicheMm: radiatorNicheMm,
                      wallElementId: selectedWallId,
                      note: note.text.trim(),
                    );
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmDeleteElement(
  BuildContext context,
  String projectId,
  String roomId,
  RoomElement element, {
  bool popAfterDelete = false,
}) async {
  final confirmed = await _confirm(context, 'Удалить элемент "${element.name}"?');
  if (!confirmed || !context.mounted) return;
  await context.read<AppState>().deleteElement(projectId, roomId, element.id);
  if (!context.mounted) return;
  if (popAfterDelete) Navigator.pop(context);
  _showBriefSnack(context, 'Элемент удалён');
}

Future<void> _showFinishLayerDialog(
  BuildContext context,
  String projectId,
  String roomId,
  String elementId,
) async {
  final name = TextEditingController();
  final height = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Слой отделки'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          const SizedBox(height: 12),
          _MeasureTextField(
            controller: height,
            labelText: 'Высота отделки, мм',
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => _closeUnsavedForm(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () async {
            final heightMm = int.tryParse(height.text.trim());
            if (heightMm == null) {
              _showSnack(context, 'Введите высоту слоя отделки');
              return;
            }
            await context.read<AppState>().addFinishLayer(
                  projectId,
                  roomId,
                  elementId,
                  name: name.text,
                  heightMm: heightMm,
                );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Добавить'),
        ),
      ],
    ),
  );
}

Future<void> _showMeasurementDialog(
  BuildContext context,
  String projectId,
  String roomId,
  String elementId,
) async {
  final value = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Новый замер'),
      content: _MeasureTextField(
        controller: value,
        labelText: 'Значение, мм',
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => _closeUnsavedForm(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () async {
            final parsed = int.tryParse(value.text.trim());
            if (parsed == null) {
              _showSnack(context, 'Введите значение замера');
              return;
            }
            await context.read<AppState>().addMeasurement(projectId, roomId, elementId, parsed);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Добавить'),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(BuildContext context, String message) async {
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

Project? _projectOrNull(AppState state, String id) {
  for (final project in state.projects) {
    if (project.id == id) return project;
  }
  return null;
}

Room? _roomOrNull(Project project, String id) {
  for (final room in project.rooms) {
    if (room.id == id) return room;
  }
  return null;
}

RoomElement? _elementOrNull(Room? room, String id) {
  if (room == null) return null;
  for (final element in room.elements) {
    if (element.id == id) return element;
  }
  return null;
}

MeasurementRoute? _routeOrNull(Project project, String id) {
  for (final route in project.routes) {
    if (route.id == id) return route;
  }
  return null;
}

Future<void> _startTemplateRoute(
  BuildContext context,
  String projectId,
  MeasurementRoute route,
) async {
  final appState = context.read<AppState>();
  final project = appState.projectById(projectId);
  _dismissAllSnacks(context);

  if (route.steps.isNotEmpty) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RouteRunScreen(projectId: projectId, routeId: route.id),
      ),
    );
    return;
  }

  if (project.rooms.isEmpty) {
    _showSnack(context, 'Сначала добавьте помещение в проект');
    return;
  }

  String? roomId;
  if (project.rooms.length == 1) {
    roomId = project.rooms.first.id;
  } else {
    roomId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            Text('Выберите помещение', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...project.rooms.map(
              (room) => ListTile(
                leading: const Icon(Icons.meeting_room_outlined),
                title: Text(room.name),
                subtitle: room.defaultHeightMm == null
                    ? null
                    : Text('Высота: ${room.defaultHeightMm} мм'),
                onTap: () => Navigator.pop(context, room.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  if (roomId == null || !context.mounted) return;
  await appState.launchRouteInRoom(projectId, route.id, roomId);
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => RouteRunScreen(projectId: projectId, routeId: route.id),
    ),
  );
}

class _MissingEntityScreen extends StatelessWidget {
  const _MissingEntityScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Данные изменились')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.undo, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> _confirmDiscardUnsaved(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Сохранить изменения?'),
          content: const Text('Есть несохранённые изменения. Выйти без сохранения?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Выйти без сохранения')),
          ],
        ),
      ) ??
      false;
}

Future<void> _closeUnsavedForm(BuildContext context) async {
  final discard = await _confirmDiscardUnsaved(context);
  if (discard && context.mounted) Navigator.pop(context);
}

String _primaryDimensionLabel(RoomElementType type) {
  return switch (type) {
    RoomElementType.wall => 'Длина стены',
    RoomElementType.door => 'Ширина проёма',
    RoomElementType.window => 'Ширина окна',
    RoomElementType.opening => 'Ширина проёма',
    RoomElementType.slope => 'Ширина откоса',
    RoomElementType.height => 'Высота',
  };
}

IconData _elementIcon(RoomElementType type) {
  return switch (type) {
    RoomElementType.wall => Icons.window,
    RoomElementType.door => Icons.door_front_door,
    RoomElementType.window => Icons.window_outlined,
    RoomElementType.opening => Icons.open_in_full,
    RoomElementType.slope => Icons.vertical_align_center,
    RoomElementType.height => Icons.height,
  };
}

bool _isOpeningType(RoomElementType type) {
  return type == RoomElementType.door ||
      type == RoomElementType.window ||
      type == RoomElementType.opening;
}

String? _openingWallName(Room room, RoomElement element) {
  final wallId = element.wallElementId;
  if (wallId == null) return null;
  for (final wall in room.elements) {
    if (wall.id == wallId) return wall.name;
  }
  return null;
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

String _formatArea(double value) => '${value.toStringAsFixed(2)} м2';

String _formatLength(int valueMm) => '${(valueMm / 1000).toStringAsFixed(2)} м';

void _dismissAllSnacks(BuildContext context) {
  rootScaffoldMessengerKey.currentState?.clearSnackBars();
  ScaffoldMessenger.of(context).clearSnackBars();
}

void _showBriefSnack(BuildContext context, String message) {
  _dismissAllSnacks(context);
  final messenger = rootScaffoldMessengerKey.currentState ?? ScaffoldMessenger.of(context);
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(message, softWrap: true),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 2100), controller.close);
}

void _showSnack(BuildContext context, String message, {bool showUndo = false}) {
  if (!showUndo) {
    _showBriefSnack(context, message);
    return;
  }
  _dismissAllSnacks(context);
  final messenger = rootScaffoldMessengerKey.currentState ?? ScaffoldMessenger.of(context);
  final appState = context.read<AppState>();
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(message, softWrap: true),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      action: appState.canUndo
          ? SnackBarAction(
              label: 'Отменить',
              onPressed: () {
                messenger.hideCurrentSnackBar();
                appState.undoLast();
              },
            )
          : null,
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 3100), controller.close);
}

Room? _firstRoomById(Project project, String roomId) {
  for (final room in project.rooms) {
    if (room.id == roomId) return room;
  }
  return null;
}

RoomElement? _firstElementById(Room? room, String elementId) {
  if (room == null) return null;
  for (final element in room.elements) {
    if (element.id == elementId) return element;
  }
  return null;
}

class _MeasureTextField extends StatefulWidget {
  const _MeasureTextField({
    required this.controller,
    required this.labelText,
    this.helperText,
    this.hintText,
    this.autofocus = false,
    this.enableRangefinder = true,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final String? hintText;
  final bool autofocus;
  final bool enableRangefinder;

  @override
  State<_MeasureTextField> createState() => _MeasureTextFieldState();
}

class _MeasureTextFieldState extends State<_MeasureTextField> {
  late final FocusNode _focusNode = FocusNode();
  StreamSubscription<RangefinderReading>? _readingSub;
  DateTime _armedAt = DateTime.now();
  int? _lastAppliedValue;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.enableRangefinder) {
      _readingSub ??= context.read<RangefinderController>().readings.listen(_applyReadingIfActive);
    }
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (!widget.enableRangefinder) return;
    if (_focusNode.hasFocus) {
      _armedAt = DateTime.now();
    }
    if (mounted) setState(() {});
  }

  void _applyReadingIfActive(RangefinderReading reading) {
    if (!widget.enableRangefinder) return;
    if (!_focusNode.hasFocus) return;
    if (reading.timestamp.isBefore(_armedAt)) return;
    if (_lastAppliedValue == reading.valueMm) return;
    _lastAppliedValue = reading.valueMm;
    widget.controller.text = reading.valueMm.toString();
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enableRangefinder) {
      return TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          helperText: widget.helperText,
        ),
      );
    }

    final rangefinder = context.watch<RangefinderController>();
    final showHistory = _focusNode.hasFocus && rangefinder.history.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            helperText: widget.helperText ??
                (_focusNode.hasFocus && rangefinder.status == RangefinderStatus.connected
                    ? 'Поле активно: новый выстрел дальномера подставится автоматически'
                    : null),
            suffixIcon: IconButton(
              tooltip: rangefinder.status == RangefinderStatus.connected
                  ? 'Снять замер с дальномера'
                  : 'Подключите дальномер',
              icon: const Icon(Icons.straighten),
              onPressed: () => _capture(context),
            ),
          ),
        ),
        if (showHistory) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: rangefinder.history.take(5).map((reading) {
                return ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${reading.valueMm} мм'),
                  tooltip: 'Источник: ${reading.source}',
                  onPressed: () {
                    widget.controller.text = reading.valueMm.toString();
                    widget.controller.selection = TextSelection.collapsed(
                      offset: widget.controller.text.length,
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _capture(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final rangefinder = context.read<RangefinderController>();
    if (rangefinder.status != RangefinderStatus.connected) {
      messenger.clearSnackBars();
      if (!rangefinder.testMode) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(builder: (_) => const RangefinderScreen()),
        );
        if (!mounted) return;
        return;
      }
    }

    _focusNode.requestFocus();
    _armedAt = DateTime.now();
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          rangefinder.testMode
              ? 'Генерация тестового замера...'
              : 'Отправляю команду измерения дальномеру...',
          softWrap: true,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    final reading = await rangefinder.captureNext(
      timeout: rangefinder.testMode
          ? const Duration(seconds: 3)
          : const Duration(seconds: 30),
      onBluetoothOff: () => _promptEnableBluetooth(context),
    );
    if (reading == null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Замер не получен', softWrap: true),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    widget.controller.text = reading.valueMm.toString();
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Получено: ${reading.valueMm} мм', softWrap: true),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _RangefinderStatusIcon extends StatelessWidget {
  const _RangefinderStatusIcon();

  @override
  Widget build(BuildContext context) {
    final rangefinder = context.watch<RangefinderController>();
    final color = switch (rangefinder.status) {
      RangefinderStatus.connected => Colors.green,
      RangefinderStatus.connecting || RangefinderStatus.scanning => Colors.orange,
      RangefinderStatus.error => Colors.red,
      RangefinderStatus.disconnected => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return IconButton(
      tooltip: 'Дальномер: ${rangefinder.status.label}',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const RangefinderScreen()),
      ),
      icon: Icon(
        rangefinder.status == RangefinderStatus.connected
            ? Icons.bluetooth_connected
            : rangefinder.status == RangefinderStatus.error
                ? Icons.bluetooth_disabled
                : Icons.bluetooth,
        color: color,
      ),
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton();

  @override
  Widget build(BuildContext context) {
    final canUndo = context.select<AppState, bool>((state) => state.canUndo);
    return IconButton(
      tooltip: 'Отменить последнее действие',
      onPressed: canUndo
          ? () async {
              await context.read<AppState>().undoLast();
              if (context.mounted) _showSnack(context, 'Последнее действие отменено');
            }
          : null,
      icon: const Icon(Icons.undo),
    );
  }
}

class RangefinderScreen extends StatelessWidget {
  const RangefinderScreen({super.key});

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
                            Text(rangefinder.status.label,
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Тестовый режим'),
                    subtitle: const Text(
                        'Только для проверки UI. В этом режиме значения случайные и не идут с дальномера.'),
                    value: rangefinder.testMode,
                    onChanged: (value) async {
                      await rangefinder.setTestMode(value);
                    },
                  ),
                  const SizedBox(height: 8),
                  if (rangefinder.testMode) ...[
                    Card(
                      color: colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Внимание: включён тестовый режим. Эти замеры случайные.',
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
                        label: Text(rangefinder.testMode
                            ? 'Запустить тестовый режим'
                            : 'Подключиться к Bosch GLM'),
                      ),
                      OutlinedButton.icon(
                        onPressed: rangefinder.status == RangefinderStatus.disconnected
                            ? null
                            : () => rangefinder.disconnect(),
                        icon: const Icon(Icons.stop),
                        label: const Text('Отключить'),
                      ),
                      OutlinedButton.icon(
                        onPressed: rangefinder.status == RangefinderStatus.connected
                            ? () async {
                                final reading = await rangefinder.captureNext(
                                  timeout: rangefinder.testMode
                                      ? const Duration(seconds: 3)
                                      : const Duration(seconds: 30),
                                  onBluetoothOff: () => _promptEnableBluetooth(context),
                                );
                                if (!context.mounted) return;
                                _showSnack(
                                  context,
                                  reading == null
                                      ? 'Замер не получен'
                                      : 'Замер: ${reading.valueMm} мм',
                                );
                              }
                            : null,
                        icon: const Icon(Icons.straighten),
                        label: Text(rangefinder.testMode ? 'Тестовый замер' : 'Снять замер'),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text('Найденные BLE-устройства',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      Text('${rangefinder.devices.length}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Если дальномер виден в списке, нажмите на него. Обычно Bosch отображается как GLM или Bosch, но иногда может быть "Без имени".',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (rangefinder.devices.isEmpty)
                    const Text('Пока устройств нет. Нажмите "Подключиться к Bosch GLM" и подождите 15 секунд.')
                  else
                    ...rangefinder.devices.take(12).map(
                          (device) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                device.hasKnownService
                                    ? Icons.bluetooth_connected
                                    : Icons.bluetooth,
                              ),
                              title: Text(device.label),
                              subtitle: Text(
                                '${device.id} - RSSI ${device.rssi}'
                                '${device.hasKnownService ? ' - Bosch-сервис найден' : ''}',
                              ),
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
                  Text('Последний замер',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    rangefinder.lastReading == null
                        ? '—'
                        : '${rangefinder.lastReading!.valueMm} мм',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (rangefinder.lastReading != null)
                    Text('источник: ${rangefinder.lastReading!.source}',
                        style: Theme.of(context).textTheme.bodySmall),
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
                  Text('Лог', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (rangefinder.log.isEmpty)
                    const Text('Лог пуст')
                  else
                    ...rangefinder.log.take(30).map(
                          (line) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              line,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Bosch GLM 50‑27 CG: включите устройство, выберите режим Bluetooth (значок ❄). '
            'Сервис BLE: 02a6c0d0…1989. После подключения значения выстрелов '
            'автоматически попадают в активное поле.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
