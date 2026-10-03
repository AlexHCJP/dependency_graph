/// The page `render` fills: `/*DATA*/null` is replaced by the scan.
///
/// Three views, each its own address so the browser's back works:
/// `#packages` — one node per package; `#package/<name>` — that package's
/// files boxed by folder, with each package it touches as one node;
/// `#files` — every file, boxed by package and folder. The "external
/// libraries" switch adds the pub packages the code imports to the first two.
const htmlTemplate = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dependency graph</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/cytoscape/3.30.2/cytoscape.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/layout-base@2.0.1/layout-base.js"></script>
<script src="https://cdn.jsdelivr.net/npm/cose-base@2.2.0/cose-base.js"></script>
<script src="https://cdn.jsdelivr.net/npm/cytoscape-fcose@2.2.0/cytoscape-fcose.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/d3/7.9.0/d3.min.js"></script>
<style>
  :root {
    --bg: #fafafa; --panel: #fff; --fg: #1d1d1f; --muted: #6e6e73;
    --line: #d2d2d7; --edge: #b0b0b8; --hi: #e8590c; --in: #1971c2;
    --c0: #2f9e44; --c1: #7048e8; --c2: #1c7ed6; --c3: #f08c00; --c4: #0c8599; --c5: #868e96;
    --box: rgba(0,0,0,.035); --cycle: #e03131; --ext: #c2255c;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #161618; --panel: #1f1f22; --fg: #ececf0; --muted: #9a9aa2;
      --line: #34343a; --edge: #55555e; --hi: #ff922b; --in: #4dabf7;
      --c0: #51cf66; --c1: #9775fa; --c2: #4dabf7; --c3: #ffa94d; --c4: #3bc9db; --c5: #adb5bd;
      --box: rgba(255,255,255,.04); --cycle: #ff6b6b; --ext: #f06595;
    }
  }
  * { box-sizing: border-box; }
  body { margin: 0; height: 100vh; display: flex; flex-direction: column;
    background: var(--bg); color: var(--fg);
    font: 14px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  header { display: flex; flex-wrap: wrap; gap: 8px; align-items: center;
    padding: 8px 16px; border-bottom: 1px solid var(--line); background: var(--panel); }
  header h1 { font-size: 15px; margin: 0 8px 0 0; }
  button, input { font: inherit; color: inherit; background: var(--bg);
    border: 1px solid var(--line); border-radius: 6px; padding: 4px 10px; }
  button { cursor: pointer; }
  button.on { border-color: var(--fg); font-weight: 600; }
  input[type=search] { min-width: 260px; flex: 1; max-width: 420px; }
  label { display: flex; gap: 4px; align-items: center; color: var(--muted); }
  #where { color: var(--muted); }
  main { flex: 1; display: flex; min-height: 0; }
  #stage { flex: 1; min-width: 0; position: relative; }
  #cy { position: absolute; inset: 0; }
  #forces { position: absolute; top: 8px; right: 8px; z-index: 1; width: 220px;
    padding: 6px 10px; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); }
  #forces summary { cursor: pointer; font-weight: 600; }
  #forces label { justify-content: space-between; margin: 6px 0; }
  #forces input { width: 120px; padding: 0; }
  aside { width: 340px; overflow: auto; padding: 12px 16px;
    border-left: 1px solid var(--line); background: var(--panel); }
  aside h2 { font-size: 14px; margin: 0 0 4px; word-break: break-all; }
  aside h3 { font-size: 12px; text-transform: uppercase; letter-spacing: .04em;
    color: var(--muted); margin: 16px 0 4px; }
  aside ul { list-style: none; margin: 0; padding: 0; }
  aside li { padding: 2px 0; cursor: pointer; word-break: break-all; }
  aside li:hover { text-decoration: underline; }
  aside .n { color: var(--muted); }
  aside a { color: var(--in); }
  aside summary { cursor: pointer; color: var(--muted); margin-top: 8px; }
  .legend span { display: inline-block; width: 10px; height: 10px;
    border-radius: 50%; margin: 0 4px 0 10px; }
  @media (max-width: 720px) {
    main { flex-direction: column; }
    aside { width: auto; height: 40vh; border-left: 0; border-top: 1px solid var(--line); }
  }
