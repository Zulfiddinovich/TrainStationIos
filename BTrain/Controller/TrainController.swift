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

import Foundation

final class TrainController {
    
    enum Result {
        case none
        case processed
    }
    
    let layout: Layout
    let train: Train
    
    var startBlock: Block?
    
    init(layout: Layout, train: Train) {
        self.layout = layout
        self.train = train
    }
        
    @discardableResult
    func run() -> Result {
        do {
            return try tryRun()
        } catch {
            // Stop the train in case there is a problem processing the layout
            BTLogger.error("Stop train \(train) because there is an error processing the layout: \(error)")
            do {
                try layout.stopTrain(train)
            } catch {
                BTLogger.error("Unable to stop train \(train) because \(error.localizedDescription)")
            }
            
            return .processed
        }
    }
    
    func tryRun() throws -> Result {
        guard let route = layout.route(for: train.routeId, trainId: train.id) else {
            // Stop the train if there is no route associated with it
            return try stop()
        }

        guard route.enabled else {
            // Stop the train if the route is disabled
            return try stop()
        }

        // Note: because each function below has a side effect that can affect
        // the currentBlock and nextBlock (as well as the train speed and other parameters),
        // always have each function retrieve what it needs.
        var result: Result = .none
        
        if try handleTrainStart() == .processed {
            result = .processed
        }

        if try handleTrainMove() == .processed {
            result = .processed
        }
        
        if try handleTrainAutomaticRouteUpdate(route: route) == .processed {
            result = .processed
        }
        
        if try handleTrainStop() == .processed {
            result = .processed
        }

        if try handleTrainMoveToNextBlock() == .processed {
            result = .processed
        }
        
        if try handleTrainStop() == .processed {
            result = .processed
        }

        return result
    }
    
    func handleTrainStart() throws -> Result {
        guard train.speed == 0 else {
            return .none
        }

        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }

        let nextBlock = layout.nextBlock(train: train)

        // Start train if next block is free and reserve it
        if let nextBlock = nextBlock, (nextBlock.reserved == nil || nextBlock.reserved == currentBlock.reserved) && nextBlock.train == nil && nextBlock.enabled {
            do {
                try layout.reserve(train: train.id, fromBlock: currentBlock.id, toBlock: nextBlock.id, direction: currentBlock.train!.direction)
                BTLogger.debug("Start train \(train) because the next block \(nextBlock) is free or reserved for this train", layout, train)
                startBlock = currentBlock
                try layout.setTrain(train, speed: LayoutFactory.Speed)
                return .processed
            } catch {
                BTLogger.debug("Cannot start train \(train) because \(error)", layout, train)
            }
        }
        
