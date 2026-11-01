// Shared page shell: navigation, the built/planned filter, section links, data panels and the step map.
// Project-specific values live in site-config.js. Don't edit this file per project.
const pageErrors = [];
addEventListener('error', e => pageErrors.push(e.message || `failed to load ${e.target?.src || e.target?.href}`), true);

const { name: SITE_NAME, nav: NAV } = window.SITE;
const PLANNED = NAV.find(([group]) => group === 'Planned')?.[1].map(([id]) => id) ?? [];

const current = location.pathname.split('/').pop().replace('.html', '') || 'index';
const flat = NAV.flatMap(([, pages]) => pages);
const at = flat.findIndex(([id]) => id === current);

// Layout
const main = document.createElement('main');
main.append(...document.body.childNodes);
const rail = document.createElement('nav');
rail.className = 'rail';
rail.setAttribute('aria-label', 'Pages');
rail.innerHTML = `<div class="brand"><a href="index.html">${SITE_NAME}</a><button class="menu-btn" type="button">Pages</button></div>
  <div class="links">${NAV.map(([group, pages]) => `<a class="group" href="${pages[0][0]}.html">${group}</a>` + pages.map(([id, title]) =>
    `<a href="${id}.html"${id === current ? ' aria-current="page"' : ''}>${title}</a>`).join('')).join('')}</div>`;
rail.querySelector('.menu-btn').addEventListener('click', () => rail.classList.toggle('open'));
const layout = document.createElement('div');
layout.className = 'layout';
layout.append(rail, main);
document.body.append(layout);

// Previous and next
if (at >= 0) {
  const pager = document.createElement('div');
  pager.className = 'pager';
  const link = (page, label) => page ? `<a href="${page[0]}.html"><span>${label}</span>${page[1]}</a>` : '<i></i>';
  pager.innerHTML = link(flat[at - 1], 'Previous') + link(flat[at + 1], 'Next');
  main.append(pager);
}

// Planned pages say so once at the top
if (PLANNED.includes(current)) {
  main.querySelector('.lede').insertAdjacentHTML('afterend', '<p class="planned-note"><span class="tag design" style="margin-left:0">planned, not built yet</span></p>');
}

// Built / planned filter, only on pages that mix the two
const filtered = [...main.querySelectorAll('.designed, .in-review')];
if (filtered.length && !PLANNED.includes(current)) {
  const bar = document.createElement('div');
  bar.className = 'legend';
  bar.setAttribute('role', 'group');
  bar.setAttribute('aria-label', 'Filter by what is built');
  bar.innerHTML = `<span><span class="swatch sw-solid"></span>built</span>
    <span><span class="swatch sw-dashed"></span>designed</span>
    ${main.querySelector('.in-review') ? '<span><span class="swatch sw-dotted"></span>in progress</span>' : ''}
    <span class="viewbar" style="margin-left:auto">
      <button data-view="all" class="on">Show all</button>
      <button data-view="impl">Built only</button>
      <button data-view="design">Highlight planned</button>
    </span><span id="viewStatus" aria-live="polite"></span>`;
  main.querySelector('.lede').after(bar);
  const buttons = bar.querySelectorAll('button');
  const status = bar.querySelector('#viewStatus');
  const items = filtered.length === 1 ? "1 item on this page that isn't" : `${filtered.length} items on this page that aren't`;
  const setView = view => {
    buttons.forEach(b => b.classList.toggle('on', b.dataset.view === view));
    document.body.classList.toggle('only-impl', view === 'impl');
    document.body.classList.toggle('only-design', view === 'design');
    status.textContent = view === 'impl' ? `Hiding ${items} built yet.`
      : view === 'design' ? `Highlighting ${items} built yet.` : '';
    try { localStorage.setItem('docs-view', view); } catch {}
  };
  buttons.forEach(b => b.addEventListener('click', () => setView(b.dataset.view)));
  try { const saved = localStorage.getItem('docs-view'); if (saved) setView(saved); } catch {}
  const setBar = () => document.documentElement.style.setProperty('--bar', bar.offsetHeight + 'px');
  new ResizeObserver(setBar).observe(bar);
  setBar();
}

