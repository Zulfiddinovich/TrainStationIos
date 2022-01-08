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

struct BlockEditView: View {
    
    let layout: Layout
    @ObservedObject var block: Block
    
    var body: some View {
        VStack(alignment: .leading) {
            UndoProvider($block.category) { category in
                Picker("Type", selection: category) {
                    ForEach(Block.Category.allCases, id:\.self) { category in
                        HStack {
                            Text(category.description)
                            BlockShapeView(layout: layout, category: category)
                        }
                    }
                }.pickerStyle(.inline)
            }

            GroupBox("Feedbacks") {
                BlockFeedbackView(layout: layout, block: block)
            }
            
            Spacer()
        }
    }
}

struct BlockEditView_Previews: PreviewProvider {
    
    static let layout = LayoutCCreator().newLayout()
    static var previews: some View {
        BlockEditView(layout: layout, block: layout.block(at: 0))
    }
}
