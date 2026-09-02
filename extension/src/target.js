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
    if (!target || typeof target !== "object" || Array.isArray(target)) return "";
    if (
      typeof target.owner !== "string" ||
      typeof target.repo !== "string" ||
      !OWNER.test(target.owner) ||
      !REPO.test(target.repo)
    ) return "";
    const rootPath = `#/${target.owner}/${target.repo}`;
    if (target.kind === "commit" && typeof target.sha === "string" && SHA.test(target.sha)) {
      return `${rootPath}/commit/${target.sha}`;
    }
    if (target.kind === "pull" && typeof target.number === "string" && NUMBER.test(target.number)) {
      return `${rootPath}/pull/${target.number}`;
    }
    if (
      target.kind === "pull_commit" &&
      typeof target.number === "string" &&
      typeof target.sha === "string" &&
      NUMBER.test(target.number) &&
      SHA.test(target.sha)
    ) {
      return `${rootPath}/pull/${target.number}/commits/${target.sha}`;
    }
    return "";
  }

  function parseTargetHash(input) {
    if (typeof input !== "string" || !input.startsWith("#/")) return null;
    const parts = input.slice(2).split("/");
    const [owner, repo, kind] = parts;
    if (!OWNER.test(owner || "") || !REPO.test(repo || "")) return null;
    if (kind === "commit" && parts.length === 4 && SHA.test(parts[3])) {
      return { owner, repo, kind: "commit", sha: parts[3] };
    }
    if (kind !== "pull" || !NUMBER.test(parts[3] || "")) return null;
    if (parts.length === 4) {
      return { owner, repo, kind: "pull", number: parts[3] };
    }
    if (parts.length === 6 && parts[4] === "commits" && SHA.test(parts[5])) {
      return { owner, repo, kind: "pull_commit", number: parts[3], sha: parts[5] };
    }
    return null;
  }

  function sameTarget(left, right) {
    const leftHash = targetHash(left);
    return Boolean(leftHash && leftHash === targetHash(right));
  }

  root.MoondiffTarget = Object.freeze({
    parseGitHubTarget,
    parseTargetHash,
    sameTarget,
    targetHash,
    validators: Object.freeze({ OWNER, REPO, SHA, NUMBER }),
  });
})(globalThis);
