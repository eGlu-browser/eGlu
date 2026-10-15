// The web token's turns (src/cloudkit.js): each answer's token is the one
// the next request sends, whichever header it came in and whatever else the
// answer said, and only a refusal to sign in takes the token away.
//
//   node --test Extension/tests/cloudkit.test.mjs

import test from 'node:test';
import assert from 'node:assert/strict';

const kept = {};
globalThis.chrome = {
  storage: {
    local: {
      get: async (key) => (key in kept ? { [key]: kept[key] } : {}),
      set: async (values) => { Object.assign(kept, values); },
      remove: async (key) => { delete kept[key]; },
    },
  },
};

const { CloudKit, CloudKitError, SignedOut } = await import('../src/cloudkit.js');

// Answers in turn, and what each request sent.
function answering(...answers) {
  const sent = [];
  globalThis.fetch = async (url) => {
    sent.push(new URL(url).searchParams.get('ckWebAuthToken'));
    const { status = 200, headers = {}, body = {} } = answers.shift();
    return {
      ok: status >= 200 && status < 300,
      status,
      headers: { get: (name) => headers[name.toLowerCase()] ?? null },
      json: async () => body,
    };
  };
  return sent;
}

const cloud = () => new CloudKit({ container: 'iCloud.test', environment: 'development', apiToken: 'api' });

test('each answer’s token is the next request’s', async () => {
  kept.ckWebAuthToken = 'first';
  const sent = answering(
    { headers: { 'x-apple-cloudkit-web-auth-token': 'second' } },
    { headers: { 'x-apple-cloudkit-session': 'third' } },
    { body: { ckWebAuthToken: 'fourth' } },
    {},
  );
  const ck = cloud();
  for (let i = 0; i < 4; i++) await ck.request('users/current');
  assert.deepEqual(sent, ['first', 'second', 'third', 'fourth']);
  assert.equal(kept.ckWebAuthToken, 'fourth', 'an answer with no token leaves the last one');
});

test('an answer that says try again later still hands over the next token', async () => {
  kept.ckWebAuthToken = 'spent';
  const sent = answering(
    { status: 503, headers: { 'x-apple-cloudkit-web-auth-token': 'fresh' }, body: { serverErrorCode: 'TRY_AGAIN_LATER', retryAfter: 3 } },
    {},
  );
  const ck = cloud();
  await assert.rejects(ck.request('changes/zone', {}), CloudKitError);
  await ck.request('changes/zone', {});
  assert.deepEqual(sent, ['spent', 'fresh']);
});

test('only being told to sign in takes the token away', async () => {
  kept.ckWebAuthToken = 'old';
  answering({ status: 421, body: { serverErrorCode: 'AUTHENTICATION_REQUIRED', redirectURL: 'https://apple.test/signin' } });
  const ck = cloud();
  await assert.rejects(ck.request('users/current'), (error) => error instanceof SignedOut && error.redirectURL === 'https://apple.test/signin');
  assert.equal(kept.ckWebAuthToken, undefined);
});

test('a token signed in with meanwhile is not the one taken away', async () => {
  kept.ckWebAuthToken = 'old';
  globalThis.fetch = async () => {
    kept.ckWebAuthToken = 'new sign-in';
    return { ok: false, status: 421, headers: { get: () => null }, json: async () => ({ serverErrorCode: 'AUTHENTICATION_REQUIRED' }) };
  };
  await assert.rejects(cloud().request('users/current'), SignedOut);
  assert.equal(kept.ckWebAuthToken, 'new sign-in');
});
