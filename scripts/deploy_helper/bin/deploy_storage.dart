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

  final rulesFile = File('../../storage.rules');
  if (!rulesFile.existsSync()) {
    print('ERROR: storage.rules not found');
    exit(1);
  }

  final saJson = jsonDecode(saFile.readAsStringSync()) as Map<String, dynamic>;
  final projectId = saJson['project_id'] as String;
  // Getting the storage bucket from google-services.json
  final bucketId = '$projectId.firebasestorage.app'; 
  final rulesSource = rulesFile.readAsStringSync();

  print('Project: $projectId');
  print('Bucket: $bucketId');
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
          'files': [{'name': 'storage.rules', 'content': rulesSource}]
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
    String releaseName = 'projects/$projectId/releases/firebase.storage/$bucketId';
    final releasePayload = jsonEncode({
      'name': releaseName,
      'rulesetName': rulesetName,
    });

    // Try PATCH first
    final patchResp = await client.patch(
      Uri.parse('https://firebaserules.googleapis.com/v1/$releaseName'),
      headers: {'Content-Type': 'application/json'},
      body: releasePayload,
    );

    if (patchResp.statusCode == 200) {
      print('✅ Storage rules deployed successfully to $bucketId!');
    } else {
      // Fallback: POST
      final postResp = await client.post(
        Uri.parse('https://firebaserules.googleapis.com/v1/projects/$projectId/releases'),
        headers: {'Content-Type': 'application/json'},
        body: releasePayload,
      );

      if (postResp.statusCode == 200) {
        print('✅ Storage rules deployed successfully to $bucketId!');
      } else {
        print('ERROR releasing rules (${postResp.statusCode}): ${postResp.body}');
        // Try falling back to .appspot.com
        final fallbackBucketId = '$projectId.appspot.com';
        final fallbackReleaseName = 'projects/$projectId/releases/firebase.storage/$fallbackBucketId';
        
        final fallbackReleasePayload = jsonEncode({
          'name': fallbackReleaseName,
          'rulesetName': rulesetName,
        });
        
        final fbPostResp = await client.post(
          Uri.parse('https://firebaserules.googleapis.com/v1/projects/$projectId/releases'),
          headers: {'Content-Type': 'application/json'},
          body: fallbackReleasePayload,
        );
        
        if (fbPostResp.statusCode == 200) {
           print('✅ Storage rules deployed successfully to $fallbackBucketId!');
        } else {
           print('ERROR fallback releasing rules (${fbPostResp.statusCode}): ${fbPostResp.body}');
           exit(1);
        }
      }
    }
  } finally {
    client.close();
  }

  exit(0);
}
