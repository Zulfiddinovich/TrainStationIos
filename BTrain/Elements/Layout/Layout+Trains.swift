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

enum Position {
    case start
    case end
    case custom(value: Int)
}

extension Layout {
    
    @discardableResult
    func newTrain() -> Train {
        let id = Layout.newIdentity(trains)
        return addTrain(Train(uuid: id, name: id))
    }
    
    @discardableResult
    func addTrain(_ train: Train) -> Train {
        trains.append(train)
        return train
    }
    
    func train(for trainId: Identifier<Train>?) -> Train? {
        return trains.first(where: { $0.id == trainId })
    }

    func remove(trainId: Identifier<Train>) {
        try? remove(trainID: trainId)
        trains.removeAll(where: { $0.id == trainId})
    }
    
    func sortTrains() {
        trains.sort {
            $0.name < $1.name
        }
    }

    func removeAllTrains() {
        trains.forEach {
            try? remove(trainID: $0.id)
        }
    }
    
    func setTrainPosition(_ train: Train, _ position: Int) throws {
        guard let train = self.train(for: train.id) else {
            throw LayoutError.trainNotFound(trainId: train.id)
        }
        train.position = position
        
        try reservation.updateReservedBlocks(train: train)

        didChange()
    }
    
    // Returns the new position of the train given the specified feedback. This is used
    // to follow the train within a block when feedbacks are activated when the locomotive moves.
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
    func newPosition(forTrain train: Train, enabledFeedbackIndex: Int, direction: Direction) -> Int {
        let strict = strictRouteFeedbackStrategy

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
    
    func setTrainSpeed(_ train: Train, _ speed: TrainSpeed.UnitKph) throws {
        guard let train = self.train(for: train.id) else {
            throw LayoutError.trainNotFound(trainId: train.id)
        }
        
        train.speed.kph = speed
        self.executor?.sendTrainSpeed(train: train)
        
        self.didChange()
    }
    
    // Returns the direction of the train within the block (not the train direction itself
    // but the direction of the train relative the natural direction of the block)
    func directionDirectionInBlock(_ train: Train) throws -> Direction {
        guard let blockId = train.blockId else {
            throw LayoutError.trainNotAssignedToABlock(trainId: train.id)
        }
        
        guard let block = self.block(for: blockId) else {
            throw LayoutError.blockNotFound(blockId: blockId)
        }
        
        guard let ti = block.train else {
            throw LayoutError.trainNotFoundInBlock(blockId: blockId)
        }
        
        guard ti.trainId == train.id else {
            throw LayoutError.trainInBlockDoesNotMatch(trainId: train.id, blockId: blockId, blockTrainId: ti.trainId)
        }

        return ti.direction
    }
    
    // Set the direction of travel of the locomotive
    func setLocomotiveDirection(_ train: Train, forward: Bool) {
        if train.directionForward != forward {
            train.directionForward = forward
            self.executor?.sendTrainDirection(train: train)
        }
    }
    
    // Toggle the direction of the train within the block itself
    func toggleTrainDirectionInBlock(_ train: Train) throws {
        guard let blockId = train.blockId else {
            throw LayoutError.trainNotAssignedToABlock(trainId: train.id)
        }
        
        guard let block = self.block(for: blockId) else {
            throw LayoutError.blockNotFound(blockId: blockId)
        }

        guard let ti = block.train else {
            throw LayoutError.trainNotFoundInBlock(blockId: blockId)
        }

        guard ti.trainId == train.id else {
            throw LayoutError.trainInBlockDoesNotMatch(trainId: train.id, blockId: blockId, blockTrainId: ti.trainId)
        }

        block.train = TrainInstance(train.id, ti.direction.opposite)
        train.wagonsPushedByLocomotive.toggle()

        try reservation.updateReservedBlocks(train: train)

        self.didChange()
    }
        
    func start(routeID: Identifier<Route>, trainID: Identifier<Train>, destination: Destination? = nil) throws {
        guard let route = self.route(for: routeID, trainId: trainID) else {
            throw LayoutError.routeNotFound(routeId: routeID)
        }
        
        guard let train = self.train(for: trainID) else {
            throw LayoutError.trainNotFound(trainId: trainID)
        }
        
        guard let blockId = train.blockId else {
            throw LayoutError.trainNotAssignedToABlock(trainId: train.id)
        }
        
        guard let block = self.block(for: blockId), block.train != nil else {
            throw LayoutError.trainNotFoundInBlock(blockId: blockId)
        }

        // Set the route to the train
        train.routeId = routeID

        if route.automatic {
            // Ensure the automatic route associated with the train is updated
            // Note: remember the destination block
            if let destination = destination {
                route.automaticMode = .once(destination: destination)
            } else {
                route.automaticMode = .endless
            }
            try automaticRouting.updateAutomaticRoute(for: trainID)
        } else {
            // Check to make sure the train is somewhere along the route
            train.routeStepIndex = -1
            for (index, step) in route.steps.enumerated() {
                guard train.blockId == step.blockId else {
                    continue
                }
                
                guard let block = self.block(for: train.blockId) else {
                    continue
                }

                guard let trainInstance = block.train else {
                    continue
                }
                
                // Check that the train direction matches as well.
                if trainInstance.direction == step.direction {
                    train.routeStepIndex = index
                    break
                }
            }
                                 
            guard train.routeStepIndex >= 0 else {
                throw LayoutError.trainNotFoundInRoute(train: train, route: route)
            }
        }

        train.scheduling = .automatic(finishing: false)
    }
    
    func trainShouldStop(train: Train, block: Block) -> Bool {
        guard block.category == .station else {
            return false
        }

        guard train.routeStepIndex != train.startRouteIndex || train.startRouteIndex == nil else {
            return false
        }

        return true
    }

    // Stop the specified train. If completely is true,
    // set the state running to false of the train which means
    // it won't restart anymore.
    func stopTrain(_ trainId: Identifier<Train>, completely: Bool = false) throws {
        guard let train = self.train(for: trainId) else {
            throw LayoutError.trainNotFound(trainId: trainId)
        }
        
        BTLogger.debug("Stopping train \(train.name) \(completely ? "completely." : "until it can be restarted.")")
        
        train.speed.kph = 0
        self.executor?.sendTrainSpeed(train: train)

        train.state = .stopped

        if completely {
            try stopCompletely(trainId)
        }
        
        self.didChange()
    }

    func stopCompletely(_ trainId: Identifier<Train>) throws {
        guard let train = self.train(for: trainId) else {
            throw LayoutError.trainNotFound(trainId: trainId)
        }
        
        BTLogger.debug("Stopping train \(train.name) completely")

        train.scheduling = .manual
        try reservation.updateReservedBlocks(train: train)
    }
    
    // Use this method to stop the train when it finishes the route
    func finishTrain(_ trainId: Identifier<Train>) throws {
        guard let train = self.train(for: trainId) else {
            throw LayoutError.trainNotFound(trainId: trainId)
        }

        train.scheduling = .automatic(finishing: true)
    }

    // This method sets the train in a specific block and updates the reserved blocks (occupied and leading blocks).
    func setTrainToBlock(_ trainId: Identifier<Train>, _ toBlockId: Identifier<Block>, position: Position = .start, direction: Direction, routeIndex: Int? = nil) throws {
        guard let train = self.train(for: trainId) else {
            throw LayoutError.trainNotFound(trainId: trainId)
        }
        
        guard let toBlock = self.block(for: toBlockId) else {
            throw LayoutError.blockNotFound(blockId: toBlockId)
        }

        guard toBlock.train == nil || toBlock.train?.trainId == trainId else {
            throw LayoutError.blockNotEmpty(blockId: toBlockId)
        }
                
        guard toBlock.reserved == nil || toBlock.reserved?.trainId == train.id else {
            throw LayoutError.cannotReserveBlock(block: toBlock, train: train, reserved: toBlock.reserved!)
        }

        defer {
            didChange()
        }
        
        // Determine the position of the train
        switch(position) {
        case .start:
            train.position = direction == .next ? 0 : toBlock.feedbacks.count
        case .end:
            train.position = direction == .next ? toBlock.feedbacks.count : 0
        case .custom(value: let value):
            train.position = value
        }

        // Reserve the block
        toBlock.reserved = .init(trainId: train.id, direction: direction)
        toBlock.train = TrainInstance(trainId, direction)

        // Assign the block to the train
        train.blockId = toBlock.id
        
        // Update the route index if specified
        if let routeIndex = routeIndex {
            train.routeStepIndex = routeIndex
        }

        try reservation.updateReservedBlocks(train: train)
    }

    func free(fromBlock: Identifier<Block>, toBlockNotIncluded: Identifier<Block>, direction: Direction) throws {
        guard let b1 = self.block(for: fromBlock) else {
            throw LayoutError.blockNotFound(blockId: fromBlock)
        }

        guard let b2 = self.block(for: toBlockNotIncluded) else {
            throw LayoutError.blockNotFound(blockId: toBlockNotIncluded)
        }

        let transitions = try self.transitions(from: b1, to: b2, direction: direction)
        if transitions.count > 0 {
            for transition in transitions {
                transition.reserved = nil
                if let turnoutId = transition.b.turnout {
                    guard let turnout = self.turnout(for: turnoutId) else {
                        throw LayoutError.turnoutNotFound(turnoutId: turnoutId)
                    }
                    turnout.reserved = nil
                }
            }
        } else {
            BTLogger.debug("No transition found between \(b1) and \(b2), direction \(direction)")
        }
        
        try free(block: b1.id)
    }
    
    func free(block: Identifier<Block>) throws {
        guard let b1 = self.block(for: block) else {
            throw LayoutError.blockNotFound(blockId: block)
        }

        BTLogger.debug("Freeing block \(b1.name)")
        
        b1.reserved = nil
        if let blockTrain = b1.train {
            guard let train = self.train(for: blockTrain.trainId) else {
                throw LayoutError.trainNotFound(trainId: blockTrain.trainId)
            }
            // Remove the block assignment from the train if the train is located in the block
            if train.blockId == b1.id {
                train.blockId = nil
            }
            b1.train = nil
        }
    }
    
    // Remove the train from the layout (but not from the list of train)
    func remove(trainID: Identifier<Train>) throws {
        guard let train = self.train(for: trainID) else {
            throw LayoutError.trainNotFound(trainId: trainID)
        }
        
        // Remove the train from the blocks
        blockMap.values
            .filter { $0.reserved?.trainId == train.id }
            .forEach { block in
                block.reserved = nil
                block.train = nil
            }
        turnouts.filter { $0.reserved == train.id }.forEach { $0.reserved = nil; $0.train = nil }
        transitions.filter { $0.reserved == train.id }.forEach { $0.reserved = nil; $0.train = nil }
        
        train.blockId = nil
        
        didChange()
    }

}