</style>
</head>
<body>
<header>
  <h1>Dependency graph</h1>
  <button data-go="#packages">Packages</button>
  <button data-go="#files">All files</button>
  <span id="where"></span>
  <label><input type="checkbox" id="foreign" checked> neighbour packages</label>
  <label><input type="checkbox" id="ext"> external libraries</label>
  <input type="search" id="q" list="ids" placeholder="File or package…">
  <datalist id="ids"></datalist>
  <label title="Nodes keep pushing and pulling; drag one and its neighbours follow"><input type="checkbox" id="physics" checked> physics</label>
  <button id="fit">Fit</button>
</header>
<main>
  <div id="stage">
    <div id="cy"></div>
    <details id="forces"><summary>Forces</summary>
      <label>Center <input type="range" data-force="center" min="0" max="0.2" step="0.005"></label>
      <label>Repel <input type="range" data-force="repel" min="0" max="3" step="0.05"></label>
      <label>Link force <input type="range" data-force="link" min="0" max="1" step="0.02"></label>
      <label>Link distance <input type="range" data-force="distance" min="0.2" max="3" step="0.05"></label>
      <label>Damping <input type="range" data-force="damping" min="0.05" max="0.9" step="0.01"></label>
      <button id="reset">Reset</button>
    </details>
  </div>
  <aside id="info"></aside>
</main>
<script>
const DATA = /*DATA*/null;

const pkgOf = id => id.slice(0, id.indexOf('/'));
const pathOf = id => id.slice(id.indexOf('/') + 1);
const dirOf = id => { const p = pathOf(id); const i = p.indexOf('/'); return i < 0 ? '' : p.slice(0, i); };
const nameOf = id => id.slice(id.lastIndexOf('/') + 1).replace(/\.dart$/, '');
// A package's group, its colour: the folder it sits in (`apps`, `packages`),
// split by a name prefix two or more packages there share (`feature_*`).
const topOf = p => p.dir === '.' ? p.name : p.dir.split('/')[0];
const prefixOf = p => p.name.includes('_') ? topOf(p) + ' ' + p.name.slice(0, p.name.indexOf('_') + 1) : null;
const prefixes = new Map();
for (const p of DATA.packages) { const x = prefixOf(p); if (x) prefixes.set(x, (prefixes.get(x) || 0) + 1); }
const sharedPrefix = p => prefixes.get(prefixOf(p)) > 1 ? prefixOf(p).split(' ')[1] : null;
const groupOf = p => sharedPrefix(p) ? sharedPrefix(p) + '*' : topOf(p);
const groups = [...new Set(DATA.packages.map(groupOf))];
const PALETTE = 6;
const kindOf = p => 'c' + Math.min(groups.indexOf(groupOf(p)), PALETTE - 1);
const css = v => getComputedStyle(document.documentElement).getPropertyValue(v).trim();

const packages = new Map(DATA.packages.map(p => [p.name, p]));
const lines = new Map(DATA.files.map(f => [f.id, f.lines]));
const out = new Map(), inn = new Map();
for (const f of DATA.files) { out.set(f.id, []); inn.set(f.id, []); }
for (const e of DATA.edges) { out.get(e.from).push(e); inn.get(e.to).push(e); }

// Package → package, counted in directives.
const pkgEdges = new Map();
for (const e of DATA.edges) {
  const a = pkgOf(e.from), b = pkgOf(e.to);
  if (a === b) continue;
  pkgEdges.set(a + '>' + b, (pkgEdges.get(a + '>' + b) || 0) + 1);
}
const pkgOut = name => [...pkgEdges].filter(([k]) => k.startsWith(name + '>')).map(([k, n]) => [k.split('>')[1], n]).sort((x, y) => y[1] - x[1]);
const pkgIn = name => [...pkgEdges].filter(([k]) => k.endsWith('>' + name)).map(([k, n]) => [k.split('>')[0], n]).sort((x, y) => y[1] - x[1]);

