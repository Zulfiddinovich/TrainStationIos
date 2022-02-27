// Copyright 2021-22 Jean Bovet
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import SwiftUI

struct SpeedSlider: View {
    
    @ObservedObject var speed: TrainSpeed
        
    var onEditingChanged: (() -> Void)?

    var body: some View {
        HStack {
            CustomSlider(value: $speed.kphAsDouble, secondaryValue: $speed.actualKphAsDouble, range: (0, Double(speed.maxSpeed)), onEditingChanged: onEditingChanged) { modifiers in
                ZStack {
                    Rectangle().foregroundColor(Color(NSColor.windowBackgroundColor)).frame(height: 8).cornerRadius(4)
                    
                    Rectangle()
                        .foregroundColor(.accentColor)
                        .opacity(0.5)
                        .frame(height: 8)
                        .cornerRadius(4)
                        .modifier(modifiers.barLeft)
                    
                    Rectangle()
                        .foregroundColor(.accentColor)
                        .opacity(0.8)
                        .frame(height: 8)
                        .cornerRadius(4)
                        .modifier(modifiers.barLeftSecondary)
                    
                    ZStack {
                        Rectangle().fill(Color.white).cornerRadius(1.5).shadow(radius: 1.2).frame(width: 26, height: 30)
                        VStack {
                            Text(("\(Int(speed.requestedKph))")).font(.system(size: 11)).foregroundColor(.black)
                            Text(("\(Int(speed.actualKph))")).font(.system(size: 11)).foregroundColor(.black)
                        }
                    }
                    .modifier(modifiers.knob)
                }.cornerRadius(3)
            }.frame(height: 34)
            Text("kph")
        }
    }
}

private extension TrainSpeed {
    
    var kphAsDouble: Double {
        get {
            return Double(self.requestedKph)
        }
        set {
            self.requestedKph = UInt16(round(newValue))
        }
    }
    
    var actualKphAsDouble: Double {
        get {
            return Double(self.actualKph)
        }
        set {
            self.actualKph = UInt16(round(newValue))
        }
    }

}

struct SpeedSlider_Previews: PreviewProvider {
    
    static let t1: Train = {
        let t = Train()
        t.speed.requestedKph = 70
        t.speed.actualKph = 30
        return t
    }()
    
    static let t2: Train = {
        let t = Train()
        t.speed.requestedKph = 30
        t.speed.actualKph = 70
        return t
    }()

    static var previews: some View {
        SpeedSlider(speed: t1.speed)
        SpeedSlider(speed: t2.speed)
    }
}