// Section IDs: every heading gets an ID and a copy-link icon on hover. Only the icon is interactive.
const slug = text => text.toLowerCase().replace(/&/g, ' and ').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const LINK_ICON = '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" aria-hidden="true"><path d="M6.5 9.5a3 3 0 0 0 4.4.1l2-2a3.1 3.1 0 0 0-4.4-4.4l-1 1"/><path d="M9.5 6.5a3 3 0 0 0-4.4-.1l-2 2a3.1 3.1 0 0 0 4.4 4.4l1-1"/></svg>';
const DONE_ICON = '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m3.5 8.5 3 3 6-7"/></svg>';
const copyText = async text => {
  try { await navigator.clipboard.writeText(text); return; } catch {}
  const area = document.createElement('textarea');
  area.value = text;
  document.body.append(area);
  area.select();
  document.execCommand('copy');
  area.remove();
};
const usedIds = new Set();
const heads = [...main.querySelectorAll('h1, h2, h3, .step .t')].filter(h => !h.closest('details'));
heads.forEach(head => {
  const nodes = [...head.childNodes];
  const end = nodes.findIndex(n => n.matches?.('.tag, a, .mono'));
  const titleNodes = end < 0 ? nodes : nodes.slice(0, end);
  const title = titleNodes.map(n => n.textContent).join('').trim();
  const isPage = head.matches('h1');
  let id = head.id || slug(title);
  for (let n = 2; !isPage && usedIds.has(id); n++) id = `${slug(title)}-${n}`;
  if (!isPage) { usedIds.add(id); head.id = id; }
  const target = isPage ? location.pathname : `#${id}`;
  head.dataset.title = title;
  const copy = document.createElement('a');
  copy.className = 'copy-link';
  copy.href = target;
  copy.title = 'Copy link to this section';
  copy.setAttribute('aria-label', `Copy link to ${title}`);
  copy.innerHTML = LINK_ICON;
  copy.addEventListener('click', async e => {
    e.preventDefault();
    history.replaceState(null, '', target);
    await copyText(location.href);
    copy.innerHTML = DONE_ICON;
    copy.classList.add('copied');
    copy.title = 'Copied';
    setTimeout(() => { copy.innerHTML = LINK_ICON; copy.classList.remove('copied'); copy.title = 'Copy link to this section'; }, 1500);
  });
  head.insertBefore(copy, end < 0 ? null : nodes[end]);
});

// The rail lists the current page's sections and follows the scroll position
const railHeads = heads.filter(h => h.matches('h2, .t'));
const currentLink = rail.querySelector('a[aria-current]');
if (railHeads.length > 1 && currentLink) {
  const subs = document.createElement('div');
  subs.className = 'subs';
  railHeads.forEach(head => {
    const a = document.createElement('a');
    a.href = `#${head.id}`;
    a.textContent = head.dataset.title;
    if (head.closest('.designed')) a.className = 'designed';
    subs.append(a);
  });
  currentLink.after(subs);
  const subLinks = [...subs.children];
  let queued = false;
  const follow = () => {
    queued = false;
    const line = (parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--bar')) || 0) + 90;
    const step = main.querySelector('.step.cur .t');
    const i = step ? railHeads.indexOf(step) : railHeads.findLastIndex(h => h.getClientRects().length && h.getBoundingClientRect().top <= line);
    subLinks.forEach((a, j) => a.classList.toggle('on', i === j));
  };
  addEventListener('scroll', () => { if (!queued) { queued = true; requestAnimationFrame(follow); } }, { passive: true });
  document.addEventListener('stepchange', follow);
  follow();
}

// IDs are added after load, so scroll to a linked section here
const openLinked = () => {
  const target = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
  if (!target) return;
  target.closest('details')?.setAttribute('open', '');
  target.scrollIntoView();
};
openLinked();
addEventListener('hashchange', openLinked);

// Data panels: simulated requests, responses and saved records behind a step or a table row
const esc = text => String(text).replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const json = value => esc(JSON.stringify(value, null, 2)).replace(/("(?:[^"\\]|\\.)*")(: )?/g, (_, str, colon) =>
  colon ? `<span class="k">${str}</span>: ` : `<span class="s">${str}</span>`);
const block = (label, value) => value === undefined ? '' :
  `<div class="ex-label">${label}</div><pre class="json"><code>${json(value)}</code></pre>`;
