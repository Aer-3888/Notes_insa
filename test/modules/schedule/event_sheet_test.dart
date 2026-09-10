import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/campus_map/campus_geo.dart';
import 'package:notes_insa/modules/campus_map/campus_places.dart';
import 'package:notes_insa/modules/campus_map/map_painter.dart';
import 'package:notes_insa/modules/campus_map/map_preview.dart';
import 'package:notes_insa/modules/schedule/event_sheet.dart';
import 'package:notes_insa/modules/schedule/schedule_event.dart';
import 'package:notes_insa/theme/campus_theme.dart';
import 'package:notes_insa/theme/tokens.dart';

ScheduleEvent _event({String? room}) => ScheduleEvent(
  title: 'Algèbre 3 - GHIJKL',
  start: DateTime(2026, 9, 7, 8, 15),
  end: DateTime(2026, 9, 7, 10, 15),
  groups: const <String>['S3-STPI-G', 'S3-STPI-H'],
  teachers: const <String>['CAMAR-EDDINE MOHAMED', 'LEY OLIVIER'],
  module: 'Algebre 3',
  room: room,
);

const _places = <CampusPlace>[
  CampusPlace(code: '3', name: 'Amphi C', kind: PlaceKind.amphi),
];

final _geo = CampusGeo(
  originLat: 48.122,
  originLon: -1.635,
  mPerDegLat: 111320,
  mPerDegLon: 74000,
  buildings: <CampusBuilding>[
    CampusBuilding(
      code: '3',
      name: 'Bâtiment 3',
      levels: 2,
      ring: const <Offset>[
        Offset(0, 0),
        Offset(20, 0),
        Offset(20, 20),
        Offset(0, 20),
        Offset(0, 0),
      ],
    ),
  ],
  entrances: const <CampusEntrance>[
    CampusEntrance(code: '3', kind: 'main', node: 0, p: Offset(10, 0)),
  ],
  graph: const CampusGraph(nodes: <Offset>[Offset(10, 0)], edges: []),
  unmapped: const <String, String>{},
  attribution: '© OpenStreetMap contributors, ODbL',
);

Future<void> _open(
  WidgetTester tester,
  ScheduleEvent event, {
  Size size = const Size(384, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        campusPlacesProvider.overrideWith((ref) async => _places),
        campusGeoProvider.overrideWith((ref) async => _geo),
      ],
      child: MaterialApp(
        theme: campusTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEventSheet(context, event),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Clipboard.setData goes through a platform channel that does not exist in
  // a widget test, and the sheet only reports success after it resolves.
  final clipboard = <MethodCall>[];
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
  });
  tearDown(() {
    clipboard.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('the sheet shows the detail the row cannot', (tester) async {
    await _open(tester, _event(room: 'Amphi C (V)'));
    expect(find.text('Algebre 3'), findsOneWidget);
    expect(find.textContaining('08:15'), findsWidgets);
    expect(find.textContaining('10:15'), findsWidgets);
    expect(find.textContaining('2 h'), findsWidgets);
    // Every teacher, not the joined single line the grid row shows.
    expect(find.text('CAMAR-EDDINE MOHAMED'), findsOneWidget);
    expect(find.text('LEY OLIVIER'), findsOneWidget);
    expect(find.textContaining('S3-STPI-G'), findsWidgets);
  });

  testWidgets('the sheet uses the full available width', (tester) async {
    await _open(
      tester,
      _event(room: 'Amphi C (V)'),
      size: const Size(900, 800),
    );
    expect(tester.getSize(find.byType(BottomSheet)).width, 900);
    expect(tester.getTopLeft(find.text('Algebre 3')).dx, CampusSpacing.gutter);
  });

  testWidgets('a resolved room offers the map action', (tester) async {
    await _open(tester, _event(room: 'Amphi C (V)'));
    expect(find.text('Voir sur la carte'), findsOneWidget);
    expect(find.text('Me guider'), findsOneWidget);
    expect(find.textContaining('bâtiment 3'), findsOneWidget);
    expect(find.byType(CampusMapPreview), findsOneWidget);
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<CampusMapPainter>()
        .single;
    expect(painter.selected, '3');
  });

  testWidgets('an unresolved room shows the text and no map action', (
    tester,
  ) async {
    await _open(tester, _event(room: '*216* (V)'));
    expect(find.text('*216* (V)'), findsOneWidget);
    expect(find.text('Voir sur la carte'), findsNothing);
    expect(find.text('Me guider'), findsNothing);
    expect(find.byType(CampusMapPreview), findsNothing);
  });

  testWidgets('an event with no room shows neither', (tester) async {
    await _open(tester, _event());
    expect(find.text('Voir sur la carte'), findsNothing);
    expect(find.text('Copier la salle'), findsNothing);
  });

  testWidgets('copying the room reports it', (tester) async {
    await _open(tester, _event(room: 'Amphi C (V)'));
    await tester.tap(find.text('Copier la salle'));
    await tester.pumpAndSettle();
    expect(find.text('Salle copiée'), findsOneWidget);
    expect(
      clipboard.single.arguments['text'],
      'Amphi C (V)',
      reason: 'the raw room is what people paste into a message',
    );
  });
}