        return .none
    }
    
    // This method updates the automatic route, if selected, in case the next block is occupied.
    func handleTrainAutomaticRouteUpdate(route: Route) throws -> Result {
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
        BTLogger.debug("Generating a new route for \(train.name) at block \(currentBlock.name) because the next block \(nextBlock.name) is occupied or disabled")

        // Update the automatic route using any previously defined destination block
        let route = try layout.updateAutomaticRoute(for: train.id, toBlockId: route.destinationBlock)
        BTLogger.debug("Generated route is: \(route.steps)")
        
        _ = tryReserveNextBlocks(direction: currentBlock.train!.direction)
        
        return .processed
    }
    
    func handleTrainStop() throws -> Result {
        guard train.speed > 0 else {
            return .none
        }
        
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }

        let atEndOfBlock = layout.atEndOfBlock(train: train)
        
        guard let nextBlock = layout.nextBlock(train: train) else {
            // Stop the train if there is no next block
            if atEndOfBlock {
                BTLogger.debug("Stop train \(train) because there is no next block (after \(currentBlock))", layout, train)
                return try stop()
            } else {
                return .none
            }
        }
        
        // Stop the train if the current block is a station, the train is located at the end of the block
        // and the train is running (this is to ensure we don't stop a train that just started from the station).
        // Stop the train when it reaches a station block, given that this block is not the one where the train
        // started - to avoid stopping a train that is starting from a station block (while still in that block).
        if currentBlock.category == .station && atEndOfBlock && currentBlock.id != startBlock?.id {
            BTLogger.debug("Stop train \(train) because the current block \(currentBlock) is a station", layout, train)
            return try stop()
        }

        // Stop if the next block is occupied
        if nextBlock.train != nil && atEndOfBlock {
            BTLogger.debug("Stop train \(train) train because the next block is occupied", layout, train)
            return try stop()
        }

        // Stop if the next block is reserved for another train
        // Note: only test the train ID because the direction can actually be different; for example, exiting
        // the current block in the "next" direction but traveling inside the next block with the "previous" direction.
        if let reserved = nextBlock.reserved, reserved != currentBlock.reserved && atEndOfBlock {
            BTLogger.debug("Stop train \(train) because the next block is reserved for another train \(reserved)", layout, train)
            return try stop()
        }
        
        // Stop if the next block is not reserved
        if nextBlock.reserved == nil && atEndOfBlock {
            BTLogger.debug("Stop train \(train) because the next block is not reserved", layout, train)
            return try stop()
        }

        // Stop if the next block is disabled
        if !nextBlock.enabled && atEndOfBlock {
            BTLogger.debug("Stop train \(train) because the next block is disabled", layout, train)
            return try stop()
        }

        if currentBlock.reserved == nil {
            BTLogger.debug("Stop train \(train) because the current block is not reserved", layout, train)
            return try stop()
        }
        
        return .none
    }
    
    func handleTrainMove() throws -> Result {
        guard train.speed > 0 else {
            return .none
        }
                
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }

        guard let trainInstance = currentBlock.train else {
            return .none
        }
        
        // feedback index:     0       1       2
        // block:          [   f1      f2      f3    ]
        // train.position:   0     1       2      3
        var result: Result = .none
        for (index, feedback) in currentBlock.feedbacks.enumerated() {
            guard let f = layout.feedback(for: feedback.feedbackId), f.detected else {
                continue
            }
            
            switch(trainInstance.direction) {
            case .previous:
                if index == train.position - 1 {
                    // this is the feedback in front of the train, it means
                    // the train has moved past this feedback
                    try layout.setTrain(train, toPosition: train.position - 1)
                    BTLogger.debug("Train moved to position \(train.position), direction \(trainInstance.direction)", layout, train)
                    result = .processed
                }
            case .next:
                if index == train.position {
                    // this is the feedback in front of the train, it means
                    // the train has moved past this feedback
                    try layout.setTrain(train, toPosition: train.position + 1)
                    BTLogger.debug("Train moved to position \(train.position), direction \(trainInstance.direction)", layout, train)
                    result = .processed
                }
            }
        }
        
        return result
    }
    
    func handleTrainMoveToNextBlock() throws -> Result {
        guard train.speed > 0 else {
            return .none
        }
        
        guard layout.atEndOfBlock(train: train) else {
            return .none
        }
        
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }

        guard let nextBlock = layout.nextBlock(train: train) else {
            return .none
        }

        // Get the first feedback that the train will hit upon entering the block,
        // which depends on the direction of travel within the block itself.
        let (firstFeedback, naturalDirection) = try layout.feedbackTriggeringTransition(from: currentBlock, to: nextBlock)
        
        guard let firstFeedback = firstFeedback, firstFeedback.detected else {
            // The first feedback is not yet detected, nothing more to do
            return .none
        }
        
        // The next block now has the train
        let direction: Direction
        let position: Int
        if naturalDirection {
            direction = .next
            position = 1
        } else {
            // Entering the next block from the "next" side, meaning the train
            // is running backwards inside the block from the block natural direction.
            direction = .previous
            position = nextBlock.feedbacks.count - 1
        }
        
        BTLogger.debug("Train \(train) enters block \(nextBlock) at position \(position), \(direction)", layout, train)

        // Asks the layout to move the train to the next block
        try layout.setTrain(train.id, toBlock: nextBlock.id, position: .custom(value: position), direction: direction)
        
        try layout.setTrain(train, routeIndex: train.routeIndex + 1)
                
        // Reserve the block ahead if possible
        _ = tryReserveNextBlocks(direction: direction)
        
        return .processed
    }
    
    func tryReserveNextBlocks(direction: Direction) -> Result {
        guard let currentBlock = layout.currentBlock(train: train) else {
            return .none
        }
        
        guard let nextBlock = layout.nextBlock(train: train) else {
            return .none
        }
        
        guard nextBlock.reserved == nil else {
            return .none
        }
        
        guard nextBlock.enabled else {
            return .none
        }
        
        do {
            try layout.reserve(train: train.id, fromBlock: currentBlock.id, toBlock: nextBlock.id, direction: direction)
            BTLogger.debug("Next block \(nextBlock) is reserved", layout, train)
        } catch {
            BTLogger.debug("Cannot reserve next blocks because \(error)", layout, train)
        }
        
        return .processed
    }
    
    func stop() throws -> Result {
        guard train.speed > 0 else {
            return .none
        }
        
        BTLogger.debug("Stop train \(train)", layout, train)
        
        try layout.stopTrain(train)
        
        return .processed
    }
}
