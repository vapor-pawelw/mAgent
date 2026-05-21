import "./style.css";

const root = document.getElementById("root");

let files = [];
let lastPatch = "";
let lastThemeType = "system";
let allCollapsed = false;
let isWrapped = false;
let currentVisiblePath = null;
let scrollFrameRequested = false;
let allowsReviewMarkers = true;
let reviewedFileSignatures = {};
let collapsedFileStates = {};
let highlightCorePromise = null;
let searchQuery = "";
let searchMode = "caseInsensitive";
let searchMatches = [];
let activeSearchIndex = -1;
const languagePromises = new Map();
const loadedLanguages = new Set();
const expandedContextByHunk = new Set();

const languageByExtension = new Map(
  Object.entries({
    bash: "bash",
    c: "c",
    cc: "cpp",
    cpp: "cpp",
    cs: "csharp",
    css: "css",
    cxx: "cpp",
    diff: "diff",
    go: "go",
    h: "cpp",
    hpp: "cpp",
    html: "xml",
    java: "java",
    js: "javascript",
    json: "json",
    jsx: "javascript",
    kt: "kotlin",
    kts: "kotlin",
    m: "objectivec",
    mm: "objectivec",
    md: "markdown",
    php: "php",
    py: "python",
    rb: "ruby",
    rs: "rust",
    sh: "bash",
    sql: "sql",
    swift: "swift",
    toml: "ini",
    ts: "typescript",
    tsx: "typescript",
    xml: "xml",
    yml: "yaml",
    yaml: "yaml",
    zig: "zig",
  })
);

const languageByFilename = new Map(
  Object.entries({
    dockerfile: "dockerfile",
    gemfile: "ruby",
    makefile: "makefile",
    package: "json",
    podfile: "ruby",
    rakefile: "ruby",
  })
);

function post(message) {
  window.webkit?.messageHandlers?.diffRenderer?.postMessage(message);
}

function createElement(tagName, className, text) {
  const element = document.createElement(tagName);
  if (className) element.className = className;
  if (text != null) element.textContent = text;
  return element;
}

function normalizePath(path) {
  return path
    .trim()
    .replace(/^"|"$/g, "")
    .replace(/^[ab]\//, "");
}

function languageForPath(path) {
  const fileName = path.split("/").pop()?.toLowerCase() ?? "";
  if (languageByFilename.has(fileName)) return languageByFilename.get(fileName);

  const parts = fileName.split(".");
  if (parts.length < 2) return null;
  const extension = parts.at(-1);
  return languageByExtension.get(extension) ?? null;
}

function parseDiffHeader(line) {
  const match = line.match(/^diff --git (?:"a\/(.+?)"|a\/(\S+)) (?:"b\/(.+?)"|b\/(\S+))$/);
  if (!match) return { oldPath: null, newPath: null };
  return {
    oldPath: normalizePath(match[1] ?? match[2] ?? ""),
    newPath: normalizePath(match[3] ?? match[4] ?? ""),
  };
}

function splitPatch(patch) {
  const lines = patch.replace(/\r\n/g, "\n").split("\n");
  const chunks = [];
  let current = [];

  for (const line of lines) {
    if (line.startsWith("diff --git ") && current.length > 0) {
      chunks.push(current);
      current = [line];
    } else {
      current.push(line);
    }
  }
  if (current.some((line) => line.trim() !== "")) chunks.push(current);
  return chunks;
}

function parseHunkHeader(line) {
  const match = line.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$/);
  if (!match) return null;
  const oldCount = Number(match[2] ?? "1");
  const newCount = Number(match[4] ?? "1");
  return {
    oldLine: Number(match[1]),
    oldCount,
    newLine: Number(match[3]),
    newCount,
    label: line,
    context: match[5]?.trim() ?? "",
  };
}

function lineRangeText(startLine, count) {
  if (count <= 0) return `line ${startLine}`;
  if (count === 1) return `line ${startLine}`;
  return `lines ${startLine}-${startLine + count - 1}`;
}

function lineCountText(count) {
  if (count <= 1) return "1 line";
  return `${count} lines`;
}

