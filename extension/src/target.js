(function installMoondiffTarget(root) {
  "use strict";

  const OWNER = /^(?!-)[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
  const REPO = /^(?!\.{1,2}$)[A-Za-z0-9._-]{1,100}$/;
  const SHA = /^[A-Fa-f0-9]{7,64}$/;
  const NUMBER = /^[1-9][0-9]*$/;

  function parseGitHubTarget(input) {
    let url;
    try {
      url = input instanceof URL ? input : new URL(String(input));
    } catch {
      return null;
    }
    if (url.protocol !== "https:" || url.hostname.toLowerCase() !== "github.com" || url.port) {
      return null;
    }
    let parts;
    try {
      parts = url.pathname.split("/").filter(Boolean).map(decodeURIComponent);
    } catch {
      return null;
    }
    if (parts.length < 4) return null;
    const [owner, repo, kind] = parts;
    if (!OWNER.test(owner) || !REPO.test(repo)) return null;
    if (kind === "commit" && parts.length === 4 && SHA.test(parts[3])) {
      return { owner, repo, kind: "commit", sha: parts[3] };
    }
    if (kind !== "pull" || !NUMBER.test(parts[3])) return null;
    const number = parts[3];
    if (
      parts.length === 4 ||
      (parts.length === 5 && ["files", "commits"].includes(parts[4]))
    ) {
      return { owner, repo, kind: "pull", number };
    }
    if (
      parts.length === 6 &&
      ["commits", "changes"].includes(parts[4]) &&
      SHA.test(parts[5])
    ) {
      return { owner, repo, kind: "pull_commit", number, sha: parts[5] };
    }
    return null;
  }

  function targetHash(target) {
    if (!target) return "";
    const rootPath = `#/${target.owner}/${target.repo}`;
    if (target.kind === "commit") return `${rootPath}/commit/${target.sha}`;
    if (target.kind === "pull") return `${rootPath}/pull/${target.number}`;
    if (target.kind === "pull_commit") {
      return `${rootPath}/pull/${target.number}/commits/${target.sha}`;
    }
    return "";
  }

  function sameTarget(left, right) {
    return Boolean(left && right && targetHash(left) === targetHash(right));
  }

  root.MoondiffTarget = Object.freeze({
    parseGitHubTarget,
    sameTarget,
    targetHash,
    validators: Object.freeze({ OWNER, REPO, SHA, NUMBER }),
  });
})(globalThis);
