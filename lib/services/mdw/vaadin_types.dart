/// One node change in a Vaadin UIDL response.
class VaadinNode {
  VaadinNode({
    required this.node,
    required this.type,
    required this.key,
    required this.value,
    required this.addNodes,
  });

  factory VaadinNode.fromJson(Map<String, dynamic> json) => VaadinNode(
    node: (json['node'] as num?)?.toInt() ?? 0,
    type: json['type'] as String? ?? '',
    key: json['key'] as String? ?? '',
    value: json['value'],
    addNodes: (json['addNodes'] as List<dynamic>?)
        ?.map((Object? e) => (e as num).toInt())
        .toList(),
  );

  final int node;
  final String type;
  final String key;
  final Object? value;
  final List<int>? addNodes;
}

/// The useful payload of a UIDL response: node changes plus the JS calls
/// Vaadin wants the browser to run.
class VaadinData {
  VaadinData({required this.changes, required this.execute, required this.raw});

  factory VaadinData.fromJson(Map<String, dynamic> json) => VaadinData(
    changes: (json['changes'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(VaadinNode.fromJson)
        .toList(),
    execute: (json['execute'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<List<dynamic>>()
        .toList(),
    raw: json,
  );

  /// Combines several responses so rows delivered in a later page can still
  /// resolve text that arrived with an earlier one.
  static VaadinData merge(List<VaadinData> parts) {
    if (parts.length == 1) return parts.first;
    return VaadinData(
      changes: <VaadinNode>[for (final VaadinData p in parts) ...p.changes],
      execute: <List<dynamic>>[for (final VaadinData p in parts) ...p.execute],
      raw: const <String, dynamic>{},
    );
  }

  final List<VaadinNode> changes;
  final List<List<dynamic>> execute;

  /// The undecoded response, kept so the capture tool can dump it verbatim.
  final Map<String, dynamic> raw;
}

class VaadinResponse {
  VaadinResponse({
    required this.syncId,
    required this.clientId,
    required this.sessionExpired,
    required this.data,
  });

  factory VaadinResponse.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'];
    return VaadinResponse(
      syncId: (json['syncId'] as num?)?.toInt() ?? 0,
      clientId: (json['clientId'] as num?)?.toInt() ?? 0,
      sessionExpired:
          meta is Map<String, dynamic> && meta['sessionExpired'] == true,
      data: VaadinData.fromJson(json),
    );
  }

  final int syncId;
  final int clientId;
  final bool sessionExpired;
  final VaadinData data;
}

/// One RPC in a UIDL request. Null fields are omitted, matching what the
/// Vaadin client sends.
class VaadinRpc {
  VaadinRpc({
    required this.node,
    required this.type,
    this.promise,
    this.feature,
    this.property,
    this.event,
    this.data,
    this.value,
    this.templateEventMethodName,
    this.templateEventMethodArgs,
  });

  final Object node;
  final String type;
  final Object? promise;
  final Object? feature;
  final Object? property;
  final Object? event;
  final Object? data;
  final Object? value;
  final Object? templateEventMethodName;
  final Object? templateEventMethodArgs;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'node': node, 'type': type};
    void put(String key, Object? v) {
      if (v != null) json[key] = v;
    }

    put('promise', promise);
    put('feature', feature);
    put('property', property);
    put('event', event);
    put('data', data);
    put('value', value);
    put('templateEventMethodName', templateEventMethodName);
    put('templateEventMethodArgs', templateEventMethodArgs);
    return json;
  }
}

class VaadinException implements Exception {
  VaadinException(this.message);

  final String message;

  @override
  String toString() => 'VaadinException: $message';
}