function hunkTitle(hunk) {
  if (hunk.context) return hunk.context;

  if (hunk.oldCount === 0 && hunk.newCount > 0) {
    if (hunk.oldLine === 0 || hunk.newLine <= 1) return `Added ${lineCountText(hunk.newCount)} at file start`;
    return `Added ${lineCountText(hunk.newCount)} at line ${hunk.newLine}`;
  }

  if (hunk.newCount === 0 && hunk.oldCount > 0) {
    return `Removed ${lineCountText(hunk.oldCount)} at line ${hunk.oldLine}`;
  }

  return `Edited around line ${hunk.newLine}`;
}

function hunkSubtitle(hunk) {
  if (hunk.context) return null;
  return null;
}

function hiddenLineTitle(count) {
  return `Show ${count} hidden line${count === 1 ? "" : "s"}`;
}

function parseFileChunk(lines, fileIndex) {
  const firstHeader = parseDiffHeader(lines.find((line) => line.startsWith("diff --git ")) ?? "");
  let oldPath = firstHeader.oldPath;
  let newPath = firstHeader.newPath;
  let status = "modified";
  let additions = 0;
  let deletions = 0;
  let isBinary = false;
  let oldLine = 0;
  let newLine = 0;
  let hunkIndex = 0;
  let currentHunkId = null;
  let previousHunkNewEnd = 0;
  const rows = [];
  const metadata = [];

  for (const line of lines) {
    if (line.startsWith("--- ")) {
      const value = normalizePath(line.slice(4));
      if (value !== "/dev/null") oldPath = value;
      continue;
    }
    if (line.startsWith("+++ ")) {
      const value = normalizePath(line.slice(4));
      if (value !== "/dev/null") newPath = value;
      continue;
    }
    if (line.startsWith("new file")) {
      status = "added";
      metadata.push(line);
      continue;
    }
    if (
      line.startsWith("Binary files ") ||
      line.startsWith("GIT binary patch") ||
      line.startsWith("literal ") ||
      line.startsWith("delta ")
    ) {
      isBinary = true;
      metadata.push(line);
      continue;
    }
    if (line.startsWith("deleted file")) {
      status = "deleted";
      metadata.push(line);
      continue;
    }
    if (line.startsWith("rename from ")) {
      status = "renamed";
      oldPath = normalizePath(line.slice("rename from ".length));
      metadata.push(line);
      continue;
    }
    if (line.startsWith("rename to ")) {
      status = "renamed";
      newPath = normalizePath(line.slice("rename to ".length));
      metadata.push(line);
      continue;
    }
    if (
      line.startsWith("index ") ||
      line.startsWith("similarity index ") ||
      line.startsWith("dissimilarity index ") ||
      line.startsWith("old mode ") ||
      line.startsWith("new mode ")
    ) {
      metadata.push(line);
      continue;
    }

    const hunk = parseHunkHeader(line);
    if (hunk) {
      const hiddenStartLine = previousHunkNewEnd === 0 ? 1 : previousHunkNewEnd;
      const hiddenEndLine = hunk.newLine - 1;
      const hiddenLineCount = Math.max(0, hiddenEndLine - hiddenStartLine + 1);
      oldLine = hunk.oldLine;
      newLine = hunk.newLine;
      currentHunkId = `file-${fileIndex}-hunk-${hunkIndex++}`;
      previousHunkNewEnd = hunk.newLine + Math.max(0, hunk.newCount);
      if (hiddenLineCount > 0) {
        rows.push({
          type: "hunk",
          title: hiddenLineTitle(hiddenLineCount),
          subtitle: hunkSubtitle(hunk) ?? hunkTitle(hunk),
          rawText: hunk.label,
          lineNumber: "",
          hunkId: currentHunkId,
          filePath: null,
          hiddenStartLine,
          hiddenEndLine,
        });
      }
      continue;
    }

    if (line.startsWith("+") && !line.startsWith("+++")) {
      rows.push({ type: "add", text: line.slice(1), lineNumber: newLine++, hunkId: currentHunkId });
      additions += 1;
      continue;
    }

    if (line.startsWith("-") && !line.startsWith("---")) {
      rows.push({ type: "delete", text: line.slice(1), lineNumber: oldLine++, hunkId: currentHunkId });
      deletions += 1;
      continue;
    }

    if (line.startsWith("\\ No newline at end of file")) {
      rows.push({ type: "notice", text: line, lineNumber: "", hunkId: currentHunkId });
      continue;
    }

    if (line.startsWith(" ") || rows.length > 0) {
      const text = line.startsWith(" ") ? line.slice(1) : line;
      rows.push({ type: "context", text, lineNumber: newLine++, hunkId: currentHunkId });
      oldLine += 1;
    }
  }

  const path = newPath || oldPath || "Unknown file";
  let finalRows = rows;
  for (const row of finalRows) {
    if (row.type === "hunk") row.filePath = path;
  }

  return {
    path,
    oldPath,
    newPath,
    status,
    additions,
    deletions,
    isBinary,
    language: languageForPath(path),
    metadata,
    rows: finalRows,
  };
}

