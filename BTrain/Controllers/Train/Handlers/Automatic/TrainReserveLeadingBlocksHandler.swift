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

import Foundation

final class TrainReserveLeadingBlocksHandler: TrainAutomaticSchedulingHandler {
    
    var events: Set<TrainEvent> {
        [.movedToNextBlock, .movedInsideBlock]
    }
    
    func process(layout: Layout, train: Train, route: Route, event: TrainEvent, controller: TrainControlling) throws -> TrainHandlerResult {
        guard train.stateChangeRequest == nil else {
            return .none()
        }
        
        guard train.state != .stopped else {
            return .none()
        }
        
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none()
        }

        let result = try controller.reserveLeadBlocks(route: route, currentBlock: currentBlock)
        if result == false {
            BTLogger.router.debug("\(train, privacy: .public): requesting to stop temporarily here \(currentBlock, privacy: .public) because the leading blocks cannot be reserved")
            train.stateChangeRequest = .stopTemporarily
            return .one(.stopRequested)
        }

        return .none()
    }
        
}