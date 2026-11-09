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
 * Colour theme follows the system preference (prefers-color-scheme). There is no
 * per-site toggle: localStorage cannot be shared across lucee.org, download.*,
 * skill.* and mcp.* domains. theme.css (loaded automatically) maps the media
 * query to the shared colour tokens.
 * header.css, theme.css and lucee-logo.svg are loaded from the same directory as this file.
 * Content is rendered in the light DOM, so it is fully styleable and accessible.
 */
(function () {
  'use strict';

  var SRC = document.currentScript && document.currentScript.src;
  var BASE = SRC ? SRC.replace(/[^\/]*([?#].*)?$/, '') : '/shared/';
  var ASSET_V = '2';

  // Single place that defines the global navigation.
  // `hub: true` => path is relative to the hub home URL.
  var NAV = [
    { key: 'download',   label: 'Download',   href: 'https://download.lucee.org/' },
    { key: 'docs',       label: 'Docs',       href: 'https://docs.lucee.org/' },
    { key: 'extensions', label: 'Extensions', hub: 'extensions' },
    { key: 'community',  label: 'Community',  hub: 'community' },
    { key: 'ai',         label: 'AI',         hub: 'ai' },
    { key: 'support',    label: 'Support',    hub: 'support' }
  ];

  var GITHUB_URL = 'https://github.com/lucee/Lucee';

  // Load the stylesheets once per page (header.css, and theme.css with the shared light/dark tokens).
  [['header.css', 'data-lucee-header-css'], ['theme.css', 'data-lucee-theme-css']].forEach(function (f) {
    if (document.querySelector('link[' + f[1] + ']')) return;
    var link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = BASE + f[0] + '?v=' + ASSET_V;
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
      this.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && btn.getAttribute('aria-expanded') === 'true') { set(false); btn.focus(); }
      });
    }
  }

  if (!customElements.get('lucee-header')) customElements.define('lucee-header', LuceeHeader);
})();