function parsePatch(patch) {
  return splitPatch(patch)
    .map((chunk, index) => parseFileChunk(chunk, index))
    .filter((file) => file.rows.length > 0 || file.metadata.length > 0);
}

function createStatus(message) {
  const status = createElement("div", "status");
  status.append(
    createElement("div", "status-icon", "doc.text.magnifyingglass"),
    createElement("div", "status-message", message)
  );
  return status;
}

function errorPayload(error, source) {
  const message = error instanceof Error ? error.message : String(error ?? "Unknown error");
  return {
    type: "error",
    source,
    message,
    stack: error instanceof Error ? error.stack ?? "" : "",
    fileCount: files.length,
    patchLength: lastPatch.length,
  };
}

function renderFailure(error) {
  console.error("Diff renderer failed", error);
  root.replaceChildren(createStatus("Diff renderer failed."));
  post(errorPayload(error, "renderFailure"));
  post({ type: "rendered", fileCount: 0, reviewedCount: 0 });
}

function renderSafely(render) {
  try {
    render();
  } catch (error) {
    renderFailure(error);
  }
}

function normalizeReviewedState(state) {
  if (!state || typeof state !== "object") return {};
  const normalized = {};
  for (const [path, signature] of Object.entries(state)) {
    if (typeof path !== "string" || typeof signature !== "string") continue;
    normalized[normalizePath(path)] = signature;
  }
  return normalized;
}

function createStat(className, value) {
  const stat = createElement("span", `stat ${className}`, value);
  return stat;
}

function createCodeChangeSignature(file) {
  const parts = ["code-v2", `status:${file.status}`];
  for (const row of file.rows) {
    if (row.type === "add" || row.type === "delete") {
      parts.push(`${row.type}:${row.lineNumber}:${row.text ?? ""}`);
    }
  }
  return parts.join("\n");
}

function legacySignatureToCodeChangeSignature(signature) {
  if (signature.startsWith("code-v2\n")) return signature;
  if (signature.startsWith("code-v1\n")) return signature;

  const parts = ["code-v2"];
  for (const line of signature.split("\n")) {
    if (line.startsWith("status:")) {
      parts.push(line);
      continue;
    }
    if (!line.startsWith("add:") && !line.startsWith("delete:")) continue;
    parts.push(line);
  }
  return parts.join("\n");
}

function isReviewed(file) {
  const signature = reviewedFileSignatures[file.path];
  if (!signature) return false;
  return legacySignatureToCodeChangeSignature(signature) === createCodeChangeSignature(file);
}

function markFileReviewed(file) {
  reviewedFileSignatures[file.path] = createCodeChangeSignature(file);
}

function postReviewedStateChanged() {
  post({
    type: "reviewedStateChanged",
    reviewedFileSignatures,
    reviewedCount: Object.keys(reviewedFileSignatures).length,
    fileCount: files.length,
  });
}

function normalizeCollapsedState(state) {
  if (!state || typeof state !== "object") return {};
  const normalized = {};
  for (const [path, collapsed] of Object.entries(state)) {
    if (typeof path !== "string" || typeof collapsed !== "boolean") continue;
    normalized[normalizePath(path)] = collapsed;
  }
  return normalized;
}

function collectCollapsedFileStates() {
  const next = {};
  for (const section of root.querySelectorAll(".file")) {
    const path = section.dataset.path;
    if (!path) continue;
    if (section.classList.contains("collapsed")) next[path] = true;
  }
  return next;
}

function postCollapsedStateChanged() {
  collapsedFileStates = collectCollapsedFileStates();
  post({
    type: "collapsedStateChanged",
    collapsedFileStates,
  });
}

