import 'package:flutter_test/flutter_test.dart';
import 'package:k/features/measurements/app_state.dart';
import 'package:k/main.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Projects screen renders app shell', (WidgetTester tester) async {
    final state = AppState();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const ZameriApp(),
      ),
    );

    expect(find.text('Проекты'), findsOneWidget);
    expect(find.text('Нет проектов'), findsOneWidget);
  });
}