const dataPanel = exchanges => {
  const panel = document.createElement('div');
  panel.className = 'step-data';
  panel.innerHTML = `<p class="note">Simulated example. The endpoints and field names follow the code, and “…” marks what's been shortened.</p>` +
    exchanges.map((x, i) => `<details class="ex"${x.edge ? ` data-edge="${x.edge}"` : ''}${i === 0 ? ' open' : ''}>
      <summary><span class="ex-route">${esc(x.from)} → ${esc(x.to)}</span><code>${esc(x.call)}</code></summary>
      ${x.note ? `<p class="note">${esc(x.note)}</p>` : ''}
      ${block('Request', x.request)}${block('Response', x.response)}${block('Saved', x.saved)}
      ${x.other ? `<div class="ex-label">Other outcomes</div><ul class="pts note">${x.other.map(o => `<li>${esc(o)}</li>`).join('')}</ul>` : ''}
      <p class="ex-src">${esc(x.source)}</p></details>`).join('');
  return panel;
};
const dataButton = onToggle => {
  const button = document.createElement('button');
  button.className = 'data-btn';
  button.type = 'button';
  button.textContent = 'Data';
  button.setAttribute('aria-expanded', 'false');
  button.addEventListener('click', () => {
    const open = button.getAttribute('aria-expanded') !== 'true';
    button.setAttribute('aria-expanded', String(open));
    onToggle(open);
  });
  return button;
};
main.querySelectorAll('tr[data-flow]').forEach(row => {
  const exchanges = window.FLOWS?.[row.dataset.flow];
  if (!exchanges) { pageErrors.push(`no FLOWS entry for data-flow="${row.dataset.flow}"`); return; }
  const extra = document.createElement('tr');
  extra.className = 'data-row';
  extra.hidden = true;
  const cell = extra.insertCell();
  cell.colSpan = row.cells.length;
  cell.append(dataPanel(exchanges));
  row.after(extra);
  row.cells[0].append(dataButton(open => { extra.hidden = !open; }));
});

// Stacked tables take each cell's label from the header row
main.querySelectorAll('table.stack').forEach(table => {
  const labels = [...table.querySelectorAll('tr:first-child th')].map(th => th.textContent.trim());
  table.querySelectorAll('tr').forEach(row => [...row.cells].forEach((cell, i) => { if (labels[i] && cell.tagName === 'TD') cell.dataset.label = labels[i]; }));
});

// Step map: lights up the systems the current step uses. window.TRACE holds { names, steps, data }.
if (document.querySelector('.trace')) {
  const { names = {}, steps: TRACE = [], data = [] } = window.TRACE ?? {};
  const steps = [...document.querySelectorAll('.trace .step')];
  if (steps.length !== TRACE.length) pageErrors.push(`${steps.length} .step elements but ${TRACE.length} TRACE steps`);
  const cap = document.getElementById('traceCap');
  let last = 0;
  const showStep = i => {
    const t = TRACE[i];
    steps.forEach((step, j) => step.classList.toggle('cur', i === j));
    cap.innerHTML = `<b>Step ${i + 1} of ${TRACE.length}</b>${t.cap}`;
    document.dispatchEvent(new Event('stepchange'));
    const active = new Set(t.nodes);
    document.querySelectorAll('.tn').forEach(n => n.classList.toggle('on', active.has(n.dataset.node)));
    document.querySelectorAll('.te').forEach(e => {
      const [a, b] = e.dataset.edge.split('-');
      const fwd = t.edges.includes(`${a}>${b}`), back = t.edges.includes(`${b}>${a}`);
      e.classList.toggle('on', fwd || back);
      e.classList.toggle('rev', back);
      e.setAttribute('marker-end', fwd ? 'url(#trace-arrow)' : 'none');
      e.setAttribute('marker-start', back ? 'url(#trace-arrow)' : 'none');
    });
  };
  steps.forEach((step, i) => {
    if (!TRACE[i]) return;
    const line = document.createElement('div');
    line.className = 'step-sys';
    line.textContent = TRACE[i].nodes.map(n => names[n]).filter(Boolean).join(' · ');
    step.lastElementChild.append(line);
    step.addEventListener('click', () => { last = i; showStep(i); });
    const exchanges = data[i];
    if (!exchanges) return;
    const panel = dataPanel(exchanges);
    panel.hidden = true;
    panel.addEventListener('click', e => e.stopPropagation());
    panel.querySelectorAll('.ex').forEach(x => {
      const edge = document.querySelector(`.te[data-edge="${x.dataset.edge}"]`);
      x.addEventListener('mouseenter', () => edge?.classList.add('hot'));
      x.addEventListener('mouseleave', () => edge?.classList.remove('hot'));
    });
    line.before(panel);
    step.querySelector('.t').after(dataButton(open => { panel.hidden = !open; }));
  });
  // A link to a step shows that step until the reader starts scrolling
  const linked = steps.findIndex(step => step.querySelector('.t').id === decodeURIComponent(location.hash.slice(1)));
  let pinned = linked >= 0;
  ['wheel', 'touchmove', 'keydown'].forEach(type => addEventListener(type, () => { pinned = false; }, { passive: true }));
  last = Math.max(linked, 0);
  if (TRACE.length) showStep(last);
  // The current step is the one crossing a line 64% down the window
  let queued = false;
  const follow = () => {
    queued = false;
    if (pinned) return;
    const line = innerHeight * 0.64;
    const i = steps.findLastIndex(step => step.getBoundingClientRect().top <= line);
    if (i >= 0 && i !== last && TRACE[i]) { last = i; showStep(i); }
  };
  addEventListener('scroll', () => { if (!queued) { queued = true; requestAnimationFrame(follow); } }, { passive: true });
}

