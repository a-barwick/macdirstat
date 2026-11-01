// The step map and Data panels for scan.html. All values are made up. The field names follow the code.
window.TRACE = {
  names: { app: 'MacDirStatApp', state: 'AppState', scanner: 'DiskScanner', disk: 'Disk', tree: 'FileNode tree', views: 'Views' },
  steps: [
    { cap: 'MacDirStatApp passes the --scan path to AppState.', nodes: ['app', 'state'], edges: ['app>state'] },
    { cap: 'AppState starts a DiskScanner on a background queue.', nodes: ['state', 'scanner'], edges: ['state>scanner'] },
    { cap: 'Workers read directories from disk and add nodes to the tree.', nodes: ['disk', 'scanner', 'tree'], edges: ['disk>scanner', 'scanner>tree'] },
    { cap: 'A timer copies the counters to AppState, and ScanningView shows them.', nodes: ['scanner', 'state', 'views'], edges: ['scanner>state', 'state>views'] },
    { cap: 'The scanner adds up totals and sorts the tree.', nodes: ['scanner', 'tree'], edges: ['scanner>tree'] },
    { cap: 'The scanner hands the finished tree to AppState on the main thread.', nodes: ['scanner', 'state', 'tree'], edges: ['scanner>state', 'state>tree'] },
    { cap: 'The Tree, File Types and The Map read the new tree.', nodes: ['state', 'tree', 'views'], edges: ['state>views', 'tree>views'] },
  ],
  data: [
    [
      { from: 'MacDirStatApp', to: 'AppState', edge: 'app-state', call: 'scan(_:)', source: 'Sources/MacDirStat/MacDirStatApp.swift',
        request: { arguments: ['--scan', '~/Downloads'], url: 'file:///Users/…/Downloads' } },
    ],
    null,
    [
      { from: 'Disk', to: 'DiskScanner', edge: 'disk-scanner', call: 'getattrlistbulk', source: 'Sources/MacDirStat/Model/DiskScanner.swift',
        response: { name: 'trip.mov', objType: 'VREG', linkCount: 2, totalSize: 2147483000, allocSize: 2147483648, fileID: 41872260, mtime: 1790000000 } },
      { from: 'DiskScanner', to: 'FileNode tree', edge: 'scanner-tree', call: 'FileNode', source: 'Sources/MacDirStat/Model/FileNode.swift',
        saved: { name: 'trip.mov', kind: 'file', size: 2147483648, logicalSize: 2147483000, fileCount: 1, modified: 1790000000, fileID: 41872260, extID: 7 } },
    ],
    [
      { from: 'DiskScanner', to: 'AppState', edge: 'state-scanner', call: 'snapshot', source: 'Sources/MacDirStat/Model/DiskScanner.swift',
        response: { files: 9120, dirs: 811, bytes: 21474836480, unreadable: 0, currentPath: '/Users/…/Downloads/Movies' } },
    ],
    null,
    [
      { from: 'DiskScanner', to: 'AppState', edge: 'state-scanner', call: 'finishScan', source: 'Sources/MacDirStat/AppState.swift',
        request: {
          result: 'FileNode named /Users/…/Downloads',
          links: [{ fileID: 41872260, allocSize: 2147483648, node: 'FileNode named trip.mov' }, { fileID: 41872260, allocSize: 2147483648, node: 'FileNode named trip.mov' }],
          stats: [{ id: 7, name: 'mov', bytes: 2147483648, count: 2 }, '…'],
          duration: 1.4,
        } },
    ],
    null,
  ],
};
