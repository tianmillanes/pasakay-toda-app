// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

void main() async {
  final saFile = File('../../scripts/serviceAccountKey.json');
  if (!saFile.existsSync()) {
    print('ERROR: serviceAccountKey.json not found');
    exit(1);
  }

  final rulesFile = File('../../firestore.rules');
  if (!rulesFile.existsSync()) {
    print('ERROR: firestore.rules not found');
    exit(1);
  }

  final saJson = jsonDecode(saFile.readAsStringSync()) as Map<String, dynamic>;
  final projectId = saJson['project_id'] as String;
  final rulesSource = rulesFile.readAsStringSync();

  print('Project: $projectId');
  print('Rules loaded (${rulesSource.length} chars)');

  // Authenticate with service account
  final credentials = auth.ServiceAccountCredentials.fromJson(saJson);
  final scopes = [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/firebase',
  ];

  final client = await auth.clientViaServiceAccount(credentials, scopes);
  print('✓ Authenticated');

  try {
    // Step 1: Create ruleset
    final createResp = await client.post(
      Uri.parse('https://firebaserules.googleapis.com/v1/projects/$projectId/rulesets'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'source': {
          'files': [{'name': 'firestore.rules', 'content': rulesSource}]
        }
      }),
    );

    if (createResp.statusCode != 200) {
      print('ERROR creating ruleset (${createResp.statusCode}): ${createResp.body}');
      exit(1);
    }

    final rulesetName = jsonDecode(createResp.body)['name'] as String;
    print('✓ Ruleset created: $rulesetName');

    // Step 2: Release (activate) the ruleset
    final releasePayload = jsonEncode({
      'name': 'projects/$projectId/releases/cloud.firestore',
      'rulesetName': rulesetName,
    });

    // Try PATCH first
    final patchResp = await client.patch(
      Uri.parse('https://firebaserules.googleapis.com/v1/projects/$projectId/releases/cloud.firestore'),
      headers: {'Content-Type': 'application/json'},
      body: releasePayload,
    );

    if (patchResp.statusCode == 200) {
      print('✅ Firestore rules deployed successfully!');
    } else {
      // Fallback: POST
      final postResp = await client.post(
        Uri.parse('https://firebaserules.googleapis.com/v1/projects/$projectId/releases'),
        headers: {'Content-Type': 'application/json'},
        body: releasePayload,
      );

      if (postResp.statusCode == 200) {
        print('✅ Firestore rules deployed successfully!');
      } else {
        print('ERROR releasing rules (${postResp.statusCode}): ${postResp.body}');
        exit(1);
      }
    }
  } finally {
    client.close();
  }

  exit(0);
}
