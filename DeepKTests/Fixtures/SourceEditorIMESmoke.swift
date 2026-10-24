import AppKit
@main struct IMESmoke {
 @MainActor static func main() {
  let app=NSApplication.shared
  let window=NSWindow(contentRect:NSRect(x:50,y:50,width:300,height:100),styleMask:[.titled],backing:.buffered,defer:false)
  var edits:[(String,Bool)]=[]
  let source=SourceEditor(text:"",onEdit:{edits.append(($0,$1))},onEscape:{})
  let coordinator=source.makeCoordinator()
  let scroll=SourceEditor.makeScrollView(fontSize:13)
  scroll.frame=NSRect(x:0,y:0,width:300,height:100)
  let editor=scroll.documentView as! SourceEditor.Editor
  editor.delegate=coordinator
  window.contentView=scroll
  window.makeFirstResponder(editor)
  editor.setMarkedText("ㅎ",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
  editor.setMarkedText("한",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
  editor.insertText("한",replacementRange:NSRange(location:NSNotFound,length:0))
  print(edits.map { "\($0.0):\($0.1)" }.joined(separator:","))
  guard edits.contains(where:{$0.1}), edits.last?.1==false else { print("IME callback failed"); exit(1) }
  editor.setMarkedText("새",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
  let editCount = edits.count
  coordinator.replaceTextIfNeeded("External copied paragraph", in: editor)
  guard editor.string == "External copied paragraph", !editor.hasMarkedText(), edits.count == editCount else {
   print("External input was lost or old composition was reported as a new edit"); exit(1)
  }
  print("IME marked edits, commit and external replacement passed")
  // U1: composing right after a boundary line keeps the marked text and the rule (dashes hidden); ⌘↩ commits before appending.
  let line=NSRange(location:3,length:3)
  coordinator.show("A\n\n---\n\n",boundaryLines:[line],in:editor)
  editor.setSelectedRange(NSRange(location:8,length:0))
  editor.setMarkedText("ㅎ",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
  coordinator.show(editor.string,boundaryLines:[line],in:editor)
  editor.setMarkedText("한",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
  coordinator.show(editor.string,boundaryLines:[line],in:editor)
  guard editor.hasMarkedText(),editor.markedRange()==NSRange(location:8,length:1),editor.textLayoutManager != nil else {
   print("Composition after a boundary line was lost"); exit(1)
  }
  editor.appendBoundary { $0.hasSuffix("\n\n") ? "---\n\n" : "\n\n---\n\n" }
  guard !editor.hasMarkedText(),editor.string=="A\n\n---\n\n한\n\n---\n\n",edits.last?.1==false else {
   print("⌘↩ did not commit the composition before appending"); exit(1)
  }
  print("Composition after a boundary line and ⌘↩ during composition passed")
  _=app
 }
}