// Pub packages from pubspec.lock, and package → library, counted in directives.
const external = new Map(DATA.external.map(x => [x.name, x]));
const extOut = new Map(DATA.files.map(f => [f.id, []]));
const extEdges = new Map();
for (const u of DATA.uses) {
  extOut.get(u.from).push(u.to);
  const k = pkgOf(u.from) + '>' + u.to;
  extEdges.set(k, (extEdges.get(k) || 0) + 1);
}
const extOf = name => [...extEdges].filter(([k]) => k.startsWith(name + '>')).map(([k, n]) => [k.split('>')[1], n]).sort((x, y) => y[1] - x[1]);
const extUsers = lib => [...extEdges].filter(([k]) => k.endsWith('>' + lib)).map(([k, n]) => [k.split('>')[0], n]).sort((x, y) => y[1] - x[1]);
const extOn = () => document.getElementById('ext').checked;

document.getElementById('ids').innerHTML =
  [...packages.keys(), ...external.keys(), ...lines.keys()].map(id => `<option value="${id}">`).join('');

// Above this many edges a graph is drawn the cheap way: straight lines with
// no arrowheads — direction still shows in the colours of a focused node.
const FAST_EDGES = 800;

if (window.cytoscapeFcose) cytoscape.use(cytoscapeFcose);
const cy = cytoscape({
  container: document.getElementById('cy'),
  wheelSensitivity: 0.3,
  minZoom: 0.05,
  // What keeps panning and zooming smooth on a few thousand elements: a
  // bitmap of the graph while it moves, redrawn properly once it stops.
  textureOnViewport: true,
  hideEdgesOnViewport: true,
  hideLabelsOnViewport: true,
  motionBlur: false,
  pixelRatio: 1,
  style: [
    { selector: 'node', style: {
      'label': 'data(label)', 'font-size': 10, 'color': css('--fg'),
      'min-zoomed-font-size': 7,
      'text-valign': 'bottom', 'text-margin-y': 3, 'width': 10, 'height': 10,
      'background-color': 'data(color)', 'text-wrap': 'wrap' } },
    { selector: 'node.pkg', style: {
      'width': 'data(size)', 'height': 'data(size)', 'font-size': 12,
      'text-valign': 'center', 'text-halign': 'center', 'text-margin-y': 0,
      'text-outline-color': css('--bg'), 'text-outline-width': 2 } },
    { selector: ':parent', style: {
      'background-color': css('--fg'), 'background-opacity': 0.04,
      'border-color': 'data(color)', 'border-width': 1, 'border-opacity': 0.6,
      'shape': 'round-rectangle', 'padding': 12, 'font-size': 11,
      'text-valign': 'top', 'text-halign': 'center', 'text-margin-y': -2,
      'color': 'data(color)', 'font-weight': 600 } },
    { selector: ':parent.dir', style: { 'border-style': 'dashed', 'font-weight': 400 } },
    { selector: 'node.ext', style: { 'shape': 'diamond', 'width': 14, 'height': 14 } },
    { selector: 'node.foreign', style: { 'opacity': 0.8, 'shape': 'round-rectangle' } },
    { selector: 'edge', style: {
      'width': 'data(width)', 'line-color': css('--edge'), 'curve-style': 'bezier',
      'target-arrow-shape': 'triangle', 'target-arrow-color': css('--edge'),
      'arrow-scale': 0.6, 'opacity': 0.7 } },
    { selector: 'edge.fast', style: {
      'curve-style': 'haystack', 'haystack-radius': 0, 'target-arrow-shape': 'none',
      'opacity': 0.35 } },
    { selector: 'edge[label]', style: { 'label': 'data(label)', 'font-size': 9,
      'min-zoomed-font-size': 7,
      'color': css('--muted'), 'text-background-color': css('--bg'),
      'text-background-opacity': 1, 'text-background-padding': 1 } },
    { selector: 'edge.export', style: { 'line-style': 'dashed' } },
    { selector: 'edge.part', style: { 'line-style': 'dotted' } },
    { selector: 'edge.cycle', style: { 'line-color': css('--cycle'), 'target-arrow-color': css('--cycle') } },
    { selector: '.faded', style: { 'opacity': 0.08 } },
    { selector: 'node.focus', style: { 'border-width': 3, 'border-color': css('--hi') } },
    { selector: 'edge.outgoing', style: { 'line-color': css('--hi'), 'target-arrow-color': css('--hi'), 'opacity': 1, 'z-index': 9 } },
    { selector: 'edge.incoming', style: { 'line-color': css('--in'), 'target-arrow-color': css('--in'), 'opacity': 1, 'z-index': 9 } },
  ],
});

