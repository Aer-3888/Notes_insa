import 'dart:convert';

import 'cas/cas_client.dart';
import 'cas/totp.dart';
import 'mdw/grade.dart';
import 'mdw/grade_merge.dart';
import 'mdw/grade_parser.dart';
import 'mdw/mdw_client.dart';
import 'mdw/vaadin_types.dart';

/// Why a background fetch stopped without grades.
enum BackgroundFetchStatus {
  ok,

  /// The CAS wants a second factor and no usable TOTP secret was supplied.
  needsReauth,

  /// The TOTP step was already claimed, so submitting would replay the code.
  totpStepClaimed,

  /// Anything the next run can reasonably retry.
  retry,
}

class BackgroundFetchResult {
  BackgroundFetchResult(this.status, {this.gradesJson, this.casSession});

  final BackgroundFetchStatus status;
  final String? gradesJson;

  /// The refreshed session, to be stored for the next run.
  final String? casSession;
}

/// Fetches grades without touching any plugin.
///
/// Credentials arrive as arguments rather than being read here, so this runs in
/// a headless isolate where plugins are not registered.
Future<BackgroundFetchResult> runBackgroundFetch({
  required String username,
  required String password,
  String? otpSecret,
  String? casSession,
  int? claimedTotpStep,
  Future<void> Function(int step)? claimTotpStep,
}) async {
  final cas = CasClient();
  MdwClient? mdw;

  try {
    var authenticated = false;
    if (casSession != null && casSession.isNotEmpty) {
      try {
        cas.importSession(casSession);
        authenticated = await cas.isAuthenticated();
      } on FormatException {
        authenticated = false;
      } on CasException {
        authenticated = false;
      }
    }

    if (!authenticated) {
      try {
        await cas.auth(username, password);
      } on CasException {
        return BackgroundFetchResult(BackgroundFetchStatus.retry);
      }

      if (cas.isTokenNeeded) {
        if (otpSecret == null || otpSecret.isEmpty) {
          return BackgroundFetchResult(BackgroundFetchStatus.needsReauth);
        }

        // The foreground shares this secret, so a step already claimed would
        // replay the same one-time code and be rejected.
        final step = Totp.stepAt(DateTime.now());
        if (claimedTotpStep == step) {
          return BackgroundFetchResult(BackgroundFetchStatus.totpStepClaimed);
        }
        await claimTotpStep?.call(step);

        try {
          await cas.autoValidate(otpSecret);
        } on CasException {
          return BackgroundFetchResult(BackgroundFetchStatus.retry);
        }
      }
    }

    mdw = MdwClient(cas.session);
    await mdw.init();
    final groupCount = await mdw.loadGroups();
    if (groupCount <= 0) {
      return BackgroundFetchResult(BackgroundFetchStatus.retry);
    }

    Map<String, dynamic>? merged;
    final mergedDetails = <dynamic>[];

    for (var i = 0; i < groupCount; i++) {
      final Grade? root;
      try {
        root = await _fetchGroup(mdw, i);
      } on VaadinException {
        continue;
      }
      if (root == null) continue;

      final group = root.toJson();
      merged ??= group;
      final details = group['details'];
      if (details is List) mergeGradeDetails(mergedDetails, details);
    }

    if (merged == null) {
      return BackgroundFetchResult(BackgroundFetchStatus.retry);
    }

    merged['details'] = mergedDetails;
    return BackgroundFetchResult(
      BackgroundFetchStatus.ok,
      gradesJson: jsonEncode(merged),
      casSession: cas.exportSession(),
    );
  } on CasException {
    return BackgroundFetchResult(BackgroundFetchStatus.retry);
  } on VaadinException {
    return BackgroundFetchResult(BackgroundFetchStatus.retry);
  } finally {
    await mdw?.dispose();
    cas.close();
  }
}

Future<Grade?> _fetchGroup(MdwClient mdw, int index) async {
  final responses = <VaadinData>[await mdw.openGrades(index)];
  await mdw.confirmRows(_parentKeys(responses));

  for (var page = 0; page < 8; page++) {
    final missing = GradeParser.missingChildKeys(
      GradeParser.rowsOf(VaadinData.merge(responses)),
    );
    if (missing.isEmpty) break;
    responses.add(await mdw.requestChildren(missing));
    await mdw.confirmRows(_parentKeys(responses));
  }

  final root = GradeParser.parse(VaadinData.merge(responses));
  await mdw.closeGrades();
  return root;
}

List<String> _parentKeys(List<VaadinData> responses) => GradeParser.rowsOf(
  VaadinData.merge(responses),
).where((GradeRow r) => r.hasChildren).map((GradeRow r) => r.key).toList();
