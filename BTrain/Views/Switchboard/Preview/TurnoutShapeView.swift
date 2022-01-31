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

struct TurnoutShapeView: View {
    
    let layout: Layout
    let category: Turnout.Category
    let shapeContext = ShapeContext()

    let viewSize = CGSize(width: 104, height: 34)
    
    var turnout: Turnout {
        Turnout("", type: category, address: .init(0, .DCC), state: .straight, center: .init(x: viewSize.width/2, y: viewSize.height/2), rotationAngle: 0)
    }
    
    var shape: TurnoutShape {
        let shape = TurnoutShape(layout: layout, turnout: turnout, shapeContext: shapeContext)
        return shape
    }
    
    var body: some View {
        Canvas { context, size in
            context.withCGContext { context in
                shape.draw(ctx: context)
            }
        }.frame(width: viewSize.width, height: viewSize.height)
    }
    
}


struct TurnoutShapeView_Previews: PreviewProvider {
    
    static let layout = LayoutACreator().newLayout()
    
    static var previews: some View {
        ForEach(Turnout.Category.allCases, id:\.self) { category in
            TurnoutShapeView(layout: layout, category: category)
        }
    }
}
