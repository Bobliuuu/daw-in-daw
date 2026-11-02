import CoreGraphics
let b = CGDisplayBounds(CGMainDisplayID())
print(Int(b.origin.x), Int(b.origin.y), Int(b.size.width), Int(b.size.height))
var n: UInt32 = 0
CGGetActiveDisplayList(0, nil, &n)
print("displays", n)
print("trusted:", CGPreflightPostEventAccess())
