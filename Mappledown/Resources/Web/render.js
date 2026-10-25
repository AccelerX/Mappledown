/*
 * Mappledown renderer: Markdown (markdown-it) + LaTeX math (MathJax 3, SVG output).
 *
 * The app sets window.MAPPLEDOWN_CONFIG before this file loads, then calls
 * Mappledown.render(markdownText). Changing a math setting reloads the page,
 * because MathJax reads its configuration only once at startup.
 */
(function () {
  'use strict';

  var defaults = {
    dollar: true,        // $ ... $
    paren: true,         // \( ... \)
    ddollar: true,       // $$ ... $$
    bracket: true,       // \[ ... \]
    tags: 'ams',         // equation numbers: none | ams | all
    macros: '',          // global \newcommand lines, loaded before every document
    showErrors: true,
    highlightCode: true,
    dark: false,
    serif: false,
    fontSize: 17
  };
  var cfg = Object.assign({}, defaults, window.MAPPLEDOWN_CONFIG || {});

  // ---------- MathJax configuration (read once when tex-svg-full.js loads) ----------
  window.MathJax = {
    tex: {
      // Only text inside our own .math elements is ever typeset, so these
      // delimiters are what the Markdown plugin below writes, not what users type.
      inlineMath: [['\\(', '\\)']],
      displayMath: [['\\[', '\\]']],
      processEscapes: false,
      processEnvironments: true,
      processRefs: true,
      tags: cfg.tags,
    },
    svg: { fontCache: 'local', displayAlign: 'center' },
    options: {
      ignoreHtmlClass: 'tex2jax_ignore',
      processHtmlClass: 'math',
      enableMenu: false,
      enableAssistiveMml: false
    },
    startup: { typeset: false }
  };

  // ---------- Markdown math plugin ----------
  var MATH_ENVS = [
    'equation', 'equation*', 'align', 'align*', 'alignat', 'alignat*', 'aligned',
    'gather', 'gather*', 'gathered', 'multline', 'multline*', 'flalign', 'flalign*',
    'eqnarray', 'eqnarray*', 'split', 'CD', 'math', 'displaymath'
  ];

  function escapeHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function isEscaped(src, pos) {
    var n = 0;
    while (pos - 1 - n >= 0 && src.charCodeAt(pos - 1 - n) === 0x5C) n++;
    return n % 2 === 1;
  }

  function isSpace(c) { return c === 0x20 || c === 0x09 || c === 0x0A || c === 0x0D; }

  // Finds `close` at or after `start`, skipping backslash-escaped copies.
  function findClose(src, close, start, max) {
    var i = start;
    while (i < max) {
      var j = src.indexOf(close, i);
      if (j < 0 || j >= max) return -1;
      if (!isEscaped(src, j)) return j;
      i = j + 1;
    }
    return -1;
  }

  function mathInline(state, silent) {
    var src = state.src, pos = state.pos, max = state.posMax;
    var c = src.charCodeAt(pos);
    var open, close, display, start, end;

    if (c === 0x5C /* \ */) {
      var n = src.charCodeAt(pos + 1);
      if (n === 0x28 /* ( */ && cfg.paren) { open = '\\('; close = '\\)'; display = false; }
      else if (n === 0x5B /* [ */ && cfg.bracket) { open = '\\['; close = '\\]'; display = true; }
      else return false;
      start = pos + 2;
      end = src.indexOf(close, start);
      if (end < 0 || end + 2 > max) return false;
    } else if (c === 0x24 /* $ */) {
      if (src.charCodeAt(pos + 1) === 0x24) {
        if (!cfg.ddollar) return false;
        open = '$$'; close = '$$'; display = true;
        start = pos + 2;
        end = findClose(src, '$$', start, max);
        if (end < 0) return false;
      } else {
        if (!cfg.dollar) return false;
        open = '$'; close = '$'; display = false;
        start = pos + 1;
        if (start >= max || isSpace(src.charCodeAt(start))) return false;
        end = start;
        for (;;) {
          end = findClose(src, '$', end, max);
          if (end < 0) return false;
          // Pandoc rule: no space before the closing $, and no digit right after it ($5 and $6).
          if (!isSpace(src.charCodeAt(end - 1))) {
            var after = src.charCodeAt(end + 1);
            if (!(after >= 0x30 && after <= 0x39)) break;
          }
          end++;
        }
      }
    } else {
      return false;
    }

    if (end === start) return false;
    if (!silent) {
      var token = state.push('math_inline', 'math', 0);
      token.content = src.slice(start, end);
      token.meta = { display: display };
      token.markup = open;
    }
    state.pos = end + close.length;
    return true;
  }

  function mathBlock(state, startLine, endLine, silent) {
    var pos = state.bMarks[startLine] + state.tShift[startLine];
    var max = state.eMarks[startLine];
    if (state.sCount[startLine] - state.blkIndent >= 4) return false;
    var first = state.src.slice(pos, max);
    var open, close, isEnv = false, envName = null;

    if (first.indexOf('$$') === 0 && cfg.ddollar) { open = '$$'; close = '$$'; }
    else if (first.indexOf('\\[') === 0 && cfg.bracket) { open = '\\['; close = '\\]'; }
    else {
      var m = /^\\begin\{([A-Za-z]+\*?)\}/.exec(first);
      if (!m || MATH_ENVS.indexOf(m[1]) < 0) return false;
      isEnv = true; envName = m[1];
      open = m[0]; close = '\\end{' + envName + '}';
    }

    var line = startLine, content, found = false, tail;

    if (isEnv) {
      // Collect lines until the matching \end{env}, allowing the same env nested inside.
      var depth = 0, buf = [];
      for (line = startLine; line < endLine; line++) {
        var ls = state.bMarks[line] + state.tShift[line];
        var lt = state.src.slice(ls, state.eMarks[line]);
        if (line > startLine && lt.trim() === '' ) { /* blank lines are allowed inside */ }
        buf.push(lt);
        var re = /\\(begin|end)\{([A-Za-z]+\*?)\}/g, mm;
        while ((mm = re.exec(lt))) {
          if (mm[2] !== envName) continue;
          depth += mm[1] === 'begin' ? 1 : -1;
          if (depth === 0) { found = true; tail = lt.slice(mm.index + mm[0].length); break; }
        }
        if (found) break;
      }
      if (!found) return false;
      if (tail && tail.trim() !== '') return false;
      content = buf.join('\n');
    } else {
      var rest = first.slice(open.length);
      var closeAt = rest.indexOf(close);
      if (closeAt >= 0) {
        // One-line block: $$ x^2 $$
        if (rest.slice(closeAt + close.length).trim() !== '') return false;
        content = rest.slice(0, closeAt);
        found = true;
      } else {
        var lines = [rest];
        for (line = startLine + 1; line < endLine; line++) {
          var s = state.bMarks[line] + state.tShift[line];
          var t = state.src.slice(s, state.eMarks[line]);
          var at = t.indexOf(close);
          if (at >= 0 && !isEscaped(t, at)) {
            if (t.slice(at + close.length).trim() !== '') return false;
            lines.push(t.slice(0, at));
            found = true;
            break;
          }
          lines.push(t);
        }
        if (!found) return false;
        content = lines.join('\n');
      }
    }

    if (silent) return true;
    state.line = line + 1;
    var token = state.push('math_block', 'math', 0);
    token.block = true;
    token.content = content;
    token.meta = { env: isEnv };
    token.markup = open;
    token.map = [startLine, state.line];
    return true;
  }

  function mathPlugin(md) {
    md.inline.ruler.before('escape', 'math_inline', mathInline);
    md.block.ruler.before('fence', 'math_block', mathBlock, {
      alt: ['paragraph', 'reference', 'blockquote', 'list']
    });
    md.renderer.rules.math_inline = function (tokens, idx) {
      var t = tokens[idx];
      if (t.meta.display) return '<span class="math display">\\[' + escapeHtml(t.content) + '\\]</span>';
      return '<span class="math inline">\\(' + escapeHtml(t.content) + '\\)</span>';
    };
    md.renderer.rules.math_block = function (tokens, idx) {
      var t = tokens[idx];
      var line = t.map ? ' data-line="' + (t.map[0] + 1) + '"' : '';
      if (t.meta.env) return '<div class="math display"' + line + '>' + escapeHtml(t.content) + '</div>\n';
      return '<div class="math display"' + line + '>\\[' + escapeHtml(t.content) + '\\]</div>\n';
    };
  }

  // ---------- markdown-it setup ----------
  var md = window.markdownit({
    html: true,
    linkify: true,
    typographer: false,
    highlight: function (code, lang) {
      if (!cfg.highlightCode || !window.hljs) return '';
      try {
        if (lang && hljs.getLanguage(lang)) {
          return '<pre><code class="hljs language-' + escapeHtml(lang) + '">' +
            hljs.highlight(code, { language: lang, ignoreIllegals: true }).value + '</code></pre>';
        }
      } catch (e) { /* fall back to plain */ }
      return '';
    }
  });
  md.use(mathPlugin);
  if (window.markdownitFootnote) md.use(window.markdownitFootnote);

  // Tag block elements with their source line, for scrolling the editor and preview together.
  md.core.ruler.push('source_lines', function (state) {
    state.tokens.forEach(function (t) {
      if (t.map && t.nesting !== -1 && t.type !== 'math_block' && t.type !== 'inline') {
        t.attrSet('data-line', String(t.map[0] + 1));
      }
    });
  });
  var defaultFence = md.renderer.rules.fence;
  md.renderer.rules.fence = function (tokens, idx, options, env, slf) {
    var html = defaultFence(tokens, idx, options, env, slf);
    var t = tokens[idx];
    if (t.map && html.indexOf('<pre data-line') !== 0) {
      html = html.replace(/^<pre/, '<pre data-line="' + (t.map[0] + 1) + '"');
    }
    return html;
  };

  // Pictures stored next to the .md file are served by the app through mdasset:// URLs.
  function isRelativeSrc(src) {
    return src && !/^[a-z][a-z0-9+.-]*:/i.test(src) && src.indexOf('//') !== 0 && src.charAt(0) !== '#';
  }
  function assetURL(src) {
    if (src.charAt(0) === '/') return 'mdasset://abs/?p=' + encodeURIComponent(decodeURI(src));
    return 'mdasset://doc/?p=' + encodeURIComponent(decodeURI(src));
  }
  var defaultImage = md.renderer.rules.image;
  md.renderer.rules.image = function (tokens, idx, options, env, slf) {
    var t = tokens[idx];
    var src = t.attrGet('src');
    if (isRelativeSrc(src)) t.attrSet('src', assetURL(src));
    return defaultImage(tokens, idx, options, env, slf);
  };

  function fixImages(el) {
    el.querySelectorAll('img').forEach(function (img) {
      var src = img.getAttribute('src');
      if (isRelativeSrc(src)) img.setAttribute('src', assetURL(src));
      if ((img.getAttribute('src') || '').indexOf('mdasset:') === 0) {
        img.addEventListener('error', function () {
          var name = decodeURIComponent((img.getAttribute('src').split('p=')[1] || ''));
          var note = document.createElement('span');
          note.className = 'img-missing';
          note.textContent = 'Picture not available: ' + name +
            '. If it is in the same folder, add that folder with Add Folder… so Mappledown can read it.';
          img.replaceWith(note);
        }, { once: true });
      }
    });
  }

  // ---------- Page setup ----------
  function applyLook(c) {
    var root = document.documentElement;
    if (root.classList.contains('print')) {
      document.body && document.body.classList.toggle('hide-errors', !c.showErrors);
      return;
    }
    root.classList.toggle('dark', !!c.dark);
    root.classList.toggle('serif', !!c.serif);
    root.style.setProperty('--size', (c.fontSize || 17) + 'px');
    document.body && document.body.classList.toggle('hide-errors', !c.showErrors);
    var light = document.getElementById('hljs-light');
    var dark = document.getElementById('hljs-dark');
    if (light && dark) { light.disabled = !!c.dark; dark.disabled = !c.dark; }
  }

  function post(name, body) {
    try {
      window.webkit.messageHandlers[name].postMessage(body === undefined ? null : body);
    } catch (e) { /* not inside the app (tests, browser) */ }
  }

  // ---------- Rendering, one at a time, newest text wins ----------
  var busy = false, pending = null, renderCount = 0, chain = Promise.resolve();

  function macrosHtml() {
    var m = (cfg.macros || '').trim();
    if (!m) return '';
    return '<span class="math math-macros" aria-hidden="true">\\(' + escapeHtml(m) + '\\)</span>';
  }

  async function doRender(text) {
    var el = document.getElementById('content');
    await MathJax.startup.promise;
    MathJax.typesetClear([el]);
    el.innerHTML = macrosHtml() + md.render(text || '');
    fixImages(el);
    MathJax.texReset();
    await MathJax.typesetPromise([el]);
    applyToc();
    renderCount++;
    post('rendered', { count: renderCount, errors: el.querySelectorAll('[data-mml-node="merror"]').length });
  }

  // Returns a promise that settles once the newest text has been rendered.
  function schedule(text) {
    pending = String(text);
    if (busy) return chain;
    busy = true;
    chain = (async function () {
      try {
        while (pending !== null) {
          var t = pending;
          pending = null;
          try { await doRender(t); } catch (e) { post('log', 'render failed: ' + e); }
        }
      } finally {
        busy = false;
      }
    })();
    return chain;
  }

  // ---------- Table of contents (PDF export) ----------
  var printOpts = { on: false, h1Break: false, toc: false };

  function applyToc() {
    var el = document.getElementById('content');
    var old = document.getElementById('toc');
    if (old) old.remove();
    if (!printOpts.on || !printOpts.toc) return;
    var heads = el.querySelectorAll('h1, h2, h3');
    if (!heads.length) return;
    var nav = document.createElement('nav');
    nav.id = 'toc';
    nav.className = 'toc';
    var title = document.createElement('div');
    title.className = 'toc-title';
    title.textContent = 'Contents';
    nav.appendChild(title);
    heads.forEach(function (h) {
      var item = document.createElement('div');
      item.className = 'toc-item toc-' + h.tagName.toLowerCase();
      // Keep rendered math in headings: copy the heading's content, not just its text.
      item.innerHTML = h.innerHTML;
      nav.appendChild(item);
    });
    el.insertBefore(nav, el.firstChild);
  }

  // ---------- Scrolling together with the editor ----------
  var ignoreScrollUntil = 0, scrollQueued = false;

  function anchors() {
    var list = [];
    var last = -1;
    document.querySelectorAll('#content [data-line]').forEach(function (e) {
      var line = +e.getAttribute('data-line');
      var top = e.getBoundingClientRect().top + window.scrollY;
      if (line > last) { list.push({ line: line, top: top }); last = line; }
    });
    return list;
  }

  function scrollToLine(line) {
    var a = anchors();
    if (!a.length) return;
    var i = 0;
    while (i + 1 < a.length && a[i + 1].line <= line) i++;
    var cur = a[i], next = a[i + 1];
    var y = cur.top;
    if (line < cur.line) y = cur.top * (line - 1) / Math.max(1, cur.line - 1);
    else if (next) y = cur.top + (line - cur.line) / (next.line - cur.line) * (next.top - cur.top);
    ignoreScrollUntil = Date.now() + 250;
    window.scrollTo(0, Math.max(0, y - 12));
  }

  function lineAtTop() {
    var a = anchors();
    if (!a.length) return 1;
    var y = window.scrollY + 12;
    var i = 0;
    while (i + 1 < a.length && a[i + 1].top <= y) i++;
    var cur = a[i], next = a[i + 1];
    if (y < cur.top) return 1 + (cur.line - 1) * y / Math.max(1, cur.top);
    if (!next) return cur.line;
    return cur.line + (y - cur.top) / Math.max(1, next.top - cur.top) * (next.line - cur.line);
  }

  window.addEventListener('scroll', function () {
    if (Date.now() < ignoreScrollUntil || scrollQueued) return;
    scrollQueued = true;
    requestAnimationFrame(function () {
      scrollQueued = false;
      if (Date.now() >= ignoreScrollUntil) post('scrolled', lineAtTop());
    });
  }, { passive: true });

  window.Mappledown = {
    render: function (text) { return schedule(text); },
    setLook: function (c) { cfg = Object.assign(cfg, c || {}); applyLook(cfg); },
    // Rendered body and MathJax's own CSS, used to build a self-contained HTML export.
    exportParts: function () {
      var el = document.getElementById('content');
      var mj = document.getElementById('MJX-SVG-styles');
      return { body: el.innerHTML, mathCSS: mj ? mj.textContent : '' };
    },
    scrollToLine: scrollToLine,
    setPrintMode: function (on, h1Break, toc) {
      printOpts = { on: !!on, h1Break: !!h1Break, toc: !!toc };
      applyToc();
      var root = document.documentElement;
      root.classList.toggle('print', !!on);
      root.classList.toggle('h1-break', !!on && !!h1Break);
      if (on) {
        root.classList.remove('dark');
        root.style.setProperty('--size', '12.5px');   // print size, about 12.5 pt on paper
        var light = document.getElementById('hljs-light'), dark = document.getElementById('hljs-dark');
        if (light && dark) { light.disabled = false; dark.disabled = true; }
      } else {
        applyLook(cfg);
      }
    },
    isReady: function () { return renderCount > 0; }
  };

  document.addEventListener('DOMContentLoaded', function () {
    applyLook(cfg);
    MathJax.startup.promise.then(function () { post('ready'); });
  });
})();
