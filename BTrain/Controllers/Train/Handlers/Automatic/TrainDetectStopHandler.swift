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

final class TrainDetectStopHandler: TrainAutomaticSchedulingHandler {
    
    var events: Set<TrainEvent> {
        [.movedToNextBlock]
    }

    func process(layout: Layout, train: Train, route: Route, event: TrainEvent, controller: TrainControlling) throws -> TrainHandlerResult {
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none()
        }
        
        // The train is not in the first step of the route
        guard train.routeStepIndex != train.startRouteIndex else {
            return .none()
        }
        
        switch(route.mode) {
        case .automaticOnce(destination: let destination):
            // This method handles any stop trigger related to the automatic route, which are:
            // - The train reaches the end of the route (that does not affect `endless` automatic route)
            // - The train reaches a block that stops the train for a while (ie station)
            if train.routeStepIndex == route.lastStepIndex {
                // Double-check that the train is located in the block specified by the destination.
                // This should never fail.
                guard currentBlock.id == destination.blockId else {
                    throw LayoutError.destinationBlockMismatch(currentBlock: currentBlock, destination: destination)
                }
                
                // Double-check that the train is moving in the direction specified by the destination, if specified.
                // This should never fail.
                if let direction = destination.direction, currentBlock.train?.direction != direction {
                    throw LayoutError.destinationDirectionMismatch(currentBlock: currentBlock, destination: destination)
                }
                                
                BTLogger.router.debug("\(train, privacy: .public): requesting to stop completely because it has reached the end of the route \(route.name)")

                train.stateChangeRequest = .stopCompletely
                return .one(.stopRequested)
            }
            
        case .automatic:
            return handleTrainStopByBlock(layout: layout, train: train, route: route, block: currentBlock)
            
        case .fixed:
            // This method handles any stop trigger related to the manual route, which are:
            // - The train reaches the end of the route
            // - The train reaches a block that stops the train for a while (ie station)
            if train.routeStepIndex == route.lastStepIndex {
                BTLogger.router.debug("\(train, privacy: .public): requesting to stop completely here \(currentBlock, privacy: .public) because it has reached the end of the route \(route.name)")
                train.stateChangeRequest = .stopCompletely
                return .one(.stopRequested)
            }
            
            return handleTrainStopByBlock(layout: layout, train: train, route: route, block: currentBlock)
        }
                                
        return .none()
    }
            
    // This method takes care to trigger a stop of the train located in
    // the specified `block`, depending on the block characteristics.
    // For now, only "station" blocks make the train stop.
    private func handleTrainStopByBlock(layout: Layout, train: Train, route: Route, block: Block) -> TrainHandlerResult {
        guard layout.trainShouldStop(train: train, block: block) else {
            return .none()
        }
                
        if train.managedFinishingScheduling {
            BTLogger.router.debug("\(train, privacy: .public): requesting to stop completely because it has reached a station and was finishing the route \(route.name)")
            train.stateChangeRequest = .stopCompletely
            return .one(.stopRequested)
        } else {
            let delay = waitingTime(route: route, train: train, block: block)
            BTLogger.router.debug("\(train, privacy: .public): requesting to stop at \(block, privacy: .public) for \(delay)s and then restart. Route \(route.name)")
            train.stateChangeRequest = .stopAndRestart(delay: delay)
            return .one(.stopRequested)
        }
    }

    private func waitingTime(route: Route, train: Train, block: Block) -> TimeInterval {
        if let step = route.steps.element(at: train.routeStepIndex), case .block(let stepBlock) = step, let time = stepBlock.waitingTime {
            return time
        } else {
            // Use the block waiting time if the route itself has nothing specified
            return block.waitingTime
        }
    }
        
}