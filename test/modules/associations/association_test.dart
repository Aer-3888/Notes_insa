import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes_insa/core/search_text.dart';
import 'package:notes_insa/core/time.dart';
import 'package:notes_insa/modules/associations/association.dart';
import 'package:notes_insa/modules/associations/association_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _row({
  Object? id = 'ktulu',
  Object? name = 'Association Ktulu',
  Object? category = 'culture',
  Object? events,
  Object? links,
  Object? logoAsset,
}) => <String, Object?>{
  'id': id,
  'name': name,
  'category': category,
  'events': ?events,
  'links': ?links,
  'logoAsset': ?logoAsset,
};

Map<String, Object?> _event({
  Object? id = 'e1',
  Object? title = 'Gala',
  Object? startsAt = '2026-03-14T20:00:00',
  Object? endsAt,
}) => <String, Object?>{
  'id': id,
  'title': title,
  'startsAt': startsAt,
  'endsAt': ?endsAt,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initCampusTime);
  group('a row the seed gets wrong is dropped, not crashed on', () {
    test('an entry with no id or no name is not an association', () {
      expect(Association.fromJson(_row(id: null)), isNull);
      expect(Association.fromJson(_row(id: '')), isNull);
      expect(Association.fromJson(_row(name: null)), isNull);
      expect(Association.fromJson(_row(name: 42)), isNull);
      expect(Association.fromJson(null), isNull);
      expect(Association.fromJson('ktulu'), isNull);
    });

    test('an event with no parseable date is dropped, the asso survives', () {
      final association = Association.fromJson(
        _row(
          events: <Object?>[
            _event(id: 'ok'),
            _event(id: 'bad', startsAt: 'le 14 mars'),
            _event(id: null),
            'not an event',
          ],
        ),
      );
      expect(association, isNotNull);
      expect(association!.events.map((e) => e.id), <String>['ok']);
    });

    test('an unknown category falls back rather than dropping the row', () {
      expect(
        Association.fromJson(_row(category: 'sportif'))?.category,
        AssociationCategory.autre,
      );
      expect(
        Association.fromJson(_row(category: null))?.category,
        AssociationCategory.autre,
      );
    });
  });

  test('an event carries the id of the association it came from', () {
    final association = Association.fromJson(
      _row(id: 'bds', events: <Object?>[_event()]),
    );
    expect(association!.events.single.associationId, 'bds');
  });

  test('an end before the start is discarded', () {
    final good = Association.fromJson(
      _row(events: <Object?>[_event(endsAt: '2026-03-15T02:00:00')]),
    );
    expect(good!.events.single.endsAt, isNotNull);

    final backwards = Association.fromJson(
      _row(events: <Object?>[_event(endsAt: '2026-03-13T02:00:00')]),
    );
    expect(backwards!.events.single.endsAt, isNull);
  });

  test('an Instagram handle loses its arobase', () {
    final links = AssociationLinks.fromJson(<String, Object?>{
      'instagram': '@ktulu',
    });
    expect(links.instagram, 'ktulu');
    expect(links.instagramUri.toString(), 'https://www.instagram.com/ktulu/');
  });

  test('an organigram keeps its public roles grouped by mandate', () {
    final association = Association.fromJson(<String, Object?>{
      ..._row(),
      'organigram': <String, Object?>{
        'title': 'Mandat 2026',
        'sections': <Object?>[
          <String, Object?>{
            'title': 'Bureau',
            'members': <Object?>[
              <String, Object?>{'role': 'Président·e', 'name': 'Maxime'},
            ],
          },
        ],
      },
    });

    expect(association!.organigram?.title, 'Mandat 2026');
    expect(association.organigram?.memberCount, 1);
    expect(
      association.organigram?.sections.single.members.single.role,
      'Président·e',
    );
  });

  test('recruitment is shown only when the feed explicitly opens it', () {
    final association = Association.fromJson(<String, Object?>{
      ..._row(),
      'recruitment': <String, Object?>{
        'isOpen': true,
        'title': 'Candidate maintenant',
        'url': 'https://example.test/apply',
      },
    });
    final closed = AssociationRecruitment.fromJson(<String, Object?>{
      'isOpen': false,
    });

    expect(association!.recruitment?.isVisible, isTrue);
    expect(association.recruitment?.title, 'Candidate maintenant');
    expect(closed?.isVisible, isFalse);
  });

  test('remote public media is accepted only over HTTPS', () {
    final association = Association.fromJson(<String, Object?>{
      ..._row(
        events: <Object?>[
          <String, Object?>{
            ..._event(),
            'coverUrl': 'https://cdn.example.test/poster.jpg',
          },
        ],
      ),
      'logoUrl': 'https://cdn.example.test/logo.png',
    });
    expect(association!.logoUrl, 'https://cdn.example.test/logo.png');
    expect(
      association.events.single.coverUrl,
      'https://cdn.example.test/poster.jpg',
    );

    final unsafe = Association.fromJson(<String, Object?>{
      ..._row(),
      'logoUrl': 'http://example.test/logo.png',
    });
    expect(unsafe!.logoUrl, isNull);
  });

  test('blank links read as absent while LinkedIn is kept', () {
    final links = AssociationLinks.fromJson(<String, Object?>{
      'instagram': '   ',
      'website': '',
      'email': 42,
      'linkedin':
          'https://www.linkedin.com/company/ouest-insa-junior-entreprise/',
    });
    expect(
      links.linkedin,
      'https://www.linkedin.com/company/ouest-insa-junior-entreprise/',
    );
  });

  group('events split on the clock, not on a flag', () {
    // Built per test: fromJson needs the timezone database, which setUpAll
    // loads after a group body has already run.
    Association subject() => Association.fromJson(
      _row(
        events: <Object?>[
          _event(id: 'before', startsAt: '2026-01-10T20:00:00'),
          // Started, not finished: still what is on tonight.
          _event(
            id: 'running',
            startsAt: '2026-03-14T20:00:00',
            endsAt: '2026-03-15T02:00:00',
          ),
          _event(id: 'after', startsAt: '2026-06-01T20:00:00'),
        ],
      ),
    )!;
    DateTime now() => campusInstant(DateTime(2026, 3, 14, 21));

    test('an event still running counts as upcoming', () {
      expect(subject().upcoming(now()).map((e) => e.id), <String>[
        'running',
        'after',
      ]);
    });

    test('past events come back newest first', () {
      expect(subject().past(now()).map((e) => e.id), <String>['before']);
    });
  });

  group('parsing the file', () {
    test('a version the app does not know is refused whole', () {
      const json = '{"version": 99, "associations": [{"id":"a","name":"A"}]}';
      expect(Associations.parse(json), isEmpty);
    });

    test('associations come back sorted by name', () {
      const json = '''
      {"version": 1, "associations": [
        {"id":"z","name":"Zythologie"},
        {"id":"a","name":"Arts"}
      ]}''';
      expect(Associations.parse(json).map((a) => a.id), <String>['a', 'z']);
    });

    test('junk does not take the whole list down', () {
      expect(Associations.parse('not json'), isEmpty);
      expect(Associations.parse('[]'), isEmpty);
      expect(Associations.parse('{"version": 1}'), isEmpty);
    });
  });

  group('remote directory', () {
    test('uses a valid Worker feed before the bundled seed', () async {
      final directory = await Associations.load(
        client: MockClient((request) async {
          expect(request.url.path, '/associations');
          return http.Response(
            '{"version":1,"updatedAt":"2026-09-17T00:00:00Z",'
            '"associations":[{"id":"remote","name":"À distance",'
            '"category":"tech"}]}',
            200,
          );
        }),
      );
      expect(directory.map((association) => association.id), <String>[
        'remote',
      ]);
    });

    test('falls back to the bundled seed when the Worker fails', () async {
      final directory = await Associations.load(
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );
      expect(directory, isNotEmpty);
    });
  });

  group('fast directory', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test(
      'uses a valid cached Worker response before the bundled seed',
      () async {
        const response =
            '{"version":1,"associations":[{"id":"cached",'
            '"name":"En cache","category":"tech"}]}';
        await Associations.refreshCache(
          client: MockClient((_) async => http.Response(response, 200)),
        );

        final directory = await Associations.loadFast();
        expect(directory.map((association) => association.id), <String>[
          'cached',
        ]);
      },
    );

    test('falls back to the bundled seed without a cached directory', () async {
      expect(await Associations.loadFast(), isNotEmpty);
    });
  });

  test('the display name prefers the short one', () {
    expect(Association.fromJson(_row())!.displayName, 'Association Ktulu');
    final short = Association.fromJson(<String, Object?>{
      ..._row(),
      'shortName': 'Ktulu',
    });
    expect(short!.displayName, 'Ktulu');
  });

  test('search covers the name, the short name and the summary', () {
    final association = Association.fromJson(<String, Object?>{
      ..._row(),
      'shortName': 'Ktulu',
      'summary': 'Le club théâtre du campus',
    })!;
    bool search(String typed) =>
        association.matchesFolded(foldForSearch(typed));

    expect(search(''), isTrue);
    expect(search('ktu'), isTrue);
    // Nobody types the accents into a search field.
    expect(search('THEATRE'), isTrue);
    expect(search('théâtre'), isTrue);
    expect(search('robotique'), isFalse);
  });
}
