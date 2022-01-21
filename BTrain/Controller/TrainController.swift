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

protocol TrainControllerDelegate: AnyObject {
    func scheduleRestartTimer(trainInstance: Block.TrainInstance)
}

// This class manages a single train in the layout, by starting and stopping it,
// managing the monitoring when it transition from one block to another, etc.
final class TrainController {
    
    // Most method in this class returns a result
    // that indicates if that method has done something
    // or not. This is useful information that will help
    // the LayoutController to re-run the TrainController
    // in case there is any changes to be applied.
    enum Result {
        case none
        case processed
    }
    
    let layout: Layout
    let train: Train
    weak var delegate: TrainControllerDelegate?
    
    // Keeping track of the route index when the train starts,
    // to avoid stopping it immediately if it is still starting
    // in the first block of the route.
    var startRouteIndex: Int?
    
    struct StopTrigger {
        let stopCompletely: Bool
    }
    
    // If this variable is not nil, it means the train
    // has been asked to stop at the next opportunity.
    var stopTrigger: StopTrigger? = nil
    
    init(layout: Layout, train: Train, delegate: TrainControllerDelegate? = nil) {
        self.layout = layout
        self.train = train
        self.delegate = delegate
    }
            
    // This is the main method to call to manage the changes for the train.
    // If this method returns Result.processed, it is expected to be called again
    // in order to process any changes remaining.
    // Note: because each function below has a side effect that can affect
    // the currentBlock and nextBlock (as well as the train speed and other parameters),
    // always have each function retrieve what it needs.
    @discardableResult
    func run() throws -> Result {
        // Stop the train if there is no route associated with it
        guard let route = layout.route(for: train.routeId, trainId: train.id) else {
            return try stop()
        }

        // Return now if the train is not actively "running"
        guard train.scheduling != .stopped else {
            return .none
        }
        
        var result: Result = .none
        
        if try handleTrainStart() == .processed {
            result = .processed
        }

        if try handleTrainMove() == .processed {
            result = .processed
        }
        
        if try handleTrainStop() == .processed {
            result = .processed
        }
        
        if try handleTrainAutomaticRouteUpdate(route: route) == .processed {
            result = .processed
        }
        
        if try handleTrainStop() == .processed {
            result = .processed
        }

        if try handleTrainMoveToNextBlock(route: route) == .processed {
            result = .processed
        }
        
        if try handleTrainStop() == .processed {
            result = .processed
        }

        return result
    }
    
    private func handleTrainStart() throws -> Result {
        guard train.speed.kph == 0 else {
            return .none
        }

        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }

        guard let routeId = train.routeId else {
            return .none
        }

        guard let route = layout.route(for: routeId, trainId: train.id) else {
            return .none
        }

        guard let trainInstance = currentBlock.train else {
            return .none
        }

        // Do not start the train if there is still time for the train until it has to restart
        guard trainInstance.timeUntilAutomaticRestart == 0 else {
            return .none
        }
        
        let nextBlock = layout.nextBlock(train: train)
        
        // Update the automatic route if the next block is not defined and if the automatic route
        // does not have a destinationBlock.
        if nextBlock == nil && route.automatic && route.automaticMode == .endless {
            BTLogger.debug("Generating a new route for \(train) at block \(currentBlock.name) with mode \(route.automaticMode) because the next block is not defined")
            return try updateAutomaticRoute(for: train.id)
        }
                
        // Try to reserve the next blocks and if successfull, then start the train
        if try reserveNextBlocks(route: route) {
            BTLogger.debug("Start train \(train.name) because the next blocks could be reserved")
            startRouteIndex = train.routeStepIndex
            try layout.setTrainSpeed(train, LayoutFactory.DefaultSpeed)
            train.state = .running
            return .processed
        }
        
