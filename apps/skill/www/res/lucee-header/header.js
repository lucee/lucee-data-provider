/* Vendored copy of the shared Lucee site header. Canonical source: the Lucee hub site (lucee.org, shared/). Keep changes in the hub and re-copy these files; do not edit them here. */
/*!
 * <lucee-header> — shared site header for the Lucee web properties.
 *
 * Usage (any site, no framework, no build step):
 *   <script src="https://lucee.org/shared/header.js" defer></script>
 *   <lucee-header home="https://lucee.org/" current="download"></lucee-header>
 *
 * Attributes
 *   home     Hub home URL. The logo always links here and the hub-owned nav
 *            items (Extensions, Community, AI, Support) are resolved against it.
 *            Default: https://lucee.org/
 *   current  Optional nav key to mark as the current section:
 *            download | docs | extensions | community | ai | support
 *
 * The right side has a theme switch (system / light / dark). The choice is stored in
 * localStorage ('lucee-theme') and applied as <html data-theme="light|dark">; no attribute = system.
 * theme.css (loaded automatically) maps that attribute to the shared colour tokens.
 * header.css, theme.css and lucee-logo.svg are loaded from the same directory as this file.
 * Content is rendered in the light DOM, so it is fully styleable and accessible.
 */
(function () {
  'use strict';

  var SRC = document.currentScript && document.currentScript.src;
  var BASE = SRC ? SRC.replace(/[^\/]*([?#].*)?$/, '') : '/shared/';

  // Single place that defines the global navigation.
  // `hub: true` => path is relative to the hub home URL.
  var NAV = [
    { key: 'download',   label: 'Download',   href: 'https://download.lucee.org/' },
    { key: 'docs',       label: 'Docs',       href: 'https://docs.lucee.org/' },
    // re-enable once lucee.org hub is live (2026-11-06)
    // { key: 'extensions', label: 'Extensions', hub: 'extensions.html' },
    // { key: 'community',  label: 'Community',  hub: 'community.html' },
    // { key: 'ai',         label: 'AI',         hub: 'ai.html' },
    { key: 'support',    label: 'Support',    hub: 'support.html' }
  ];

  var THEME_KEY = 'lucee-theme';   // 'light' | 'dark'; absent = follow the system

  function storedTheme() {
    try { var t = localStorage.getItem(THEME_KEY); return t === 'light' || t === 'dark' ? t : 'system'; }
    catch (e) { return 'system'; }
  }
  function setTheme(t) {
    var root = document.documentElement;
    if (t === 'light' || t === 'dark') root.setAttribute('data-theme', t); else root.removeAttribute('data-theme');
    try { if (t === 'system') localStorage.removeItem(THEME_KEY); else localStorage.setItem(THEME_KEY, t); } catch (e) {}
    var all = document.querySelectorAll('lucee-header .lh-theme button');
    for (var i = 0; i < all.length; i++) {
      all[i].setAttribute('aria-pressed', all[i].getAttribute('data-theme-value') === t ? 'true' : 'false');
    }
  }
  // Apply the saved choice as early as possible (pages may also do this inline in <head> to avoid a flash).
  (function () { var t = storedTheme(); if (t !== 'system') document.documentElement.setAttribute('data-theme', t); })();

  var ICONS = {
    system: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/></svg>',
    light:  '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
    dark:   '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>'
  };
  var THEME_LABEL = { system: 'System theme', light: 'Light theme', dark: 'Dark theme' };

  var GITHUB_URL = 'https://github.com/lucee/Lucee';

  // Load the stylesheets once per page (header.css, and theme.css with the shared light/dark tokens).
  [['header.css', 'data-lucee-header-css'], ['theme.css', 'data-lucee-theme-css']].forEach(function (f) {
    if (document.querySelector('link[' + f[1] + ']')) return;
    var link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = BASE + f[0];
    link.setAttribute(f[1], '');
    document.head.appendChild(link);
  });

  var uid = 0;

  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
  }

  class LuceeHeader extends HTMLElement {
    connectedCallback() {
      var id = 'lh' + (++uid);
      var home = this.getAttribute('home') || 'https://lucee.org/';
      if (home.slice(-1) !== '/') home += '/';
      var current = this.getAttribute('current') || '';

      var links = NAV.map(function (n) {
        var href = n.hub ? home + n.hub : n.href;
        var cur = n.key === current ? ' aria-current="page"' : '';
        return '<li><a href="' + esc(href) + '"' + cur + '>' + esc(n.label) + '</a></li>';
      }).join('');

      var cur_t = storedTheme();
      var themeButtons = ['system', 'light', 'dark'].map(function (t) {
        return '<button type="button" data-theme-value="' + t + '" aria-pressed="' + (t === cur_t) + '" title="' + THEME_LABEL[t] +
               '" aria-label="' + THEME_LABEL[t] + '">' + ICONS[t] + '</button>';
      }).join('');

      this.innerHTML =
        '<header class="lh">' +
          '<div class="lh-bar">' +
            '<a class="lh-logo" href="' + esc(home) + '" aria-label="Lucee home">' +
              '<img src="' + esc(BASE) + 'lucee-logo.svg" alt="Lucee" width="172" height="81">' +
            '</a>' +
            '<button class="lh-toggle" type="button" aria-expanded="false" aria-controls="' + id + '-menu" aria-label="Menu">' +
              '<span class="lh-burger" aria-hidden="true"></span>' +
            '</button>' +
            '<div class="lh-menu" id="' + id + '-menu">' +
              '<nav class="lh-nav" aria-label="Main"><ul>' + links + '</ul></nav>' +
              '<div class="lh-tools">' +
                '<div class="lh-theme" role="group" aria-label="Color theme">' + themeButtons + '</div>' +
                '<a class="lh-github" href="' + GITHUB_URL + '" target="_blank" rel="noopener" aria-label="Lucee on GitHub">' +
                  '<svg width="22" height="22" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.6 7.6 0 0 1 4 0c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg>' +
                '</a>' +
              '</div>' +
            '</div>' +
          '</div>' +
        '</header>';

      var root = this.firstChild;
      var btn = this.querySelector('.lh-toggle');
      var set = function (open) {
        root.classList.toggle('lh-open', open);
        btn.setAttribute('aria-expanded', open ? 'true' : 'false');
      };
      btn.addEventListener('click', function () { set(btn.getAttribute('aria-expanded') !== 'true'); });
      this.querySelector('.lh-theme').addEventListener('click', function (e) {
        var b = e.target.closest('button[data-theme-value]');
        if (b) setTheme(b.getAttribute('data-theme-value'));
      });
      this.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && btn.getAttribute('aria-expanded') === 'true') { set(false); btn.focus(); }
      });
    }
  }

  if (!customElements.get('lucee-header')) customElements.define('lucee-header', LuceeHeader);
})();
