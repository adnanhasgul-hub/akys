import 'dart:convert';
import 'dart:io';

import 'package:akys/modules/schedule_v2/data/draft_snapshot.dart';

Future<void> main() async {
  final input = jsonDecode(await utf8.decoder.bind(stdin).join()) as List;
  final results = <bool>[];
  for (final payload in input) {
    try {
      DraftSnapshot.decode(payload as String);
      results.add(true);
    } catch (_) {
      results.add(false);
    }
  }
  stdout.write(jsonEncode(results));
}
