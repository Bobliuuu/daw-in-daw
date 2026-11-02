// evt.swift : post REAL macOS input events (CGEvent) - used for GUI tests of the inner DAW.
// usage: evt move X Y | click X Y | rclick X Y | dclick X Y | drag X1 Y1 X2 Y2 [steps] | key KEYCODE [cmd|shift|alt]... | type TEXT | scroll DY
import Foundation
import CoreGraphics
func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap); usleep(12000) }
func mouse(_ type: CGEventType, _ x: Double, _ y: Double, _ btn: CGMouseButton = .left, click: Int64 = 1) {
  let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: btn)
  e?.setIntegerValueField(.mouseEventClickState, value: click)
  post(e)
}
let a = CommandLine.arguments
func d(_ i: Int) -> Double { Double(a[i])! }
switch a[1] {
case "move": mouse(.mouseMoved, d(2), d(3))
case "click": mouse(.mouseMoved, d(2), d(3)); mouse(.leftMouseDown, d(2), d(3)); mouse(.leftMouseUp, d(2), d(3))
case "rclick": mouse(.mouseMoved, d(2), d(3)); mouse(.rightMouseDown, d(2), d(3), .right); mouse(.rightMouseUp, d(2), d(3), .right)
case "dclick":
  mouse(.mouseMoved, d(2), d(3))
  mouse(.leftMouseDown, d(2), d(3)); mouse(.leftMouseUp, d(2), d(3))
  mouse(.leftMouseDown, d(2), d(3), click: 2); mouse(.leftMouseUp, d(2), d(3), click: 2)
case "drag":
  let steps = a.count > 6 ? Int(a[6])! : 12
  mouse(.mouseMoved, d(2), d(3)); mouse(.leftMouseDown, d(2), d(3))
  for i in 1...steps { let t = Double(i) / Double(steps); mouse(.leftMouseDragged, d(2) + (d(4) - d(2)) * t, d(3) + (d(5) - d(3)) * t) }
  mouse(.leftMouseUp, d(4), d(5))
case "key":
  let code = CGKeyCode(Int(a[2])!)
  var flags = CGEventFlags()
  for m in a.dropFirst(3) { if m == "cmd" { flags.insert(.maskCommand) }; if m == "shift" { flags.insert(.maskShift) }; if m == "alt" { flags.insert(.maskAlternate) } }
  for down in [true, false] { let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down); e?.flags = flags; post(e) }
case "type":
  for ch in a[2].unicodeScalars {
    let u = [UniChar(ch.value)]
    for down in [true, false] { let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down); e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: u); post(e) }
  }
case "scroll": let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(d(2)), wheel2: 0, wheel3: 0); post(e)
default: print("unknown")
}
