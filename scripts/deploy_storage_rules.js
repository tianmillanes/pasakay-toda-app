const fs = require('fs');
const https = require('https');
const crypto = require('crypto');

async function main() {
    const saPath = 'scripts/serviceAccountKey.json';
    if (!fs.existsSync(saPath)) {
        console.error('ERROR: Service account file not found at', saPath);
        process.exit(1);
    }
    const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
    
    let rulesSource = fs.readFileSync('storage.rules', 'utf8');

    const bucketId = sa.project_id + '.firebasestorage.app'; // Or .appspot.com
    
    const jwt = generateJwt(sa);
    const accessToken = await getAccessToken(jwt);
    console.log('✓ Got access token');

    const rulesetName = await createRuleset(accessToken, sa.project_id, rulesSource);
    console.log('✓ Ruleset created:', rulesetName);

    // Try .firebasestorage.app first
    let releaseName = `projects/${sa.project_id}/releases/firebase.storage/${bucketId}`;
    let success = await releaseRuleset(accessToken, releaseName, rulesetName);
    
    if (success) {
        console.log('✅ Storage Rules deployed successfully to', bucketId);
    } else {
        console.log('Falling back to .appspot.com bucket...');
        const fallbackBucketId = sa.project_id + '.appspot.com';
        releaseName = `projects/${sa.project_id}/releases/firebase.storage/${fallbackBucketId}`;
        success = await releaseRuleset(accessToken, releaseName, rulesetName);
        if (success) {
            console.log('✅ Storage Rules deployed successfully to', fallbackBucketId);
        } else {
            console.error('Failed to deploy to both bucket variants.');
            process.exit(1);
        }
    }
}

function generateJwt(sa) {
    const header = { alg: 'RS256', typ: 'JWT' };
    const now = Math.floor(Date.now() / 1000);
    const payload = {
        iss: sa.client_email,
        scope: 'https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600
    };

    const encodedHeader = base64url(JSON.stringify(header));
    const encodedPayload = base64url(JSON.stringify(payload));
    const signingInput = `${encodedHeader}.${encodedPayload}`;

    const sign = crypto.createSign('RSA-SHA256');
    sign.update(signingInput);
    const signature = sign.sign(sa.private_key, 'base64')
        .replace(/=/g, '')
        .replace(/\+/g, '-')
        .replace(/\//g, '_');

    return `${signingInput}.${signature}`;
}

function base64url(str) {
    return Buffer.from(str).toString('base64')
        .replace(/=/g, '')
        .replace(/\+/g, '-')
        .replace(/\//g, '_');
}

function getAccessToken(jwt) {
    return new Promise((resolve, reject) => {
        const postData = `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`;
        const req = https.request({
            hostname: 'oauth2.googleapis.com',
            path: '/token',
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Content-Length': Buffer.byteLength(postData)
            }
        }, res => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                const json = JSON.parse(data);
                if (json.access_token) resolve(json.access_token);
                else reject(data);
            });
        });
        req.on('error', reject);
        req.write(postData);
        req.end();
    });
}

function createRuleset(token, projectId, rulesSource) {
    return new Promise((resolve, reject) => {
        const postData = JSON.stringify({
            source: { files: [{ name: 'storage.rules', content: rulesSource }] }
        });
        const req = https.request({
            hostname: 'firebaserules.googleapis.com',
            path: `/v1/projects/${projectId}/rulesets`,
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData)
            }
        }, res => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                const json = JSON.parse(data);
                if (res.statusCode === 200 && json.name) resolve(json.name);
                else reject(`Ruleset creation failed (${res.statusCode}): ${data}`);
            });
        });
        req.on('error', reject);
        req.write(postData);
        req.end();
    });
}

function releaseRuleset(token, releaseName, rulesetName) {
    return new Promise((resolve) => {
        const postData = JSON.stringify({ name: releaseName, rulesetName: rulesetName });
        
        // Try PATCH first
        const patchReq = https.request({
            hostname: 'firebaserules.googleapis.com',
            path: `/v1/${releaseName}`,
            method: 'PATCH',
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData)
            }
        }, res => {
            if (res.statusCode === 200) {
                resolve(true);
            } else {
                // If PATCH fails, try POST to create release
                const postReq = https.request({
                    hostname: 'firebaserules.googleapis.com',
                    path: `/v1/${releaseName.split('/').slice(0, 4).join('/')}`, 
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${token}`,
                        'Content-Type': 'application/json',
                        'Content-Length': Buffer.byteLength(postData)
                    }
                }, res2 => {
                    resolve(res2.statusCode === 200);
                });
                postReq.on('error', () => resolve(false));
                postReq.write(postData);
                postReq.end();
            }
        });
        patchReq.on('error', () => resolve(false));
        patchReq.write(postData);
        patchReq.end();
    });
}

main().catch(console.error);
