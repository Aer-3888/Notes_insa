import 'package:flutter_test/flutter_test.dart';
import 'package:notes_insa/modules/campus_map/campus_geo.dart';
import 'package:notes_insa/modules/campus_map/campus_route.dart';

CampusBuilding _building(String code, double x) => CampusBuilding(
  code: code,
  name: 'Bâtiment $code',
  levels: null,
  ring: <Offset>[
    Offset(x, 0),
    Offset(x + 10, 0),
    Offset(x + 10, 10),
    Offset(x, 10),
    Offset(x, 0),
  ],
);

final _geo = CampusGeo(
  originLat: 48.122,
  originLon: -1.635,
  mPerDegLat: 111320,
  mPerDegLon: 74000,
  buildings: <CampusBuilding>[_building('3', 30)],
  entrances: const <CampusEntrance>[
    CampusEntrance(code: '3', kind: 'yes', node: 2, p: Offset(30, 0)),
    CampusEntrance(code: '3', kind: 'main', node: 3, p: Offset(40, 0)),
  ],
  graph: const CampusGraph(
    nodes: <Offset>[Offset(0, 0), Offset(10, 0), Offset(30, 0), Offset(40, 0)],
    edges: <List<double>>[
      <double>[0, 1, 10],
      <double>[1, 2, 20],
      <double>[1, 3, 31],
    ],
  ),
  unmapped: const <String, String>{},
  attribution: '',
);

void main() {
  test('estimates and labels campus walking time', () {
    expect(estimatedWalkingMinutes(0), 0);
    expect(estimatedWalkingMinutes(78), 1);
    expect(estimatedWalkingMinutes(100), 2);
    expect(approximateWalkingTimeLabel(78), '≈ 1 min');
  });

  test('routes from the nearest graph node to the closest entrance', () {
    final route = routeToBuilding(_geo, const Offset(1, 1), '3');
    expect(route, isNotNull);
    expect(route!.entrance.node, 2);
    expect(route.points, <Offset>[
      const Offset(1, 1),
      const Offset(0, 0),
      const Offset(10, 0),
      const Offset(30, 0),
    ]);
    expect(route.distanceMeters, closeTo(31.41, 0.01));
  });

  test('returns null when a building has no reachable entrance', () {
    expect(routeToBuilding(_geo, Offset.zero, '8'), isNull);
  });

  test('does not invent a straight route from outside the campus graph', () {
    expect(routeToBuilding(_geo, const Offset(-200, 0), '3'), isNull);
  });
}
