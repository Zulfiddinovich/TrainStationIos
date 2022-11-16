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

struct LocomotiveEditingView: View {
    
    @ObservedObject var document: LayoutDocument
    @ObservedObject var layout: Layout

    @State private var discoverLocomotiveConfirmation = false
    
    var body: some View {
        LayoutElementsEditingView(layout: layout, new: {
            layout.newLocomotive()
        }, delete: { loc in
            document.layout.locomotives.remove(loc.id)
        },sort: {
            layout.locomotives.elements.sort {
                $0.name < $1.name
            }
        }, elementContainer: $layout.locomotives, row: { loc in
            HStack {
                Toggle("Enabled", isOn: loc.enabled)
                if let image = document.locomotiveIconManager.icon(for: loc.id) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 25)
                }
                TextField("Name", text: loc.name)
            }.labelsHidden()
        }) { loc in
            ScrollView {
                LocomotiveDetailsView(document: document, loc: loc)
                    .padding()
            }
        }
        // TODO: discover locomotive
//
//        Button("􀈄") {
//            discoverLocomotiveConfirmation.toggle()
//        }
//        .disabled(!document.connected)
//        .help("Download Locomotives")
        .alert("Are you sure you want to change the current list of locomotives with the locomotives definition from the Central Station?", isPresented: $discoverLocomotiveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Download & Merge") {
                document.locomotiveDiscovery.discover(merge: true)
            }
            Button("Download & Replace", role: .destructive) {
                document.locomotiveDiscovery.discover(merge: false)
            }
        }
    }
}

struct LocomotiveEditingView_Previews: PreviewProvider {
    
    static let doc = LayoutDocument(layout: LayoutLoop2().newLayout())
    
    static var previews: some View {
        ConfigurationSheet(title: "Locomotives") {
            LocomotiveEditingView(document: doc, layout: doc.layout)
        }
    }
}
