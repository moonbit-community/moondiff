const entryForTicket = Symbol('comment bundle generation');

export class CommentBundlePairingError extends Error {
  constructor(message) {
    super(message);
    this.name = 'CommentBundlePairingError';
  }
}

export function commentBundleKey({ owner, repo, number }) {
  const normalizedOwner = String(owner ?? '').trim().toLowerCase();
  const normalizedRepo = String(repo ?? '').trim().toLowerCase();
  const rawNumber = String(number ?? '').trim();
  if (!normalizedOwner || !normalizedRepo || !/^\d+$/.test(rawNumber)) {
    throw new CommentBundlePairingError(`Invalid public comment target: ${owner}/${repo}#${number}`);
  }
  const normalizedNumber = rawNumber.replace(/^0+(?=\d)/, '');
  if (normalizedNumber === '0') {
    throw new CommentBundlePairingError(`Invalid public comment target: ${owner}/${repo}#${number}`);
  }
  return `${normalizedOwner}/${normalizedRepo}#${normalizedNumber}`;
}

export function createCommentBundlePairs() {
  const available = new Map();
  const latest = new Map();
  let nextSequence = 0;

  function invalidate(entry, error) {
    if (entry.invalidated) return;
    entry.invalidated = true;
    if (!entry.settled) {
      entry.settled = true;
      entry.reject(error);
    }
  }

  function entry(ticket) {
    const value = ticket?.[entryForTicket];
    if (!value) throw new CommentBundlePairingError('Unknown public comment bundle generation');
    return value;
  }

  return {
    begin(target) {
      const key = commentBundleKey(target);
      const previous = latest.get(key);
      if (previous) {
        if (available.get(key) === previous) available.delete(key);
        invalidate(previous, new CommentBundlePairingError(
          `Public comment bundle generation ${previous.sequence} for ${key} was superseded`,
        ));
      }
      let resolve;
      let reject;
      const result = new Promise((onResolve, onReject) => {
        resolve = onResolve;
        reject = onReject;
      });
      // A superseded issue request may have no review consumer. Keep its
      // rejected generation from becoming an unhandled test-process rejection.
      result.catch(() => {});
      const value = {
        key,
        sequence: ++nextSequence,
        result,
        resolve,
        reject,
        settled: false,
        invalidated: false,
        consumed: false,
      };
      available.set(key, value);
      latest.set(key, value);
      return Object.freeze({
        key,
        sequence: value.sequence,
        result,
        [entryForTicket]: value,
      });
    },

    publish(ticket, bundle) {
      const value = entry(ticket);
      if (value.invalidated || latest.get(value.key) !== value) return false;
      if (!value.settled) {
        value.settled = true;
        value.resolve(bundle);
      }
      if (value.consumed) latest.delete(value.key);
      return true;
    },

    cancel(ticket, cause = 'Public comment bundle request was cancelled') {
      const value = entry(ticket);
      if (value.invalidated) return false;
      if (available.get(value.key) === value) available.delete(value.key);
      if (latest.get(value.key) === value) latest.delete(value.key);
      const error = cause instanceof Error ? cause : new CommentBundlePairingError(String(cause));
      invalidate(value, error);
      return true;
    },

    consume(target) {
      const key = commentBundleKey(target);
      const value = available.get(key);
      if (!value) {
        throw new CommentBundlePairingError(
          `Missing issue-comments bundle for public review-comments request ${key}`,
        );
      }
      available.delete(key);
      value.consumed = true;
      if (value.settled && latest.get(key) === value) latest.delete(key);
      return value.result;
    },
  };
}
