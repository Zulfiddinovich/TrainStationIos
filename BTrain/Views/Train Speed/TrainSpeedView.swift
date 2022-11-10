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

// TODO: rename LocSpeedView
struct TrainSpeedView: View {
    
    let document: LayoutDocument
    let loc: Locomotive
    
    @ObservedObject var trainSpeed: LocomotiveSpeed

    @State private var selection = Set<LocomotiveSpeed.SpeedTableEntry.ID>()

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                TrainSpeedColumnView(selection: $selection, currentSpeedEntry: .constant(nil), trainSpeed: trainSpeed)
                TrainSpeedGraphView(trainSpeed: trainSpeed)
            }
            
            Divider()

            HStack {
                Spacer()
                Button("OK") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            trainSpeed.updateSpeedStepsTable()
        }
    }
}

struct TrainSpeedView_Previews: PreviewProvider {
        
    static let doc = LayoutDocument(layout: LayoutComplex().newLayout())
    
    static var previews: some View {
        TrainSpeedView(document: doc, loc: Locomotive(), trainSpeed: LocomotiveSpeed(decoderType: .MFX))
    }
}