        return .none
    }
    
    // This method updates the automatic route, if selected, in case the next block is occupied.
    private func handleTrainAutomaticRouteUpdate(route: Route) throws -> Result {
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }

        guard let nextBlock = layout.nextBlock(train: train) else {
            return .none
        }
        
        var nextBlockNotAvailable = false
        // If the next block is disabled, we need to re-compute a new route
        if !nextBlock.enabled {
            nextBlockNotAvailable = true
        }

        // If the next block contains a train, we need to re-compute a new route
        if nextBlock.train != nil {
            nextBlockNotAvailable = true
        }
        
        // If the next block is reserved for another train, we need to re-compute a new route
        if let reserved = nextBlock.reserved, reserved.trainId != train.id {
            nextBlockNotAvailable = true
        }
        
        guard nextBlockNotAvailable && route.automatic else {
            return .none
        }
        
        // Generate a new route if one is available
        debug("Generating a new route for \(train) at block \(currentBlock.name) because the next block \(nextBlock.name) is occupied or disabled")

        // Update the automatic route
        return try updateAutomaticRoute(for: train.id)
    }
        
    private func handleAutomaticRouteStop(route: Route) throws -> Result {
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }
        
        guard route.automatic else {
            return .none
        }
        
        // The train is not in the first step of the route
        guard train.routeStepIndex != startRouteIndex else {
            return .none
        }
        
        switch(route.automaticMode) {
        case .once(destination: let destination):
            if train.routeStepIndex == route.steps.count - 1 {
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
                                
                debug("Stopping completely \(train) because it has reached the end of the route")
                stopTrigger = .init(stopCompletely: true)
                return .processed
            }
            
        case .endless:
            if currentBlock.category == .station {
                if train.scheduling == .finishing {
                    debug("Stopping completely \(train) because it has reached a station and it is marked as .finishing")
                    stopTrigger = .init(stopCompletely: true)
                    return .processed
                } else {
                    let delay = currentBlock.waitingTime
                    debug("Schedule timer to restart train \(train) in \(delay) seconds")
                    
                    // The layout controller is going to schedule the appropriate timer given the `restartDelayTime` value
                    if let ti = currentBlock.train {
                        ti.timeUntilAutomaticRestart = delay
                        delegate?.scheduleRestartTimer(trainInstance: ti)
                    }
                    stopTrigger = .init(stopCompletely: false)
                    return .processed
                }
            }
        }
                                
        return .none
    }
    