const color = name => css('--' + kindOf(packages.get(name)));

function pkgNode(name, classes = 'pkg') {
  const p = packages.get(name);
  return { group: 'nodes', classes, data: {
    id: 'p:' + name, label: name.slice((sharedPrefix(p) || '').length) + '\n' + p.files,
    color: color(name), size: 24 + Math.sqrt(p.files) * 7 } };
}

function extNode(lib) {
  return { group: 'nodes', classes: 'ext', data: {
    id: 'x:' + lib, label: lib + '\n' + external.get(lib).version, color: css('--ext') } };
}

function fileNode(id, parent) {
  return { group: 'nodes', classes: 'file',
    data: { id, parent, label: nameOf(id), color: color(pkgOf(id)) } };
}

// One edge per pair of files; an import and an export between the same two
// are still one line on the page.
function fileEdges(ids) {
  const seen = new Set(), els = [];
  for (const e of DATA.edges) {
    if (!ids.has(e.from) || !ids.has(e.to)) continue;
    const id = e.from + '>' + e.to;
    if (seen.has(id)) continue;
    seen.add(id);
    els.push({ group: 'edges', classes: e.kind, data: { id, source: e.from, target: e.to, width: 1 } });
  }
  return els;
}

// Files boxed by package, and by folder inside it.
function boxed(ids, els) {
  const boxes = new Set();
  for (const id of ids) {
    const p = pkgOf(id), g = 'g:' + p, d = 'd:' + p + '/' + dirOf(id);
    if (!boxes.has(g)) {
      boxes.add(g);
      els.push({ group: 'nodes', classes: 'box', data: { id: g, label: p, color: color(p) } });
    }
    if (!boxes.has(d)) {
      boxes.add(d);
      els.push({ group: 'nodes', classes: 'dir', data: { id: d, label: dirOf(id) || 'lib', parent: g, color: color(p) } });
    }
    els.push(fileNode(id, d));
  }
  return els;
}

function packagesView() {
  const els = DATA.packages.map(p => pkgNode(p.name));
  const max = Math.max(1, ...pkgEdges.values());
  for (const [k, n] of pkgEdges) {
    const [a, b] = k.split('>');
    els.push({ group: 'edges', classes: pkgEdges.has(b + '>' + a) ? 'cycle' : '',
      data: { id: k, source: 'p:' + a, target: 'p:' + b, label: String(n), width: 1 + 5 * Math.sqrt(n / max) } });
  }
  if (!extOn()) return els;
  for (const lib of new Set([...extEdges.keys()].map(k => k.split('>')[1]))) els.push(extNode(lib));
  for (const [k, n] of extEdges) {
    const [a, b] = k.split('>');
    els.push({ group: 'edges', data: { id: k, source: 'p:' + a, target: 'x:' + b, label: String(n), width: 1 + 5 * Math.sqrt(n / max) } });
  }
  return els;
}

