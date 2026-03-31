// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

void main() async {
  final saFile = File('scripts/serviceAccountKey.json');
  if (!saFile.existsSync()) {
    print('ERROR: scripts/serviceAccountKey.json not found');
    exit(1);
  }
  final saJson = jsonDecode(saFile.readAsStringSync()) as Map<String, dynamic>;
  final projectId = saJson['project_id'] as String;
  final clientEmail = saJson['client_email'] as String;
  final privateKey = saJson['private_key'] as String;

  print('Project: $projectId');
  print('Service Account: $clientEmail');

  final rulesFile = File('firestore.rules');
  if (!rulesFile.existsSync()) {
    print('ERROR: firestore.rules not found');
    exit(1);
  }
  final rulesSource = rulesFile.readAsStringSync();
  print('Rules file loaded (${rulesSource.length} chars)');

  // Create JWT components
  final now = DateTime.now().toUtc();
  final exp = now.add(const Duration(hours: 1));

  final headerB64 = _b64url(utf8.encode(jsonEncode({'alg': 'RS256', 'typ': 'JWT'})));
  final payloadB64 = _b64url(utf8.encode(jsonEncode({
    'iss': clientEmail,
    'scope': 'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase',
    'aud': 'https://oauth2.googleapis.com/token',
    'iat': now.millisecondsSinceEpoch ~/ 1000,
    'exp': exp.millisecondsSinceEpoch ~/ 1000,
  })));

  final signingInput = '$headerB64.$payloadB64';

  // Extract base64 key body from PEM
  final pemLines = privateKey.split('\n')
      .where((l) => !l.startsWith('-----') && l.trim().isNotEmpty)
      .join('');

  // Write temp files for PowerShell
  final keyFile = File('scripts/_tmp_key_b64.txt');
  keyFile.writeAsStringSync(pemLines);

  final inputFile = File('scripts/_tmp_signing_input.txt');
  inputFile.writeAsStringSync(signingInput);

  // Use PowerShell with manual PKCS8 parsing (compatible with older .NET)
  final psResult = await Process.run('powershell', [
    '-NoProfile', '-Command',
    r'''
$ErrorActionPreference = "Stop"
$keyB64 = Get-Content "scripts/_tmp_key_b64.txt" -Raw
$inputText = Get-Content "scripts/_tmp_signing_input.txt" -Raw
$keyBytes = [Convert]::FromBase64String($keyB64.Trim())
$inputBytes = [System.Text.Encoding]::UTF8.GetBytes($inputText.Trim())

# Create RSA from PKCS8 key
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportPkcs8PrivateKey($keyBytes, [ref]$null)
$signature = $rsa.SignData($inputBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
[Convert]::ToBase64String($signature)
'''
  ]);

  // Cleanup temp files
  try { keyFile.deleteSync(); } catch (_) {}
  try { inputFile.deleteSync(); } catch (_) {}

  if (psResult.exitCode != 0) {
    print('PowerShell RSA failed, trying C# inline...');
    // Fallback: use inline C# compilation via PowerShell Add-Type
    final psResult2 = await Process.run('powershell', [
      '-NoProfile', '-Command',
      r'''
$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

public class JwtSigner {
    public static string Sign(string keyB64Path, string inputPath) {
        string keyB64 = File.ReadAllText(keyB64Path).Trim();
        string input = File.ReadAllText(inputPath).Trim();
        byte[] keyBytes = Convert.FromBase64String(keyB64);
        byte[] inputBytes = Encoding.UTF8.GetBytes(input);
        
        using (var rsa = RSA.Create()) {
            rsa.ImportPkcs8PrivateKey(keyBytes, out _);
            byte[] sig = rsa.SignData(inputBytes, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            return Convert.ToBase64String(sig);
        }
    }
}
"@ -ReferencedAssemblies "System.Security.Cryptography.Algorithms","System.Security.Cryptography.Primitives","System.Runtime","System.IO","netstandard" -ErrorAction Stop

[JwtSigner]::Sign("scripts/_tmp_key_b64.txt", "scripts/_tmp_signing_input.txt")
'''
    ]);

    if (psResult2.exitCode != 0) {
      print('ERROR: Could not sign JWT.');
      print('stderr: ${psResult2.stderr}');
      print('\nPlease deploy rules manually from Firebase Console.');
      print('Copy the contents of firestore.rules to:');
      print('  Firebase Console > Firestore > Rules > Edit > Publish');
      exit(1);
    }

    final sig2 = (psResult2.stdout as String).trim()
        .replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
    await _deployWithToken('$signingInput.$sig2', projectId, rulesSource);
    return;
  }

  final sig = (psResult.stdout as String).trim()
      .replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

  await _deployWithToken('$signingInput.$sig', projectId, rulesSource);
}

Future<void> _deployWithToken(String jwt, String projectId, String rulesSource) async {
  // Exchange JWT for access token
  final tokenClient = HttpClient();
  final tokenReq = await tokenClient.postUrl(Uri.parse('https://oauth2.googleapis.com/token'));
  tokenReq.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
  tokenReq.write('grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$jwt');
  final tokenResp = await tokenReq.close();
  final tokenBody = await tokenResp.transform(utf8.decoder).join();
  final tokenJson = jsonDecode(tokenBody);

  if (tokenJson['access_token'] == null) {
    print('ERROR getting access token: $tokenBody');
    exit(1);
  }

  final accessToken = tokenJson['access_token'] as String;
  print('✓ Access token obtained');

  // Create ruleset
  final client = HttpClient();
  final createReq = await client.postUrl(Uri.parse(
    'https://firebaserules.googleapis.com/v1/projects/$projectId/rulesets'
  ));
  createReq.headers.set('Authorization', 'Bearer $accessToken');
  createReq.headers.contentType = ContentType.json;
  createReq.write(jsonEncode({
    'source': {
      'files': [{'name': 'firestore.rules', 'content': rulesSource}]
    }
  }));
  final createResp = await createReq.close();
  final createBody = await createResp.transform(utf8.decoder).join();

  if (createResp.statusCode != 200) {
    print('ERROR creating ruleset (${createResp.statusCode}): $createBody');
    exit(1);
  }

  final rulesetName = jsonDecode(createBody)['name'] as String;
  print('✓ Ruleset created: $rulesetName');

  // Release ruleset
  final payload = jsonEncode({
    'name': 'projects/$projectId/releases/cloud.firestore',
    'rulesetName': rulesetName,
  });

  final relReq = await client.openUrl('PATCH', Uri.parse(
    'https://firebaserules.googleapis.com/v1/projects/$projectId/releases/cloud.firestore'
  ));
  relReq.headers.set('Authorization', 'Bearer $accessToken');
  relReq.headers.contentType = ContentType.json;
  relReq.write(payload);
  final relResp = await relReq.close();
  await relResp.transform(utf8.decoder).join();

  if (relResp.statusCode == 200) {
    print('✅ Firestore rules deployed successfully!');
  } else {
    final relReq2 = await client.postUrl(Uri.parse(
      'https://firebaserules.googleapis.com/v1/projects/$projectId/releases'
    ));
    relReq2.headers.set('Authorization', 'Bearer $accessToken');
    relReq2.headers.contentType = ContentType.json;
    relReq2.write(payload);
    final relResp2 = await relReq2.close();
    final relBody2 = await relResp2.transform(utf8.decoder).join();

    if (relResp2.statusCode == 200) {
      print('✅ Firestore rules deployed successfully!');
    } else {
      print('ERROR releasing (${relResp2.statusCode}): $relBody2');
      exit(1);
    }
  }

  client.close();
  tokenClient.close();
  exit(0);
}

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