//    func waitingTime(route: Route, train: Train) -> TimeInterval {
//        if let step = route.steps.element(at: train.routeIndex), let time = step.waitingTime {
//            return time
//        } else {
//            return 10.0 // Default time if nothing is specified
//        }
//    }
    
    private func handleManualRouteStop(route: Route) throws -> Result {
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }
        
        guard !route.automatic else {
            return .none
        }
        
        // The train is not in the first step of the route
        guard train.routeStepIndex != startRouteIndex else {
            return .none
        }
        
        if train.routeStepIndex == route.steps.count - 1 {
            debug("Train \(train) will stop here (\(currentBlock)) because it has reached the end of the route")
            stopTrigger = .init(stopCompletely: true)
            return .processed
        }
        
        return .none
    }
    
    private func handleTrainStop() throws -> Result {
        guard train.speed.kph > 0 else {
            return .none
        }
                
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }

        guard let trainInstance = currentBlock.train else {
            return .none
        }
        
        guard let stopTrigger = stopTrigger else {
            return .none
        }
        
        let direction = trainInstance.direction
        var result: Result = .none
        for (_, feedback) in currentBlock.feedbacks.enumerated() {
            guard let f = layout.feedback(for: feedback.feedbackId), f.detected else {
                continue
            }
            
            if train.state == .running {
                guard let brakeFeedback = currentBlock.brakeFeedback(for: direction) else {
                    throw LayoutError.brakeFeedbackNotFound(block: currentBlock)
                }
                if brakeFeedback == f.id {
                    debug("Train \(train) is braking in \(currentBlock.name) at position \(train.position), direction \(direction)")
                    train.state = .braking
                    try layout.setTrainSpeed(train, LayoutFactory.DefaultBrakingSpeed)
                    result = .processed
                }
            }
            
            if train.state == .braking {
                guard let stopFeedback = currentBlock.stopFeedback(for: direction) else {
                    throw LayoutError.stopFeedbackNotFound(block: currentBlock)
                }
                if stopFeedback == f.id {
                    debug("Train \(train) is stopped in \(currentBlock.name) at position \(train.position), direction \(direction)")
                    result = try stop(completely: stopTrigger.stopCompletely)
                }
            }
        }
        return result
    }
    
    private func handleTrainMove() throws -> Result {
        guard train.speed.kph > 0 else {
            return .none
        }
                
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }

        guard let trainInstance = currentBlock.train else {
            return .none
        }
        
        let direction = trainInstance.direction
        var result: Result = .none
        for (index, feedback) in currentBlock.feedbacks.enumerated() {
            guard let f = layout.feedback(for: feedback.feedbackId), f.detected else {
                continue
            }
            
            let position = newPosition(forTrain: train, enabledFeedbackIndex: index, direction: direction)
            if train.position != position {
                try layout.setTrainPosition(train, position)
                debug("Train \(train) moved to position \(train.position) in \(currentBlock.name), direction \(direction)")
                result = .processed
            }
                        
        }
        
        return result
    }
    
    //      ╲       ██            ██            ██
    //       ╲      ██            ██            ██
    //────────■─────██────────────██────────────██────────────▶
    //       ╱   0  ██     1      ██     2      ██     3
    //      ╱       ██            ██            ██     ▲
    //              0             1             2      │
    //                            ▲                    │
    //                            │                    │
    //                            │                    │
    //
    //                     Feedback Index       Train Position
    private func newPosition(forTrain train: Train, enabledFeedbackIndex: Int, direction: Direction) -> Int {
        let strict = layout.strictRouteFeedbackStrategy

        switch(direction) {
        case .previous:
            let delta = train.position - enabledFeedbackIndex
            if strict && delta == 1 {
                // this is the feedback in front of the train, it means
                // the train has moved past this feedback
                return train.position - delta
            }
            if !strict && delta > 0 {
                // A feedback in front of the train has been activated.
                // When not in strict mode, we update the position of the train.
                return train.position - delta
            }

        case .next:
            let delta = enabledFeedbackIndex - train.position
            if strict && delta == 0 {
                // this is the feedback in front of the train, it means
                // the train has moved past this feedback
                return train.position + 1
            }
            if !strict && delta >= 0 {
                // A feedback in front of the train has been activated.
                // When not in strict mode, we update the position of the train.
                return train.position + delta + 1
            }
        }
        
        return train.position
    }
    
    private func handleTrainMoveToNextBlock(route: Route) throws -> Result {
        guard train.speed.kph > 0 else {
            return .none
        }
        
        guard try layout.shouldHandleTrainMoveToNextBlock(train: train) else {
            return .none
        }
        
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }

        guard let nextBlock = layout.nextBlock(train: train) else {
            return .none
        }

        // Find out what is the entry feedback for the next block
        let (entryFeedback, direction) = try layout.feedbackTriggeringTransition(from: currentBlock, to: nextBlock)
        
        guard let entryFeedback = entryFeedback, entryFeedback.detected else {
            // The first feedback is not yet detected, nothing more to do
            return .none
        }
        
        guard let position = nextBlock.indexOfTrain(forFeedback: entryFeedback.id, direction: direction) else {
            throw LayoutError.feedbackNotFound(feedbackId: entryFeedback.id)
        }
                
        debug("Train \(train) enters block \(nextBlock) at position \(position), direction \(direction)")

        // Remember the current step before moving to the next block
        rememberCurrentBlock(route: route)
        
        // Set the leading flag to false for the current block (now the previous one) and the next block (now the current one)
        // TODO: better way to do that?
        currentBlock.reserved?.leading = false
        nextBlock.reserved?.leading = false
        
        // Set the train to its new block
        try layout.setTrainToBlock(train.id, nextBlock.id, position: .custom(value: position), direction: direction)

        // And remove the train from the previous block
        currentBlock.train = nil
        
        // Increment the train route index
        try layout.setTrainRouteStepIndex(train, train.routeStepIndex + 1)
                
        // Free up the trailing blocks        
        try freeTrailingBlocks()
        
        // Reserve the block(s) ahead. If it is not possible, then stop the train in this block
        if try reserveNextBlocks(route: route) == false {
            debug("Train \(train) will stop here (\(nextBlock)) because the next block(s) cannot be reserved")
            stopTrigger = .init(stopCompletely: false)
        }
        
        // Handle any route-specific stop now that the block has moved to a new block
        if route.automatic {
            _ = try handleAutomaticRouteStop(route: route)
        } else {
            _ = try handleManualRouteStop(route: route)
        }

        return .processed
    }
        
    private func rememberCurrentBlock(route: Route) {
        let step = route.steps[train.routeStepIndex]
        train.trailingReservedBlocks.append(.init(step.blockId, step.direction))
    }
    
    private func freeTrailingBlocks() throws {
        guard let currentBlock = layout.currentBlock(train: train) else {
            throw LayoutError.trainNotAssignedToABlock(trainId: train.id)
        }
        
        // [ b1, b2, b3 ]    // Previous visited blocks that are kept reserved
        //                b4 // Current block where the train resides
        // Free up the following blocks, in order:
        // b1-b2
        // b2-b3
        // b3-b4
        while train.trailingReservedBlocks.count > train.numberOfTrailingReservedBlocks {
            if train.trailingReservedBlocks.count >= 2 {
                let step1 = train.trailingReservedBlocks.removeFirst()
                let step2 = train.trailingReservedBlocks.first!
                try layout.free(fromBlock: step1.blockId, toBlockNotIncluded: step2.blockId, direction: step1.direction)
            } else if train.trailingReservedBlocks.count == 1 {
                let step = train.trailingReservedBlocks.removeFirst()
                try layout.free(fromBlock: step.blockId, toBlockNotIncluded: currentBlock.id, direction: step.direction)
            } else {
                break
            }
        }
    }
    
    private func reserveNextBlocks(route: Route) throws -> Bool {
        let startReservationIndex = min(route.steps.count-1, train.routeStepIndex + 1)
        let endReservationIndex = min(route.steps.count-1, train.routeStepIndex + train.maxNumberOfLeadingReservedBlocks)
                
        var previousStep = route.steps[train.routeStepIndex]
        let stepsToReserve = route.steps[startReservationIndex...endReservationIndex]
        var numberOfBlocksReserved = 0
        for step in stepsToReserve {
            guard let block = layout.block(for: step.blockId) else {
                throw LayoutError.blockNotFound(blockId: step.blockId)
            }
            
            if let reservation = block.reserved {
                if reservation.trainId == train.id && reservation.leading {
                    // The reservation was already done
                } else {
                    // If the block is already reserved, bail out here.
                    // If at least one block has been reserved, we consider
                    // the reservation to be successfull.
                    return numberOfBlocksReserved > 0
                }
            }
                        
            guard block.train == nil else {
                // If the block already contains a train, bail out here.
                // If at least one block has been reserved, we consider
                // the reservation to be successfull.
                return numberOfBlocksReserved > 0
            }
            
            guard block.enabled else {
                return false
            }

            // Note: it is possible or this call to throw an exception if it cannot reserve.
            // Catch it and return false instead as this is not an error we want to report back to the runtime
            do {
                try layout.reserve(trainId: train.id, fromBlock: previousStep.blockId, toBlock: block.id, direction: previousStep.direction)
                BTLogger.debug("Reserved \(previousStep.blockId) to \(block.id) for \(train.name)")
                numberOfBlocksReserved += 1
            } catch {
                BTLogger.debug("Cannot reserve block \(previousStep.blockId) to \(block.id) for \(train.name): \(error)")
                return false
            }

            previousStep = step
        }
        
        return true
    }
    
    private func stop(completely: Bool = false) throws -> Result {
        stopTrigger = nil
        
        guard train.speed.kph > 0 else {
            return .none
        }
        
        debug("Stop train \(train)")
        
        try layout.stopTrain(train.id, completely: completely)
                
        return .processed
    }
        
    private func updateAutomaticRoute(for trainId: Identifier<Train>) throws -> Result {
        let (success, route) = try layout.updateAutomaticRoute(for: train.id)
        if success {
            debug("Generated route is: \(route.steps)")
            return .processed
        } else {
            BTLogger.warning("Unable to find a suitable route for train \(train)")
            return .none
        }
    }
    
    private func debug(_ message: String) {
        BTLogger.debug(message)
    }

}