// The package's own files, boxed by folder; every other package it touches is
// one node, its edges summed — a package everybody imports would otherwise
// bring in most of the workspace file by file.
function packageView(name) {
  const own = DATA.files.map(f => f.id).filter(id => pkgOf(id) === name);
  const els = boxed(own, []).concat(fileEdges(new Set(own)));
  if (extOn()) {
    const libs = new Set();
    for (const id of own) for (const lib of new Set(extOut.get(id))) {
      libs.add(lib);
      els.push({ group: 'edges', data: { id: id + '>x:' + lib, source: id, target: 'x:' + lib, width: 1 } });
    }
    for (const lib of libs) els.push(extNode(lib));
  }
  if (!document.getElementById('foreign').checked) return els;
  const sums = new Map();
  const add = (source, target) => {
    const k = source + '>' + target;
    sums.set(k, (sums.get(k) || 0) + 1);
  };
  for (const id of own) {
    for (const e of out.get(id)) if (pkgOf(e.to) !== name) add(id, 'p:' + pkgOf(e.to));
    for (const e of inn.get(id)) if (pkgOf(e.from) !== name) add('p:' + pkgOf(e.from), id);
  }
  const neighbours = new Set([...sums.keys()].flatMap(k => k.split('>')).filter(n => n.startsWith('p:')));
  for (const n of neighbours) els.push(pkgNode(n.slice(2), 'pkg foreign'));
  for (const [k, n] of sums) {
    const [source, target] = k.split('>');
    els.push({ group: 'edges', data: { id: k, source, target, width: Math.min(4, 1 + Math.log2(n)) } });
  }
  return els;
}

function filesView() {
  return boxed(lines.keys(), []).concat(fileEdges(new Set(lines.keys())));
}

// A layout is the slow part, so each view keeps where its nodes were when it
// was left: going back to a graph puts every node where it was.
const positions = new Map();
let shown = null;
// The packages graph spreads wider than the others, with or without libraries.
const wide = key => key.split('+')[0] === '#packages';

function savePositions() {
  if (!shown) return;
  const p = {};
  cy.nodes().forEach(n => { p[n.id()] = { ...n.position() }; });
  positions.set(shown, p);
}

// Live forces, as in Obsidian: springs on the edges, charge between nodes, a
// pull to the middle. They start from the laid-out positions, cool down, and
// warm up again while a node is dragged, so its neighbours follow. Above this
// many nodes a view keeps still unless the box is ticked again there.
const PHYSICS_NODES = 600;
const FORCES = { center: 0.02, repel: 1, link: 0.15, distance: 1, damping: 0.5 };
const forces = { ...FORCES };
try { Object.assign(forces, JSON.parse(localStorage.getItem('dependency_graph.forces'))); } catch {}
let sim = null, simNodes = new Map();

function stopPhysics() {
  if (sim) sim.stop();
  sim = null;
  simNodes = new Map();
}

function startPhysics() {
  stopPhysics();
  if (!window.d3 || !document.getElementById('physics').checked) return;
  const box = cy.nodes().boundingBox();
  // Boxes follow their files; only the files and package nodes feel forces.
  cy.nodes().not(':parent').forEach(n => {
    const { x, y } = n.position();
    simNodes.set(n.id(), { id: n.id(), x, y, r: n.width() / 2 + 4 });
  });
  const links = cy.edges().map(e => ({ source: e.source().id(), target: e.target().id() }))
    .filter(l => simNodes.has(l.source) && simNodes.has(l.target));
  sim = d3.forceSimulation([...simNodes.values()])
    .alpha(0)
    .force('link', d3.forceLink(links).id(d => d.id))
    .force('charge', d3.forceManyBody())
    .force('x', d3.forceX((box.x1 + box.x2) / 2))
    .force('y', d3.forceY((box.y1 + box.y2) / 2))
    .force('collide', d3.forceCollide(d => d.r))
    .on('tick', () => cy.batch(() => {
      for (const d of simNodes.values()) {
        const n = cy.getElementById(d.id);
        if (!n.grabbed()) n.position({ x: d.x, y: d.y });
      }
    }));
  applyForces();
}