// Layout audit for check.py --render. It runs only when the URL has ?audit.
if (location.search.includes('audit')) addEventListener('load', () => {
  const width = document.documentElement.clientWidth;
  const label = el => el.tagName.toLowerCase() + (el.getAttribute('class') ? '.' + el.getAttribute('class').split(' ')[0] : '');
  const scrolls = el => { for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) if (getComputedStyle(p).overflowX !== 'visible') return true; return false; };
  const wide = [...main.querySelectorAll('*')].filter(el => el.getClientRects().length && el.getBoundingClientRect().right > width + 1 && !scrolls(el) && !el.closest('svg'));
  const inside = (b, x, y) => x >= b.x && x <= b.x + b.width && y >= b.y && y <= b.y + b.height;
  const diagrams = [];
  main.querySelectorAll('svg[viewBox]').forEach(svg => {
    if (!svg.getClientRects().length || svg.closest('.copy-link')) return;
    const view = svg.viewBox.baseVal;
    const scale = svg.getBoundingClientRect().width / view.width;
    const rects = [...svg.querySelectorAll('rect')].map(r => r.getBBox()).filter(b => b.width < view.width * .96 || b.height < view.height * .96);
    const texts = [...svg.querySelectorAll('text')].filter(t => t.textContent.trim());
    const boxes = texts.map(t => t.getBBox());
    texts.forEach((t, i) => {
      const b = boxes[i], words = t.textContent.trim().slice(0, 30);
      if (b.x < view.x - 1 || b.y < view.y - 1 || b.x + b.width > view.x + view.width + 1 || b.y + b.height > view.y + view.height + 1) diagrams.push(`text leaves the diagram: "${words}"`);
      const cx = b.x + b.width / 2, cy = b.y + b.height / 2;
      const home = rects.filter(r => inside(r, cx, cy)).sort((p, q) => p.width * p.height - q.width * q.height)[0];
      if (home && (b.x < home.x - 1 || b.x + b.width > home.x + home.width + 1)) diagrams.push(`text wider than its box: "${words}"`);
      for (let j = i + 1; j < boxes.length; j++) {
        const o = boxes[j], w = Math.min(b.x + b.width, o.x + o.width) - Math.max(b.x, o.x), h = Math.min(b.y + b.height, o.y + o.height) - Math.max(b.y, o.y);
        if (w > 2 && h > 3) diagrams.push(`text overlaps text: "${words}" and "${texts[j].textContent.trim().slice(0, 30)}"`);
      }
      const size = parseFloat(getComputedStyle(t).fontSize) * scale;
      if (size < 8.5) diagrams.push(`text renders at ${size.toFixed(1)}px: "${words}"`);
    });
    svg.querySelectorAll('path, line, polyline').forEach(path => {
      if (path.closest('defs, marker') || path.closest('.tn')) return;
      const length = path.getTotalLength();
      if (!length) return;
      const points = [];
      for (let d = 0; d <= length; d += 4) points.push(path.getPointAtLength(d));
      const start = points[0], end = path.getPointAtLength(length);
      rects.forEach(r => {
        if (inside(r, start.x, start.y) || inside(r, end.x, end.y)) return;
        if (points.some(p => p.x > r.x + 2 && p.x < r.x + r.width - 2 && p.y > r.y + 2 && p.y < r.y + r.height - 2)) diagrams.push(`a line crosses a box at x=${Math.round(r.x)} y=${Math.round(r.y)}`);
      });
      boxes.forEach((b, i) => {
        const hits = points.filter(p => inside(b, p.x, p.y));
        if (hits.length && !(inside(b, start.x, start.y) || inside(b, end.x, end.y))) diagrams.push(`a line crosses text: "${texts[i].textContent.trim().slice(0, 30)}"`);
      });
    });
  });
  const brokenImages = [...document.images].filter(img => img.complete && !img.naturalWidth).map(img => img.getAttribute('src'));
  const report = JSON.stringify({
    width, scrollWidth: document.documentElement.scrollWidth, height: document.documentElement.scrollHeight, wide: [...new Set(wide.map(label))].slice(0, 6),
    errors: pageErrors, brokenImages, diagrams: [...new Set(diagrams)].slice(0, 12),
  });
  if (parent !== window) parent.postMessage(report, '*');
  const meta = document.createElement('meta');
  meta.name = 'docs-audit';
  meta.content = report;
  document.head.append(meta);
});
