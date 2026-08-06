import ForNowEditor
import SwiftUI

@main
struct EditorProjectionSpikeApp: App {
  private let fixture = """
    list: Projection integrity

    Review the source-backed checkbox
    Verify checked presentation /x
    // Comment lines are not list items
    # Heading lines are not list items
    #### Four hashes remain an ordinary item
    20 + 22 =

    https://example.com/a/very/long/path/to/source
    https://example.com/a/very/long/path/to/source

    中文输入保持原样 📝
    Café and composed accents stay intact.
    """

  var body: some Scene {
    WindowGroup("Editor Projection Spike") {
      ProjectionEditorView(initialText: fixture)
        .frame(minWidth: 620, minHeight: 500)
    }
    .defaultSize(width: 760, height: 620)
    .windowResizability(.contentMinSize)
  }
}