function updateFileDisclosure(section) {
  const collapsed = section.classList.contains("collapsed");
  const header = section.querySelector(".file-header");
  header?.setAttribute("aria-expanded", String(!collapsed));
  const chevron = section.querySelector(".file-chevron");
  if (chevron) chevron.textContent = collapsed ? "▸" : "▾";
}

function setFileCollapsed(section, collapsed, shouldPost = true) {
  if (!section) return;
  section.classList.toggle("collapsed", collapsed);
  updateFileDisclosure(section);
  if (shouldPost) postCollapsedStateChanged();
}

function renderFileHeader(file, initiallyCollapsed) {
  const header = createElement("button", "file-header");
  header.type = "button";
  header.dataset.path = file.path;
  header.setAttribute("aria-expanded", String(!initiallyCollapsed));
  if (isReviewed(file)) header.classList.add("is-reviewed");

  const leading = createElement("span", "file-leading");
  const chevron = createElement("span", "file-chevron", initiallyCollapsed ? "▸" : "▾");
  chevron.setAttribute("aria-hidden", "true");
  if (allowsReviewMarkers) {
    const checkbox = createElement("input", "file-review-toggle");
    checkbox.type = "checkbox";
    checkbox.checked = isReviewed(file);
    checkbox.title = "Mark file as reviewed";
    checkbox.setAttribute("aria-label", `Mark ${file.path} as reviewed`);
    checkbox.addEventListener("click", (event) => {
      event.stopPropagation();
    });
    checkbox.addEventListener("change", (event) => {
      event.stopPropagation();
      const section = header.closest(".file");
      if (checkbox.checked) {
        markFileReviewed(file);
        header.classList.add("is-reviewed");
        setFileCollapsed(section, true);
      } else {
        delete reviewedFileSignatures[file.path];
        header.classList.remove("is-reviewed");
      }
      postReviewedStateChanged();
    });
    leading.append(checkbox);
  }
  leading.append(chevron);
  if (file.status === "added" || file.status === "deleted") {
    const badge = createElement(
      "span",
      `file-status-badge ${file.status}`,
      file.status === "added" ? "ADDED" : "REMOVED"
    );
    badge.title = file.status === "added" ? "Added file" : "Deleted file";
    leading.append(badge);
  }

  const titleWrap = createElement("span", "file-title-wrap");
  const title = createElement("span", "file-title", file.path);
  titleWrap.append(title);
  if (file.status === "renamed" && file.oldPath && file.oldPath !== file.path) {
    titleWrap.append(createElement("span", "file-subtitle", `renamed from ${file.oldPath}`));
  }
  if (file.isBinary) {
    titleWrap.append(createElement("span", "file-badge", "Binary"));
  }

  const stats = createElement("span", "file-stats");
  if (file.isBinary) {
    stats.append(createStat("neutral", "Binary"));
  } else {
    if (file.additions > 0) stats.append(createStat("added", `+${file.additions}`));
    if (file.deletions > 0) stats.append(createStat("deleted", `-${file.deletions}`));
    if (file.additions === 0 && file.deletions === 0) stats.append(createStat("neutral", file.status));
  }

  const moreButton = createElement("button", "file-more-button", "⋯");
  moreButton.type = "button";
  moreButton.title = "More";
  moreButton.setAttribute("aria-label", `More actions for ${file.path}`);
  moreButton.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    const rect = moreButton.getBoundingClientRect();
    post({
      type: "fileActionsMenuRequested",
      filePath: file.path,
      anchorX: rect.left + rect.width / 2,
      anchorY: rect.bottom,
    });
  });

  const trailing = createElement("span", "file-trailing");
  trailing.append(stats, moreButton);

  leading.append(titleWrap);
  header.append(leading, trailing);
  header.addEventListener("click", () => {
    const section = header.closest(".file");
    if (!section) return;
    setFileCollapsed(section, !section.classList.contains("collapsed"));
  });
  return header;
}

function renderRow(row) {
  if (row.type === "hunk") return renderHunkRow(row);

  const line = createElement("div", `diff-row ${row.type}`);
  if (row.hunkId) line.dataset.hunkId = row.hunkId;
  const lineNo = createElement("span", "line-number", row.lineNumber);
  const marker = createElement("span", "marker", row.type === "add" ? "+" : row.type === "delete" ? "-" : "");
  const code = createElement("code", "code", row.text);
  if (row.language && row.type !== "hunk" && row.type !== "notice") {
    code.dataset.language = row.language;
    code.dataset.raw = row.text;
  }
  line.append(lineNo, marker, code);
  return line;
}

