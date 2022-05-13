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

final class TrainMoveToNextBlockHandler: TrainAutomaticSchedulingHandler {
    
    var events: Set<TrainEvent> {
        [.feedbackTriggered]
    }

    // This method handles the transition from one block to another, using
    // the entry feedback of the next block to determine when a train moves
    // to the next block.
    // When the train moves to another block:
    // - Occupied and leading reservation blocks are updated.
    // - Stop trigger is evaluated depending on the nature of the route
    func process(layout: Layout, train: Train, route: Route, event: TrainEvent, controller: TrainControlling) throws -> TrainHandlerResult {
        guard train.state != .stopped else {
            return .none()
        }
        
        // Find out what is the entry feedback for the next block
        let entryFeedback = try layout.entryFeedback(for: train)
        
        guard let entryFeedback = entryFeedback, entryFeedback.feedback.detected else {
            // The entry feedback is not yet detected, nothing more to do
            return .none()
        }
        
        guard let position = entryFeedback.block.indexOfTrain(forFeedback: entryFeedback.feedback.id, direction: entryFeedback.direction) else {
            throw LayoutError.feedbackNotFound(feedbackId: entryFeedback.feedback.id)
        }
         
        BTLogger.router.debug("\(train, privacy: .public): enters block \(entryFeedback.block, privacy: .public) at position \(position), direction \(entryFeedback.direction)")
                
        // Set the train to its new block. This method also takes care of updating the reserved blocks for the train itself
        // but also the leading blocks so the train can continue to move automatically.
        try layout.setTrainToBlock(train.id, entryFeedback.block.id, position: .custom(value: position), direction: entryFeedback.direction, routeIndex: train.routeStepIndex + 1)
                             
        return .one(.movedToNextBlock)
    }

}
