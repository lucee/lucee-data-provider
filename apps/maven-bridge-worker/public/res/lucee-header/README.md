# Shared Lucee header (vendored)

These files are a copy of the shared site header of the Lucee hub site (lucee.org, `shared/`).
The hub is the canonical source. To update, copy `header.js`, `header.css`, `theme.css` and
`lucee-logo.svg` from the hub's `shared/` directory byte-for-byte.

The header is a web component, used as `<lucee-header home="https://lucee.org/" current="...">`.
`header.js` loads the files from its own directory, so this copy works without the hub being reachable.
Colour theme follows the system preference only (no per-site toggle).
