// CloudKit Web Services for the user's private database: the REST interface
// to the same iCloud container the app syncs with, signed in with the
// user's Apple Account.
//
// Apple's sign-in gives a web token (ckWebAuthToken) that lasts 30 minutes
// from when it was made, or two weeks with "Keep me signed in" ticked on
// Apple's page, and changes with every request: each response carries the
// next one in a header, and the one sent stops working. So requests go one
// at a time, and the newest token is kept in chrome.storage.local.
//
// Staying signed in is then a matter of asking often enough: every sync
// makes a new token with a new 30 minutes or two weeks. Chrome closed, or
// the computer asleep, for longer than that is what signs it out, and
// nothing here can ask Apple for more: which of the two it is is the box
// on Apple's page and nothing in the request (Apple's own CloudKit JS
// sends nothing for its "persist" either, which is only where it keeps the
// token).
//
// https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/

import { ZONE } from './model.js';

const BASE = 'https://api.apple-cloudkit.com/database/1';

export class SignedOut extends Error {
  constructor(redirectURL) {
    super('Not signed in to iCloud');
    this.redirectURL = redirectURL;
  }
}

export class CloudKitError extends Error {
  constructor(code, reason, retryAfter) {
    super(`${code}: ${reason || ''}`);
    this.code = code;
    this.retryAfter = retryAfter;
  }
}

export class CloudKit {
  constructor({ container, environment, apiToken }) {
    this.container = container;
    this.environment = environment;
    this.apiToken = apiToken;
    this.queue = Promise.resolve();
  }

  async token() {
    return (await chrome.storage.local.get('ckWebAuthToken')).ckWebAuthToken || null;
  }

  async setToken(token) {
    if (token) await chrome.storage.local.set({ ckWebAuthToken: token });
    else await chrome.storage.local.remove('ckWebAuthToken');
  }

  // One request at a time: each changes the token the next one needs.
  request(path, body) {
    const run = this.queue.then(() => this.send(path, body));
    this.queue = run.catch(() => {});
    return run;
  }

  async send(path, body, signedIn = true) {
    const token = signedIn ? await this.token() : null;
    let url = `${BASE}/${this.container}/${this.environment}/private/${path}?ckAPIToken=${encodeURIComponent(this.apiToken)}`;
    if (token) url += `&ckWebAuthToken=${encodeURIComponent(token)}`;
    const response = await fetch(url, {
      method: body ? 'POST' : 'GET',
      headers: body ? { 'Content-Type': 'application/json' } : {},
      body: body ? JSON.stringify(body) : undefined,
    });
    let json = {};
    try { json = await response.json(); } catch (_) {}
    // The next token, under either name Apple's own library reads it by
    // (cloudkit.js: the web auth token's header, then the session's).
    const next = response.headers.get('X-Apple-CloudKit-Web-Auth-Token') || response.headers.get('X-Apple-CloudKit-Session')
      || json.ckWebAuthToken || json.webAuthToken || json.ckSession;
    if (json.serverErrorCode === 'AUTHENTICATION_REQUIRED' || response.status === 401 || response.status === 421) {
      // Only the token that failed goes: a sign-in may have put a new one in meanwhile.
      if (signedIn && token && (await this.token()) === token) await this.setToken(null);
      throw new SignedOut(json.redirectURL);
    }
    // Kept whatever else the answer says: the token sent is spent once an
    // answer has come, so one that says "try again later" and carries the
    // next token would otherwise leave nothing to try again with.
    if (next && signedIn) await this.setToken(next);
    if (!response.ok || json.serverErrorCode) {
      throw new CloudKitError(json.serverErrorCode || `HTTP ${response.status}`, json.reason, json.retryAfter);
    }
    return json;
  }

  // Apple's sign-in, in a window of Chrome's own: it ends at the callback
  // URL set for the API token in CloudKit Console, which must be this
  // extension's https://<id>.chromiumapp.org/ address, with the token in it.
  async signIn() {
    let redirectURL = null;
    try {
      await this.send('users/current', null, false);
    } catch (error) {
      if (!(error instanceof SignedOut)) throw error;
      redirectURL = error.redirectURL;
    }
    if (!redirectURL) throw new Error('CloudKit gave no sign-in page. Check the API token in config.js.');
    const done = await chrome.identity.launchWebAuthFlow({ url: redirectURL, interactive: true });
    const answer = new URL(done);
    const params = new URLSearchParams(answer.search + '&' + answer.hash.replace(/^#/, ''));
    // Apple's documentation calls it ckWebAuthToken; the callback has also been seen to say ckSession.
    const token = params.get('ckWebAuthToken') || params.get('ckSession');
    if (!token) throw new Error('Apple’s sign-in came back without a token.');
    // In turn with the requests, which each change the token.
    this.queue = this.queue.then(() => this.setToken(token));
    await this.queue;
    return this.request('users/current');
  }

  async signOut() {
    await this.setToken(null);
  }

  // The app makes the zone too; whichever comes first.
  async ensureZone() {
    const found = await this.request('zones/lookup', { zones: [{ zoneName: ZONE }] });
    const zone = found.zones?.[0];
    if (zone && !zone.serverErrorCode) return;
    await this.request('zones/modify', { operations: [{ operationType: 'create', zone: { zoneID: { zoneName: ZONE } } }] });
  }

  // Every change since `syncToken` (all of it for none), page by page.
  async changes(syncToken) {
    const records = [];
    let token = syncToken || undefined;
    for (let page = 0; page < 1000; page++) {
      const zone = { zoneID: { zoneName: ZONE }, resultsLimit: 200 };
      if (token) zone.syncToken = token;
      const result = await this.request('changes/zone', { zones: [zone] });
      const answer = result.zones?.[0] || {};
      if (answer.serverErrorCode === 'ZONE_NOT_FOUND') return { records, syncToken: null, zoneMissing: true };
      if (answer.serverErrorCode) throw new CloudKitError(answer.serverErrorCode, answer.reason, answer.retryAfter);
      records.push(...(answer.records || []));
      // Deletions come in `records` with deleted: true (Apple's reference);
      // a separate list is taken too, should a response have one.
      records.push(...(answer.deleted || []).map((d) => ({ ...d, deleted: true })));
      token = answer.syncToken;
      if (!answer.moreComing) break;
    }
    return { records, syncToken: token };
  }

  // Saves (whole records, replacing iCloud's) and deletions, 200 to a request.
  async modify(saves, deletions) {
    const operations = [
      ...saves.map((record) => ({ operationType: 'forceReplace', record })),
      ...deletions.map((recordName) => ({ operationType: 'forceDelete', record: { recordName } })),
    ];
    const failed = [];
    for (let i = 0; i < operations.length; i += 200) {
      const result = await this.request('records/modify', {
        operations: operations.slice(i, i + 200), zoneID: { zoneName: ZONE }, atomic: false,
      });
      for (const record of result.records || []) {
        // A record already gone needs no deleting.
        if (record.serverErrorCode && record.serverErrorCode !== 'NOT_FOUND') failed.push(record);
      }
    }
    return failed;
  }
}
