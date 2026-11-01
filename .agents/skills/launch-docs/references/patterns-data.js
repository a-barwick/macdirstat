// Data for patterns.html. The app is made up. A real site puts this in its own data script, loaded before site.js.
window.SITE = { name: 'Shortly', nav: [['Patterns', [['patterns', 'Patterns']]]] };

window.TRACE = {
  // Display names for the line under each step on narrow screens. Frames are left out.
  names: { browser: 'Browser', api: 'API', postgres: 'Postgres', queue: 'Queue', worker: 'Worker' },
  // One entry per .step: the caption above the map, the nodes to light, and the edges to animate as 'from>to'.
  steps: [
    { cap: 'The API checks the URL and saves a link.', nodes: ['browser', 'api', 'postgres'], edges: ['browser>api', 'api>postgres'] },
    { cap: 'The API queues a preview job and replies.', nodes: ['api', 'queue', 'browser'], edges: ['api>queue', 'api>browser'] },
    { cap: 'The worker takes the job and saves the preview.', nodes: ['queue', 'worker', 'postgres'], edges: ['queue>worker', 'worker>postgres'] },
  ],
  // Optional: what crosses each boundary, one list per step. `edge` highlights that line on hover.
  data: [
    [
      { from: 'Browser', to: 'API', edge: 'browser-api', call: 'POST /links', source: 'src/api/links.ts',
        request: { url: 'https://example.com/spring-sale' }, response: { status: 201, body: { code: 'x7Qp', url: 'https://example.com/spring-sale' } },
        other: ['400 if the URL has no host', '409 if the custom code is taken'] },
      { from: 'API', to: 'Postgres', edge: 'api-postgres', call: 'links', source: 'src/db/links.ts',
        saved: { code: 'x7Qp', url: 'https://example.com/spring-sale', created_at: '2026-03-14T09:30:00Z' } },
    ],
    [
      { from: 'API', to: 'Queue', edge: 'api-queue', call: 'preview', source: 'src/jobs/preview.ts', request: { code: 'x7Qp' },
        note: 'The job carries only the code. The worker reads the URL from Postgres.' },
    ],
  ],
};

window.FLOWS = {
  expire: [{ from: 'Sweeper', to: 'Postgres', call: 'DELETE links', source: 'src/jobs/sweep.ts', request: { older_than: '…' }, response: { deleted: 12 } }],
};
