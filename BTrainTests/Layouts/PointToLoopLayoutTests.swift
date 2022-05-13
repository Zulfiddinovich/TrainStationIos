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

import XCTest
@testable import BTrain

class PointToLoopLayoutTests: XCTestCase {

    func testAutomaticRoute() throws {
        let layout = LayoutFactory.layoutFromBundle(named: "Point to Loop")
        
        let train = layout.trains[0]
        let blockA = layout.block(named: "A")
        
        try layout.setTrainToBlock(train.id, blockA.id, position: .end, direction: .next)
        XCTAssertEqual(train.speed.requestedKph, 0)

        layout.automaticRouteRandom = false
                
        // Verify the a path can be found starting in block "A"
        let pf = LayoutPathFinder(layout: layout, train: train, settings: .init(reservedBlockBehavior: .avoidReserved, baseSettings: .init(verbose: true, random: false, overflow: 30)))
        let path = pf.path(graph: layout, from: .starting(blockA, Block.nextSocket), to: nil, constraints: pf.constraints)!
        XCTAssertEqual(path.toStrings, ["A:1", "0:T1:1", "0:B:1", "0:C:1", "0:D:1", "2:T1:0", "1:A"])
        
        let unresolvedPath: [UnresolvedGraphPathElement] = path.elements.map { $0 }
        let resolved = pf.resolve(graph: layout, unresolvedPath, constraints: pf.constraints, context: pf.context)!
        XCTAssertEqual(resolved.toStrings, ["A:1", "0:T1:1", "0:B:1", "0:C:1", "0:D:1", "2:T1:0", "1:A"])
    }

}