function renderHunkRow(row) {
  const line = createElement("div", "diff-row hunk");
  line.tabIndex = 0;
  line.role = "button";
  line.dataset.hunkId = row.hunkId;
  line.dataset.filePath = row.filePath ?? "";
  line.dataset.startLine = String(row.hiddenStartLine ?? 1);
  line.dataset.endLine = String(row.hiddenEndLine ?? row.hiddenStartLine ?? 1);
  line.setAttribute("aria-expanded", "false");
  line.title = row.rawText ?? "";

  const gutter = createElement("span", "hunk-gutter");
  const chevron = createElement("span", "hunk-chevron", "▸");
  gutter.append(chevron);

  const content = createElement("span", "hunk-content");
  content.append(createElement("span", "hunk-title", row.title));
  if (row.subtitle) content.append(createElement("span", "hunk-subtitle", row.subtitle));
  line.append(gutter, content);
  const requestFromPointer = (event) => {
    if (event instanceof MouseEvent && event.button !== 0) return;
    event.preventDefault();
    const hunkId = line.dataset.hunkId;
    if (!hunkId || expandedContextByHunk.has(hunkId) || line.classList.contains("loading")) return;
    line.classList.add("loading");
    post({
      type: "requestHunkContext",
      hunkId,
      filePath: line.dataset.filePath ?? "",
      startLine: Number(line.dataset.startLine ?? "1"),
      endLine: Number(line.dataset.endLine ?? line.dataset.startLine ?? "1"),
    });
  };
  line.addEventListener("click", requestFromPointer);
  return line;
}

function hunkHeaderFromEvent(event) {
  const target = event.target;
  if (!(target instanceof Element)) return null;
  return target.closest(".diff-row.hunk");
}

root.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" && event.key !== " ") return;
  const header = hunkHeaderFromEvent(event);
  if (!header) return;
  event.preventDefault();
  header.click();
});

function showHunkContext(payload) {
  const hunkId = payload?.hunkId;
  if (!hunkId || expandedContextByHunk.has(hunkId)) return;
  const header = root.querySelector(`.diff-row.hunk[data-hunk-id="${CSS.escape(hunkId)}"]`);
  if (!header) return;
  header.classList.remove("loading");
  header.setAttribute("aria-expanded", "true");

  let lineNo = Number(payload?.startLine ?? 1);
  if (!Number.isFinite(lineNo) || lineNo < 1) lineNo = 1;
  const lines = Array.isArray(payload?.lines) ? payload.lines : [];
  const fragment = document.createDocumentFragment();
  const language = languageForPath(header.dataset.filePath ?? "");
  for (const text of lines) {
    const row = createElement("div", "diff-row context reveal");
    const code = createElement("code", "code", String(text ?? ""));
    if (language) {
      code.dataset.language = language;
      code.dataset.raw = String(text ?? "");
    }
    row.append(
      createElement("span", "line-number", String(lineNo++)),
      createElement("span", "marker", "·"),
      code
    );
    fragment.append(row);
  }
  if (lines.length === 0) {
    const row = createElement("div", "diff-row notice reveal");
    row.append(
      createElement("span", "line-number", ""),
      createElement("span", "marker", ""),
      createElement("code", "code", "No additional context available")
    );
    fragment.append(row);
  }
  expandedContextByHunk.add(hunkId);
  header.replaceWith(fragment);
  applySyntaxHighlighting();
}

function renderFile(file) {
  const section = createElement("section", "file");
  section.dataset.path = file.path;
  const initiallyCollapsed = collapsedFileStates[file.path] ?? allCollapsed;
  if (initiallyCollapsed) section.classList.add("collapsed");
  section.append(renderFileHeader(file, initiallyCollapsed));

  const body = createElement("div", "file-body");
  for (const row of file.rows) {
    row.language = file.language;
    body.append(renderRow(row));
  }
  section.append(body);
  return section;
}

function loadHighlightCore() {
  if (!highlightCorePromise) {
    highlightCorePromise = import(/* @vite-ignore */ "https://esm.sh/highlight.js@11.11.1/lib/core").then(
      (module) => module.default
    );
  }
  return highlightCorePromise;
}

