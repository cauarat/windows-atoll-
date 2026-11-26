// Stand-in for @tauri-apps/api/webview: nothing is dropped on a web page's island.
export function getCurrentWebview() {
  return {
    onDragDropEvent: async () => () => {},
  };
}
