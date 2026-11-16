// Emulator-only approval prototype. Production startup intentionally unavailable.
// Uses the SAME Dart validator and a signed test issuer (not unsigned Auth emulator tokens).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'approval.dart';
import 'token_verifier.dart';

class EmulatorApprovalStore {
  EmulatorApprovalStore(this.port);
  final int port;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  String get root =>
      'http://127.0.0.1:$port/v1/projects/demo-akys/databases/(default)/documents';
  Future<Map<String, dynamic>> request(
    String method,
    String url, [
    Object? body,
  ]) async {
    final r = await client.openUrl(method, Uri.parse(url));
    r.headers.set('Authorization', 'Bearer owner');
    r.headers.contentType = ContentType.json;
    if (body != null) r.write(jsonEncode(body));
    final response = await r.close().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        r.abort();
        throw TimeoutException('Approval store deadline');
      },
    );
    final value = jsonDecode(await utf8.decoder.bind(response).join());
    if (response.statusCode >= 400) {
      throw const ApprovalRejected('STORE_CONFLICT_OR_UNAVAILABLE');
    }
    return value is List
        ? {'documents': value}
        : Map<String, dynamic>.from(value as Map);
  }

  Future<Map<String, dynamic>> approve(
    String id,
    int version,
    String operation,
    String actor,
  ) async {
    final transaction =
        (await request('POST', '$root:beginTransaction', {}))['transaction']
            as String;
    try {
      final fetched = await request('POST', '$root:batchGet', {
        'documents': [
          'projects/demo-akys/databases/(default)/documents/v2_schedules/$id',
          'projects/demo-akys/databases/(default)/documents/v2_schedules/$id/versions/$version',
        ],
        'transaction': transaction,
      });
      final documents = (fetched['documents'] as List)
          .map((d) => d['found'])
          .whereType<Map>()
          .toList();
      if (documents.length != 2) throw const ApprovalRejected('NOT_FOUND');
      final head = documents.singleWhere(
        (d) => d['name'].endsWith('/v2_schedules/$id'),
      );
      final document = documents.singleWhere(
        (d) => d['name'].endsWith('/versions/$version'),
      );
      final fields = Map<String, dynamic>.from(document['fields'] as Map);
      final headFields = Map<String, dynamic>.from(head['fields'] as Map);
      if (headFields['version']['integerValue'] != '$version') {
        throw const ApprovalRejected('VERSION_CONFLICT');
      }
      if (headFields['status']['stringValue'] == 'approved') {
        if (headFields['approvalOperation']?['stringValue'] != operation ||
            headFields['approvedBy']?['stringValue'] != actor) {
          throw const ApprovalRejected('ALREADY_APPROVED');
        }
        return {'status': 'approved', 'version': version, 'idempotent': true};
      }
      if (headFields['status']['stringValue'] != 'draft' ||
          fields['status']['stringValue'] != 'draft') {
        throw const ApprovalRejected('NOT_DRAFT');
      }
      if (fields['version']['integerValue'] != '$version' ||
          fields['operationId'] != null &&
              jsonEncode(fields['operationId']) !=
                  jsonEncode(headFields['operationId'])) {
        throw const ApprovalRejected('SNAPSHOT_MISMATCH');
      }
      final snapshot = validateForApproval(
        fields['payload']['stringValue'] as String,
      );
      if (fields['year']?['integerValue'] !=
              '${snapshot.problem.startDate!.year}' ||
          fields['month']?['integerValue'] !=
              '${snapshot.problem.startDate!.month}' ||
          jsonEncode(fields['year']) != jsonEncode(headFields['year']) ||
          jsonEncode(fields['month']) != jsonEncode(headFields['month'])) {
        throw const ApprovalRejected('SNAPSHOT_MISMATCH');
      }
      final approval = {
        'status': {'stringValue': 'approved'},
        'approvedBy': {'stringValue': actor},
        'approvalOperation': {'stringValue': operation},
        'approvalPolicy': {
          'stringValue': 'A-hard-constraints-v1-no-optimality-claim',
        },
      };
      final writes = <Object>[];
      for (final doc in [head, document]) {
        writes.add({
          'update': {
            'name': doc['name'],
            'fields': {
              ...Map<String, dynamic>.from(doc['fields'] as Map),
              ...approval,
            },
          },
          'currentDocument': {'updateTime': doc['updateTime']},
          'updateTransforms': [
            {'fieldPath': 'approvedAt', 'setToServerValue': 'REQUEST_TIME'},
          ],
        });
      }
      final eventName =
          'projects/demo-akys/databases/(default)/documents/v2_schedules/$id/server_audit/$operation';
      writes.add({
        'update': {
          'name': eventName,
          'fields': {
            'action': {'stringValue': 'approvalSucceeded'},
            'actor': {'stringValue': actor},
            'version': {'integerValue': '$version'},
            'operationId': {'stringValue': operation},
          },
        },
        'currentDocument': {'exists': false},
        'updateTransforms': [
          {'fieldPath': 'at', 'setToServerValue': 'REQUEST_TIME'},
        ],
      });
      if (headFields['historySchema']?['integerValue'] == '2') {
        writes.add({
          'update': {
            'name':
                'projects/demo-akys/databases/(default)/documents/v2_schedules/$id/version_metadata/$version',
            'fields': {...headFields, ...approval},
          },
          'updateTransforms': [
            {'fieldPath': 'approvedAt', 'setToServerValue': 'REQUEST_TIME'},
          ],
        });
      }
      await request('POST', '$root:commit', {
        'transaction': transaction,
        'writes': writes,
      });
      return {'status': 'approved', 'version': version, 'idempotent': false};
    } finally {
      try {
        await request('POST', '$root:rollback', {'transaction': transaction});
      } catch (_) {
        /* committed transactions cannot roll back */
      }
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 3 || args[0] != '--emulator-only') {
    stderr.writeln(
      'Only --emulator-only <trusted-test-jwks.json> <port> is supported. No production adapter.',
    );
    exitCode = 64;
    return;
  }
  final keys = List<Map<String, dynamic>>.from(
    (jsonDecode(await File(args[1]).readAsString()) as Map)['keys'] as List,
  );
  final verifier = TokenVerifier('demo-akys', () async => keys);
  final store = EmulatorApprovalStore(8080);
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    int.parse(args[2]),
  );
  stdout.writeln('READY ${server.port} emulator-only');
  await for (final request in server) {
    unawaited(() async {
      try {
        if (request.method != 'POST' || request.uri.path != '/approve') {
          throw const ApprovalRejected('NOT_FOUND');
        }
        final bearer = request.headers.value('authorization') ?? '';
        if (!bearer.startsWith('Bearer ')) {
          throw const ApprovalRejected('UNAUTHORIZED');
        }
        final actor = await verifier.admin(bearer.substring(7));
        var size = 0;
        final bytes = <int>[];
        await for (final chunk in request) {
          size += chunk.length;
          if (size > 4096) throw const ApprovalRejected('TOO_LARGE');
          bytes.addAll(chunk);
        }
        final input = jsonDecode(utf8.decode(bytes)) as Map;
        if (input.length != 3 ||
            input['scheduleId'] is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(input['scheduleId']) ||
            input['version'] is! int ||
            input['version'] < 1 ||
            input['operationId'] is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]{20,64}$').hasMatch(input['operationId'])) {
          throw const ApprovalRejected('BAD_REQUEST');
        }
        final result = await store.approve(
          input['scheduleId'],
          input['version'],
          input['operationId'],
          actor,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
      } catch (e, stack) {
        stderr.writeln('Approval failure type: ${e.runtimeType}\n$stack');
        request.response.statusCode =
            e is ApprovalRejected && e.code == 'UNAUTHORIZED' ? 403 : 409;
        request.response.write(
          jsonEncode({
            'error': e is ApprovalRejected ? e.code : 'INVALID_OR_UNAVAILABLE',
          }),
        );
      } finally {
        await request.response.close();
      }
    }());
  }
}
