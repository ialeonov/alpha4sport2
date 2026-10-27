import 'package:alpha4sport_app/core/theme/app_theme.dart';
import 'package:alpha4sport_app/features/workouts/presentation/rest_timer_button.dart';
import 'package:alpha4sport_app/features/workouts/presentation/set_quick_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.theme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('quick entry submits adjusted weight, reps and RPE',
      (tester) async {
    double? weight;
    int? reps;
    double? rpe;
    await tester.pumpWidget(_wrap(SetQuickEntry(
      setNumber: 3,
      initialWeight: 100,
      initialReps: 7,
      restSeconds: 90,
      onSubmit: (w, r, e) {
        weight = w;
        reps = r;
        rpe = e;
      },
    )));

    expect(find.text('Подход 3'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);

    await tester.tap(find.byTooltip('Плюс 2,5 кг'));
    await tester.tap(find.byTooltip('Плюс 2,5 кг'));
    await tester.tap(find.byTooltip('Минус повтор'));
    await tester.pump();
    await tester.tap(find.text('9'));
    await tester.pump();

    expect(find.text('105'), findsOneWidget);
    expect(find.text('6'), findsWidgets);

    await tester.tap(find.text('Записать · отдых 1:30'));
    expect(weight, 105);
    expect(reps, 6);
    expect(rpe, 9);
  });

  testWidgets('weight and reps can be typed from the keyboard',
      (tester) async {
    double? weight;
    int? reps;
    await tester.pumpWidget(_wrap(SetQuickEntry(
      setNumber: 1,
      initialWeight: 55,
      initialReps: 10,
      onSubmit: (w, r, _) {
        weight = w;
        reps = r;
      },
    )));

    await tester.enterText(find.byType(TextField).at(0), '67,5');
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.tap(find.text('Записать подход'));
    expect(weight, 67.5);
    expect(reps, 12);
  });

  testWidgets('quick entry resets to new seed for the next set',
      (tester) async {
    Widget build(int setNumber, double weight) => _wrap(SetQuickEntry(
          setNumber: setNumber,
          initialWeight: weight,
          initialReps: 8,
          onSubmit: (_, __, ___) {},
        ));

    await tester.pumpWidget(build(1, 80));
    await tester.tap(find.byTooltip('Плюс 2,5 кг'));
    await tester.pump();
    expect(find.text('82,5'), findsOneWidget);

    await tester.pumpWidget(build(2, 82.5));
    expect(find.text('Подход 2'), findsOneWidget);
    expect(find.text('82,5'), findsOneWidget);
  });

  testWidgets('rest bar appears while the timer runs', (tester) async {
    final controller = RestTimerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(RestTimerBar(controller: controller)));

    expect(find.text('ОТДЫХ'), findsNothing);

    controller.start(90);
    // Даём полосе раскрыться (AnimatedSize), иначе тап уйдёт мимо.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ОТДЫХ'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    expect(RestTimerController.lastSeconds, 90);

    await tester.tap(find.text('Дальше'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.running, isFalse);
    expect(find.text('ОТДЫХ'), findsNothing);
  });
}