// The sliders, scaled to the view: the packages graph is drawn wider.
function applyForces() {
  if (!sim) return;
  const base = wide(shown) ? 160 : 60;
  sim.velocityDecay(forces.damping);
  sim.force('link').distance(base * forces.distance).strength(forces.link);
  sim.force('charge').strength(-base * 4 * forces.repel).distanceMax(base * 10);
  sim.force('x').strength(forces.center);
  sim.force('y').strength(forces.center);
  sim.alpha(Math.max(sim.alpha(), 0.3)).restart();
}

// A dragged node, or every file in a dragged box, is held where the mouse is.
const held = e => e.target.union(e.target.descendants()).filter(n => simNodes.has(n.id()));
cy.on('grab', 'node', () => { if (sim) sim.alphaTarget(0.3).restart(); });
cy.on('drag', 'node', e => held(e).forEach(n => {
  const d = simNodes.get(n.id());
  d.fx = n.position('x');
  d.fy = n.position('y');
}));
cy.on('free', 'node', e => {
  held(e).forEach(n => { const d = simNodes.get(n.id()); d.fx = d.fy = null; });
  if (sim) sim.alphaTarget(0);
});

const sliders = document.querySelectorAll('[data-force]');
const showForces = () => sliders.forEach(i => { i.value = forces[i.dataset.force]; });
showForces();
sliders.forEach(i => i.oninput = () => {
  forces[i.dataset.force] = +i.value;
  try { localStorage.setItem('dependency_graph.forces', JSON.stringify(forces)); } catch {}
  applyForces();
});
document.getElementById('reset').onclick = () => {
  Object.assign(forces, FORCES);
  try { localStorage.removeItem('dependency_graph.forces'); } catch {}
  showForces();
  applyForces();
};

function layout(key, done) {
  const saved = positions.get(key);
  const size = cy.nodes().length;
  const opts = saved ? { name: 'preset', positions: n => saved[n.id()] }
    : window.cytoscapeFcose ? {
      name: 'fcose', animate: false, randomize: true, packComponents: true,
      quality: 'default', numIter: size > 500 ? 1200 : 2500,
      nodeRepulsion: wide(key) ? 30000 : 4500,
      idealEdgeLength: wide(key) ? 160 : 60,
      nestingFactor: 0.2, gravityCompound: 1.2,
      nodeDimensionsIncludeLabels: size < 500,
    } : { name: 'cose', animate: false };
  const l = cy.layout(opts);
  l.one('layoutstop', done);
  l.run();
}

// --- What the side panel says about a file or a package.

const info = document.getElementById('info');
const li = (id, text) => `<li data-id="${id}">${text}</li>`;

function showFile(id) {
  const outs = [...new Set(out.get(id).map(e => e.to))].sort();
  const ins = [...new Set(inn.get(id).map(e => e.from))].sort();
  const libs = [...new Set(extOut.get(id))].sort();
  info.innerHTML = `<h2>${id}</h2>
    <div class="n">${lines.get(id)} lines · <a href="#package/${pkgOf(id)}">${pkgOf(id)}</a></div>
    <h3 style="color:${css('--hi')}">Imports (${outs.length})</h3>
    <ul>${outs.map(t => li(t, t)).join('')}</ul>
    <h3 style="color:${css('--in')}">Imported by (${ins.length})</h3>
    <ul>${ins.map(t => li(t, t)).join('')}</ul>
    <h3 style="color:${css('--ext')}">External libraries (${libs.length})</h3>
    <ul>${libs.map(t => li(t, `${t} <span class="n">${external.get(t).version}</span>`)).join('')}</ul>`;
}