function loadLanguage(language) {
  if (loadedLanguages.has(language)) return Promise.resolve();
  if (languagePromises.has(language)) return languagePromises.get(language);

  const promise = Promise.all([
    loadHighlightCore(),
    import(/* @vite-ignore */ `https://esm.sh/highlight.js@11.11.1/lib/languages/${language}`),
  ])
    .then(([hljs, module]) => {
      hljs.registerLanguage(language, module.default);
      loadedLanguages.add(language);
    })
    .catch((error) => {
      console.warn(`Syntax highlighting unavailable for ${language}`, error);
    });

  languagePromises.set(language, promise);
  return promise;
}

function applySyntaxHighlighting() {
  const languages = Array.from(new Set(files.map((file) => file.language).filter(Boolean)));
  if (languages.length === 0) return;

  Promise.all(languages.map(loadLanguage))
    .then(() => loadHighlightCore())
    .then((hljs) => {
      clearSearchHighlights();
      for (const code of root.querySelectorAll("code[data-language]")) {
        const language = code.dataset.language;
        const raw = code.dataset.raw ?? code.textContent ?? "";
        if (!language || !loadedLanguages.has(language)) continue;
        code.innerHTML = hljs.highlight(raw, { language, ignoreIllegals: true }).value;
        code.classList.add("highlighted");
      }
      applySearch(searchQuery, searchMode, activeSearchIndex, false);
    })
    .catch((error) => {
      console.warn("Syntax highlighting unavailable", error);
    });
}

function clearSearchHighlights() {
  for (const mark of Array.from(root.querySelectorAll("mark.diff-search-match"))) {
    mark.replaceWith(document.createTextNode(mark.textContent ?? ""));
  }
  root.normalize();
  searchMatches = [];
  activeSearchIndex = -1;
}

function textNodesIn(element) {
  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      return node.nodeValue ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
    },
  });
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  return nodes;
}

function regexForSearch(query, mode) {
  if (mode !== "regex") return null;
  try {
    return new RegExp(query, "gu");
  } catch {
    return null;
  }
}

function markTextNodeMatches(textNode, query, mode, regex) {
  const text = textNode.nodeValue ?? "";
  if (!query) return [];

  const fragment = document.createDocumentFragment();
  const marks = [];
  let cursor = 0;

  if (mode === "regex") {
    if (!regex) return [];
    for (const match of text.matchAll(regex)) {
      const value = match[0];
      if (!value) continue;
      const index = match.index ?? 0;
      if (index > cursor) {
        fragment.append(document.createTextNode(text.slice(cursor, index)));
      }
      const mark = createElement("mark", "diff-search-match", value);
      fragment.append(mark);
      marks.push(mark);
      cursor = index + value.length;
    }
    if (marks.length === 0) return [];
    if (cursor < text.length) fragment.append(document.createTextNode(text.slice(cursor)));
    textNode.replaceWith(fragment);
    return marks;
  }

  const caseSensitive = mode === "caseSensitive";
  const haystack = caseSensitive ? text : text.toLocaleLowerCase();
  const needle = caseSensitive ? query : query.toLocaleLowerCase();
  if (!needle || !haystack.includes(needle)) return [];

  while (cursor < text.length) {
    const index = haystack.indexOf(needle, cursor);
    if (index === -1) {
      fragment.append(document.createTextNode(text.slice(cursor)));
      break;
    }
    if (index > cursor) {
      fragment.append(document.createTextNode(text.slice(cursor, index)));
    }
    const mark = createElement("mark", "diff-search-match", text.slice(index, index + query.length));
    fragment.append(mark);
    marks.push(mark);
    cursor = index + query.length;
  }
  textNode.replaceWith(fragment);
  return marks;
}

function postSearchState() {
  post({
    type: "searchStateChanged",
    current: activeSearchIndex >= 0 ? activeSearchIndex + 1 : 0,
    total: searchMatches.length,
  });
}

function scrollToActiveSearchMatch() {
  for (const match of searchMatches) match.classList.remove("current");
  const match = searchMatches[activeSearchIndex];
  if (!match) {
    postSearchState();
    return;
  }
  match.classList.add("current");
  const section = match.closest(".file");
  if (section) setFileCollapsed(section, false);
  match.scrollIntoView({ block: "center", inline: "nearest" });
  postSearchState();
}

