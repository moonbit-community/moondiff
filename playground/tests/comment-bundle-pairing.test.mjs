import assert from 'node:assert/strict';
import test from 'node:test';
import { CommentBundlePairingError, commentBundleKey, createCommentBundlePairs } from './comment-bundle-pairing.mjs';

test('comment bundles pair independently by normalized pull target', async () => {
  const pairs = createCommentBundlePairs();
  const first = pairs.begin({ owner: 'Owner', repo: 'Repo', number: '0007' });
  const second = pairs.begin({ owner: 'owner', repo: 'other', number: 7 });
  const firstReview = pairs.consume({ owner: 'OWNER', repo: 'repo', number: 7 });
  const secondReview = pairs.consume({ owner: 'OWNER', repo: 'OTHER', number: '7' });
  assert.equal(commentBundleKey({ owner: 'Owner', repo: 'Repo', number: '0007' }), 'owner/repo#7');
  assert.equal(pairs.publish(second, { name: 'second' }), true);
  assert.equal(pairs.publish(first, { name: 'first' }), true);
  assert.deepEqual(await firstReview, { name: 'first' });
  assert.deepEqual(await secondReview, { name: 'second' });
});

test('a late same-target issue generation cannot overwrite the latest bundle', async () => {
  const pairs = createCommentBundlePairs();
  const target = { owner: 'owner', repo: 'repo', number: 17 };
  const stale = pairs.begin(target);
  const latest = pairs.begin(target);
  assert(latest.sequence > stale.sequence);
  await assert.rejects(stale.result, /superseded/);
  assert.equal(pairs.publish(latest, { generation: 'latest' }), true);
  assert.equal(pairs.publish(stale, { generation: 'stale' }), false);
  assert.deepEqual(await pairs.consume(target), { generation: 'latest' });
});

test('starting a new issue invalidates an unconsumed completed generation', async () => {
  const pairs = createCommentBundlePairs();
  const target = { owner: 'owner', repo: 'repo', number: 17 };
  const stale = pairs.begin(target);
  assert.equal(pairs.publish(stale, { generation: 'stale' }), true);
  const latest = pairs.begin(target);
  assert.equal(pairs.publish(stale, { generation: 'too-late' }), false);
  assert.equal(pairs.publish(latest, { generation: 'latest' }), true);
  assert.deepEqual(await pairs.consume(target), { generation: 'latest' });
});

test('a newer issue invalidates a consumed generation that is still pending', async () => {
  const pairs = createCommentBundlePairs();
  const target = { owner: 'owner', repo: 'repo', number: 17 };
  const stale = pairs.begin(target);
  const staleReview = pairs.consume(target);
  const latest = pairs.begin(target);
  await assert.rejects(staleReview, /superseded/);
  assert.equal(pairs.publish(stale, { generation: 'stale' }), false);
  assert.equal(pairs.publish(latest, { generation: 'latest' }), true);
  assert.deepEqual(await pairs.consume(target), { generation: 'latest' });
});

test('cancelled and consumed generations cannot be consumed again', async () => {
  const pairs = createCommentBundlePairs();
  const target = { owner: 'owner', repo: 'repo', number: 17 };
  const cancelled = pairs.begin(target);
  assert.equal(pairs.cancel(cancelled, new CommentBundlePairingError('fixture request cancelled')), true);
  await assert.rejects(cancelled.result, /fixture request cancelled/);
  assert.throws(() => pairs.consume(target), /Missing issue-comments bundle/);

  const completed = pairs.begin(target);
  assert.equal(pairs.publish(completed, { generation: 'only' }), true);
  assert.deepEqual(await pairs.consume(target), { generation: 'only' });
  assert.throws(() => pairs.consume(target), /Missing issue-comments bundle/);
});