function showExternal(lib) {
  const x = external.get(lib), users = extUsers(lib);
  info.innerHTML = `<h2>${lib}</h2>
    <div class="n">${x.version} · ${x.source}</div>
    <h3 style="color:${css('--in')}">Imported by (${users.length})</h3>
    <ul>${users.map(([n, c]) => li(n, `${n} <span class="n">${c}</span>`)).join('')}</ul>
    ${users.length ? '' : '<p class="n">No workspace code imports it: it came in as a dependency of another library.</p>'}`;
}

function showPackage(name) {
  const p = packages.get(name), outs = pkgOut(name), ins = pkgIn(name);
  info.innerHTML = `<h2>${name}</h2>
    <div class="n">${p.dir} · ${p.files} files</div>
    <p><a href="#package/${name}">Open the package graph →</a></p>
    <h3 style="color:${css('--hi')}">Depends on (${outs.length})</h3>
    <ul>${outs.map(([n, c]) => li(n, `${n} <span class="n">${c}</span>`)).join('')}</ul>
    <h3 style="color:${css('--in')}">Used by (${ins.length})</h3>
    <ul>${ins.map(([n, c]) => li(n, `${n} <span class="n">${c}</span>`)).join('')}</ul>
    <h3 style="color:${css('--ext')}">External libraries (${extOf(name).length})</h3>
    <ul>${extOf(name).map(([n, c]) => li(n, `${n} <span class="n">${external.get(n).version} · ${c}</span>`)).join('')}</ul>`;
}

function showOverview() {
  const kinds = Object.fromEntries(groups.slice(0, PALETTE).map((g, i) => ['c' + i, i === PALETTE - 1 && groups.length > PALETTE ? 'other' : g]));
  kinds.ext = 'external';
  const used = [...external.keys()].map(lib => [lib, extUsers(lib).length]).filter(([, n]) => n).sort((x, y) => y[1] - x[1] || (x[0] < y[0] ? -1 : 1));
  const rest = [...external.keys()].filter(lib => !extUsers(lib).length).sort();
  const extLi = lib => li(lib, `${lib} <span class="n">${external.get(lib).version}</span>`);
  const cycles = [...pkgEdges.keys()].filter(k => { const [a, b] = k.split('>'); return a < b && pkgEdges.has(b + '>' + a); });
  info.innerHTML = `<h2>${DATA.packages.length} packages · ${DATA.files.length} files · ${DATA.edges.length} edges</h2>
    <div class="legend">${Object.entries(kinds).map(([k, t]) => `<span style="background:${css('--' + k)}"></span>${t}`).join('')}</div>
    <p class="n">Click a node to see its edges: <b style="color:${css('--hi')}">outgoing</b>, <b style="color:${css('--in')}">incoming</b>.
    Double-click a package to open its graph. Dashed — export, dotted — part.</p>
    <h3 style="color:${css('--cycle')}">Packages that depend on each other (${cycles.length})</h3>
    <ul>${cycles.map(k => { const [a, b] = k.split('>'); return li(a, `${a} ⇄ ${b}`); }).join('')}</ul>
    <h3 style="color:${css('--ext')}">External libraries (${external.size} downloaded)</h3>
    <div class="n">Imported by the code (${used.length}), by number of packages:</div>
    <ul>${used.map(([lib, n]) => li(lib, `${lib} <span class="n">${external.get(lib).version} · ${n}</span>`)).join('')}</ul>
    <details><summary>Only as a dependency of another library (${rest.length})</summary>
    <ul>${rest.map(extLi).join('')}</ul></details>`;
}

info.addEventListener('click', e => {
  const id = e.target.closest('li')?.dataset.id;
  if (id) open(id);
});

// --- Selection and navigation.

// The node standing for a file or a package in the graph on screen.
function nodeOf(id) {
  for (const n of packages.has(id) ? ['p:' + id, 'g:' + id] : external.has(id) ? ['x:' + id] : [id]) {
    const node = cy.getElementById(n);
    if (node.nonempty()) return node;
  }
  return cy.collection();
}

