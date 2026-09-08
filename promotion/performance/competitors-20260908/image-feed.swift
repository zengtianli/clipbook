import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
for i in 1...20 {
 let w=2048,h=2048
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:w*4,bitsPerPixel:32)!
 let ptr=rep.bitmapData!
 for y in 0..<h {for x in 0..<w {let k=(y*w+x)*4;ptr[k]=UInt8((x/8+i*11)%256);ptr[k+1]=UInt8((y/8+i*17)%256);ptr[k+2]=UInt8(((x+y)/16+i*23)%256);ptr[k+3]=255}}
 let data=rep.representation(using:.png,properties:[:])!;try data.write(to:root.appendingPathComponent(String(format:"fixture-%02d.png",i)))
 NSPasteboard.general.clearContents();NSPasteboard.general.setData(data,forType:.png);Thread.sleep(forTimeInterval:1)
}
print("20 generated 2048x2048 PNG fixtures copied")