function applySearch(query, mode = searchMode, preferredIndex = 0, shouldScroll = true) {
  clearSearchHighlights();
  searchQuery = query ?? "";
  searchMode = mode ?? "caseInsensitive";
  const trimmed = searchQuery.trim();
  if (!trimmed) {
    postSearchState();
    return;
  }

  const matches = [];
  const regex = regexForSearch(trimmed, searchMode);
  if (searchMode === "regex" && !regex) {
    postSearchState();
    return;
  }
  for (const code of root.querySelectorAll("code.code")) {
    for (const textNode of textNodesIn(code)) {
      matches.push(...markTextNodeMatches(textNode, trimmed, searchMode, regex));
    }
  }

  searchMatches = matches;
  if (searchMatches.length === 0) {
    activeSearchIndex = -1;
    postSearchState();
    return;
  }
  activeSearchIndex = Math.min(Math.max(preferredIndex, 0), searchMatches.length - 1);
  if (shouldScroll) {
    scrollToActiveSearchMatch();
  } else {
    searchMatches[activeSearchIndex]?.classList.add("current");
    postSearchState();
  }
}

function moveSearchResult(delta) {
  if (!searchQuery.trim() || searchMatches.length === 0) {
    postSearchState();
    return;
  }
  activeSearchIndex = (activeSearchIndex + delta + searchMatches.length) % searchMatches.length;
  scrollToActiveSearchMatch();
}

function clearSearch() {
  searchQuery = "";
  searchMode = "caseInsensitive";
  clearSearchHighlights();
  postSearchState();
}

function renderCurrent() {
  root.replaceChildren();
  currentVisiblePath = null;

  if (!lastPatch.trim()) {
    root.append(createStatus("No files changed"));
    const hadReviewedState = Object.keys(reviewedFileSignatures).length > 0;
    const hadCollapsedState = Object.keys(collapsedFileStates).length > 0;
    reviewedFileSignatures = {};
    collapsedFileStates = {};
    if (hadReviewedState) postReviewedStateChanged();
    if (hadCollapsedState) postCollapsedStateChanged();
    post({ type: "rendered", fileCount: 0, reviewedCount: 0 });
    return;
  }

  files = parsePatch(lastPatch);
  if (files.length === 0) {
    root.append(createStatus("No files changed"));
    const hadReviewedState = Object.keys(reviewedFileSignatures).length > 0;
    const hadCollapsedState = Object.keys(collapsedFileStates).length > 0;
    reviewedFileSignatures = {};
    collapsedFileStates = {};
    if (hadReviewedState) postReviewedStateChanged();
    if (hadCollapsedState) postCollapsedStateChanged();
    post({ type: "rendered", fileCount: 0, reviewedCount: 0 });
    return;
  }

  // If a previously reviewed file's actual added/deleted lines changed, clear
  // review marker and auto-expand it. Context drift and hunk line-number shifts
  // should not reopen reviewed files.
  let reviewedStateDidChange = false;
  let collapsedStateDidChange = false;
  const changedReviewedPaths = [];
  const currentPaths = new Set(files.map((file) => file.path));
  for (const path of Object.keys(reviewedFileSignatures)) {
    if (currentPaths.has(path)) continue;
    delete reviewedFileSignatures[path];
    reviewedStateDidChange = true;
  }
  for (const path of Object.keys(collapsedFileStates)) {
    if (currentPaths.has(path)) continue;
    delete collapsedFileStates[path];
    collapsedStateDidChange = true;
  }
  for (const file of files) {
    const previousSignature = reviewedFileSignatures[file.path];
    if (!previousSignature) continue;
    const previousCodeSignature = legacySignatureToCodeChangeSignature(previousSignature);
    const currentCodeSignature = createCodeChangeSignature(file);
    if (previousCodeSignature !== currentCodeSignature) {
      delete reviewedFileSignatures[file.path];
      if (Object.prototype.hasOwnProperty.call(collapsedFileStates, file.path)) {
        delete collapsedFileStates[file.path];
        collapsedStateDidChange = true;
      }
      reviewedStateDidChange = true;
      changedReviewedPaths.push(file.path);
    } else if (previousSignature !== currentCodeSignature) {
      reviewedFileSignatures[file.path] = currentCodeSignature;
      reviewedStateDidChange = true;
    }
  }

  const fragment = document.createDocumentFragment();
  for (const file of files) fragment.append(renderFile(file));
  root.append(fragment);
  for (const path of changedReviewedPaths) {
    const section = Array.from(root.querySelectorAll(".file")).find((node) => (node.dataset.path ?? "") === path);
    if (!section) continue;
    setFileCollapsed(section, false, false);
  }
  applySyntaxHighlighting();
  applySearch(searchQuery, searchMode, activeSearchIndex, false);
  updateVisibleFile();
  if (reviewedStateDidChange) postReviewedStateChanged();
  if (collapsedStateDidChange) postCollapsedStateChanged();
  post({
    type: "rendered",
    fileCount: files.length,
    reviewedCount: Object.keys(reviewedFileSignatures).length,
  });
}