function unfocus() {
  cy.batch(() => cy.elements().removeClass('faded focus outgoing incoming'));
}

function focus(n) {
  cy.batch(() => {
    cy.elements().removeClass('faded focus outgoing incoming');
    if (n.empty()) return;
    const near = n.closedNeighborhood();
    cy.elements().not(near.union(near.nodes().ancestors())).addClass('faded');
    n.addClass('focus');
    n.outgoers('edge').addClass('outgoing');
    n.incomers('edge').addClass('incoming');
  });
}

function select(id) {
  if (packages.has(id)) showPackage(id); else if (external.has(id)) showExternal(id); else showFile(id);
  const n = nodeOf(id);
  focus(n);
  if (n.nonempty()) cy.animate({ center: { eles: n }, duration: 200 });
}

// A file or package from the search or the panel: in this graph if it is
// there, in its package's otherwise.
function open(id) {
  if (nodeOf(id).nonempty()) return select(id);
  // A library not on screen: its users are in the packages graph, if any.
  if (external.has(id)) {
    if (!extUsers(id).length) return select(id);
    document.getElementById('ext').checked = true;
    pending = id;
    if ((location.hash || '#packages') === '#packages') route(); else location.hash = '#packages';
    return;
  }
  pending = id;
  location.hash = '#package/' + (packages.has(id) ? id : pkgOf(id));
}

let pending = null;

function route() {
  const view = location.hash || '#packages';
  const name = view.startsWith('#package/') ? decodeURIComponent(view.slice(9)) : null;
  const key = (name ? view + (document.getElementById('foreign').checked ? '+' : '') : view)
    + (extOn() && view !== '#files' ? '+x' : '');
  const where = document.getElementById('where');
  document.querySelectorAll('[data-go]').forEach(b => b.classList.toggle('on', b.dataset.go === view));
  where.textContent = 'laying out…';
  stopPhysics();
  savePositions();
  shown = null;
  // Let the browser paint the message before the layout takes the thread.
  setTimeout(() => {
    const els = name ? packageView(name) : view === '#files' ? filesView() : packagesView();
    const edges = els.filter(e => e.group === 'edges').length;
    if (edges > FAST_EDGES) for (const e of els) if (e.group === 'edges') e.classes = (e.classes || '') + ' fast';
    cy.batch(() => { cy.elements().remove(); cy.add(els); });
    layout(key, () => {
      shown = key;
      cy.fit(undefined, 30);
      if (cy.nodes().length <= PHYSICS_NODES) startPhysics();
      where.textContent = name ? '› ' + name : '';
      if (pending) { select(pending); pending = null; }
      else if (name) showPackage(name);
      else showOverview();
    });
  }, 0);
}

cy.on('tap', 'node', e => {
  const id = e.target.id();
  select(/^[gpx]:/.test(id) ? id.slice(2) : id.startsWith('d:') ? id.slice(2).split('/')[0] : id);
});
cy.on('dbltap', 'node.pkg, node.box', e => {
  location.hash = '#package/' + e.target.id().slice(2);
});
cy.on('tap', e => { if (e.target === cy) unfocus(); });

document.querySelectorAll('[data-go]').forEach(b => b.onclick = () => location.hash = b.dataset.go);
document.getElementById('fit').onclick = () => cy.fit(undefined, 30);
document.getElementById('foreign').onchange = route;
document.getElementById('ext').onchange = route;
document.getElementById('physics').onchange = e => e.target.checked && shown ? startPhysics() : stopPhysics();
document.getElementById('q').addEventListener('change', e => {
  const id = e.target.value.trim();
  if (packages.has(id) || external.has(id) || lines.has(id)) open(id);
});
addEventListener('hashchange', route);
route();
</script>
</body>
</html>
''';
