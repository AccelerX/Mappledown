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
      if (t.meta.env) return '<div class="math display">' + escapeHtml(t.content) + '</div>\n';
      return '<div class="math display">\\[' + escapeHtml(t.content) + '\\]</div>\n';
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
    MathJax.texReset();
    await MathJax.typesetPromise([el]);
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

  window.Mappledown = {
    render: function (text) { return schedule(text); },
    setLook: function (c) { cfg = Object.assign(cfg, c || {}); applyLook(cfg); },
    // Rendered body and MathJax's own CSS, used to build a self-contained HTML export.
    exportParts: function () {
      var el = document.getElementById('content');
      var mj = document.getElementById('MJX-SVG-styles');
      return { body: el.innerHTML, mathCSS: mj ? mj.textContent : '' };
    },
    setPrintMode: function (on, h1Break) {
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