function applyWrapMode() {
  root.classList.toggle("wrapped", isWrapped);
}

function setAllReviewed(checked) {
  if (checked) {
    const next = {};
    for (const file of files) {
      next[file.path] = createCodeChangeSignature(file);
    }
    reviewedFileSignatures = next;
  } else {
    reviewedFileSignatures = {};
  }
  renderCurrent();
  postReviewedStateChanged();
}

function scrollToFile(path) {
  const normalized = normalizePath(path);
  const target = Array.from(root.querySelectorAll(".file")).find((node) => {
    const value = node.dataset.path ?? "";
    return value === normalized || value.endsWith(`/${normalized}`);
  });
  if (!target) return;
  setFileCollapsed(target, false);
  target.scrollIntoView({ block: "start" });
  updateVisibleFile();
}

function updateVisibleFile() {
  const target = Array.from(root.querySelectorAll(".file")).find((node) => {
    return node.getBoundingClientRect().bottom > 30;
  });
  const path = target?.dataset.path;
  if (path == null || path === currentVisiblePath) return;
  currentVisiblePath = path;
  post({ type: "scrolledToFile", filePath: path });
}

window.addEventListener("scroll", () => {
  if (scrollFrameRequested) return;
  scrollFrameRequested = true;
  window.requestAnimationFrame(() => {
    scrollFrameRequested = false;
    updateVisibleFile();
  });
}, { passive: true });

window.addEventListener("error", (event) => {
  post(errorPayload(event.error ?? event.message, "window.error"));
});

window.addEventListener("unhandledrejection", (event) => {
  post(errorPayload(event.reason, "unhandledrejection"));
});

window.magentDiffRenderer = {
  setDiff(payload) {
    lastPatch = payload.patch ?? "";
    lastThemeType = payload.themeType ?? "system";
    allowsReviewMarkers = payload.allowsReviewMarkers !== false;
    reviewedFileSignatures = normalizeReviewedState(payload.reviewedFileSignatures);
    collapsedFileStates = normalizeCollapsedState(payload.collapsedFileStates);
    document.documentElement.dataset.theme = lastThemeType;
    allCollapsed = false;
    expandedContextByHunk.clear();
    clearSearch();
    renderSafely(renderCurrent);
  },
  setMessage(message) {
    root.replaceChildren(createStatus(message));
    post({ type: "rendered", fileCount: 0 });
  },
  setTheme(themeType) {
    lastThemeType = themeType ?? "system";
    document.documentElement.dataset.theme = lastThemeType;
  },
  setWrapped(wrapped) {
    isWrapped = Boolean(wrapped);
    applyWrapMode();
  },
  setCollapsed(collapsed) {
    allCollapsed = Boolean(collapsed);
    for (const section of root.querySelectorAll(".file")) {
      setFileCollapsed(section, allCollapsed, false);
    }
    postCollapsedStateChanged();
  },
  setAllReviewed,
  showHunkContext,
  scrollToFile,
  setSearch(payload) {
    if (typeof payload === "string") {
      applySearch(payload, searchMode, 0, true);
    } else {
      applySearch(payload?.query ?? "", payload?.mode ?? searchMode, 0, true);
    }
  },
  findNext() {
    moveSearchResult(1);
  },
  findPrevious() {
    moveSearchResult(-1);
  },
  clearSearch
};

window.addEventListener("DOMContentLoaded", () => {
  document.documentElement.dataset.theme = lastThemeType;
  applyWrapMode();
  post({ type: "ready" });
});
