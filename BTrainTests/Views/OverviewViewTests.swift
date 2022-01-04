// Copyright 2021 Jean Bovet
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
import ViewInspector

extension TrainDropActionSheet: Inspectable { }

class OverviewViewTests: RootViewTests {

    func testMainView() throws {
        let sut = OverviewView(document: doc)
        XCTAssertNoThrow(try sut.inspect().hStack().vStack(0).view(TrainListView.self, 0))
        XCTAssertNoThrow(try sut.inspect().hStack().vStack(0).view(SimulatorView.self, 1))
        XCTAssertNoThrow(try sut.inspect().hStack().view(OverviewSwitchboardView.self, 1))
    }
    
    func testOverviewSwitchboardView() throws {
        let sut = OverviewSwitchboardView(layout: doc.layout, coordinator: doc.coordinator!, document: doc, switchboard: doc.switchboard!, state: doc.switchboard!.state)
        XCTAssertNoThrow(try sut.inspect().vStack().view(SwitchboardEditControlsView.self, 0))
        XCTAssertNoThrow(try sut.inspect().vStack().scrollView(1).view(SwitchBoardView.self))
    }
    
    func testTrainDropActionSheet() throws {
        let info = SwitchBoard.State.TrainDragInfo(trainId: layout.trains[0].id, blockId: layout.blockIds[0], position: 0)
        let sut = TrainDropActionSheet(layout: doc.layout, trainDragInfo: info, coordinator: doc.coordinator!)
        
        _ = try sut.inspect().find(button: "Set Train")
        _ = try sut.inspect().find(button: "Move Train")
        _ = try sut.inspect().find(button: "Cancel")
    }
}
