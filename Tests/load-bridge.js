// Match Scripts.bridge composition while keeping the fixture runnable in Safari.
window.__bridgeReady = (async () => {
  const sources = await Promise.all(['bridge', 'draft'].map(async (name) => {
    const response = await fetch('../PadCore/Sources/PadCore/Scripts/' + name + '.js');
    if (!response.ok) throw new Error('Cannot load ' + name);
    return response.text();
  }));
  window.__draftCall = sources[1] + '\nreturn safienceHasDraft(handsOff);';
  const script = document.createElement('script');
  script.textContent = sources[0].replace('/*DRAFT_PROBE*/', sources[1]);
  document.head.appendChild(script);
  script.remove();
})();
