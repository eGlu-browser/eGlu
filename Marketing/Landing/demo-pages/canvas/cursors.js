// The canvas app's own cursors, as SVG pictures at 32 points: black shapes edged in white with a soft
// shadow, as the system draws its own; the hands white edged in black. Each value is a CSS cursor.
(function () {
  const shadow = '<filter id="s" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="0.9" stdDeviation="0.9" flood-opacity="0.38"/></filter>';
  const svg = (body) => `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><defs>${shadow}</defs><g filter="url(#s)">${body}</g></svg>`;
  const url = (s, x, y, fallback) => `url("data:image/svg+xml,${encodeURIComponent(s)}") ${x} ${y}, ${fallback}`;

  const arrowPath = "M9.5 5.5v19.2l4.7-4.6 3.1 7.1 3.3-1.5-3.1-6.9h6.7z";
  const arrow = svg(`<path d="${arrowPath}" fill="#141414" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/>`);

  const badge = '<g transform="translate(22.5 22.5)"><circle r="6.4" fill="#fff"/><circle r="6.4" fill="none" stroke="#141414" stroke-opacity="0.18" stroke-width="0.8"/>'
    + '<path d="M0-4.2v8.4M-4.2 0h8.4" stroke="#141414" stroke-width="1.2" stroke-linecap="round"/>'
    + '<path d="M0-4.9l-1.6 1.9h3.2zM0 4.9l-1.6-1.9h3.2zM-4.9 0l1.9-1.6v3.2zM4.9 0l-1.9-1.6v3.2z" fill="#141414"/></g>';
  const move = svg(`<path d="M7.5 4v17l4.2-4.1 2.8 6.3 2.9-1.3-2.8-6.2h6z" fill="#141414" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/>${badge}`);

  const crossArms = "M16 4.5v8M16 19.5v8M4.5 16h8M19.5 16h8";
  const cross = svg(`<path d="${crossArms}" stroke="#fff" stroke-width="3.6" stroke-linecap="round"/><path d="${crossArms}" stroke="#141414" stroke-width="1.3" stroke-linecap="round"/>`);

  const dbl = "M-11 0L-5.4-5.4V-1.5H5.4V-5.4L11 0L5.4 5.4V1.5H-5.4V5.4Z";
  const resize = svg(`<path transform="translate(16 16) rotate(45)" d="${dbl}" fill="#141414" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/>`);

  // A hand: four fingers and a thumb as rounded strokes over a palm, the whole edged once (drawn
  // black and wider first, then white on top), so the fingers part where they fan out.
  function hand(fingers, thumb) {
    const palm = '<path d="M10.6 17.4c0-1.6 1.2-2.6 2.6-2.6h7.6c1.9 0 3.4 1.5 3.4 3.4v3.6c0 3.6-2.8 6.4-6.4 6.4h-1.6c-2.4 0-4.2-1.3-5.2-3.2z"/>';
    const strokes = (w, colour) => fingers.concat([thumb]).map(([x1, y1, x2, y2, k = 1]) =>
      `<path d="M${x1} ${y1}L${x2} ${y2}" stroke="${colour}" stroke-width="${(w * k).toFixed(2)}" stroke-linecap="round"/>`).join("");
    const outline = `<g fill="#141414" stroke="#141414" stroke-width="2.3" stroke-linejoin="round">${palm}</g>${strokes(3.25 + 2.3, "#141414")}`;
    const fill = `<g fill="#fff">${palm}</g>${strokes(3.25, "#fff")}`;
    return svg(outline + fill);
  }
  const open = hand([[12.6, 17, 11.6, 7.8], [15.7, 16, 15.7, 5.6], [18.8, 16.4, 19.8, 7.1], [21.6, 18.4, 23.4, 11.2, 0.92]], [11.8, 22.8, 7.2, 18.2]);
  const shut = hand([[12.8, 16.6, 12.6, 12.9], [15.8, 15.8, 15.9, 11.9], [18.8, 16, 19.2, 12.3], [21.6, 17.6, 22.2, 14.2, 0.92]], [11.9, 22.4, 9.3, 19.7]);

  window.CANVAS_CURSORS = {
    arrow: url(arrow, 9.5, 5.5, "default"), move: url(move, 7.5, 4, "move"), cross: url(cross, 16, 16, "crosshair"),
    resize: url(resize, 16, 16, "nwse-resize"), hand: url(open, 16, 16, "grab"), grab: url(shut, 16, 16, "grabbing"),
  };
  window.CANVAS_CURSOR_SVGS = { arrow, move, cross, resize, hand: open, grab: shut };
})();
