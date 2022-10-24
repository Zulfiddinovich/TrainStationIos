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

extension Layout {
    
    var pathFinderOverflowLimit: Int {
        (turnouts.count + blocks.count) * 4
    }
        
    /// Returns the best route to reach ``toBlock`` given the specified ``train``.
    /// - Parameters:
    ///   - train: The train from which to start the route
    ///   - toBlock: The destination block of the route
    ///   - toDirection: The optional direction when reaching the ``toBlock``
    ///   - shortestPath: true if the shortest path is to be found, false if any path is suitable
    /// - Returns: a route, represented as a ``GraphPath`` or nil if no suitable route found.
    func bestPath(ofTrain train: Train, toReachBlock toBlock: Block?, withDirection toDirection: Direction?, reservedBlockBehavior: PathFinder.Constraints.ReservedBlockBehavior, shortestPath: Bool = SettingsKeys.bool(forKey: SettingsKeys.shortestRouteEnabled)) throws -> GraphPath? {
        let paths = try possiblePaths(for: train, toBlock: toBlock, toDirection: toDirection, reservedBlockBehavior: reservedBlockBehavior, shortestPath: shortestPath)
            .sorted(by: { $0.count < $1.count })
        return paths.first
    }
    
    private func possiblePaths(for train: Train, toBlock: Block?, toDirection: Direction?, reservedBlockBehavior: PathFinder.Constraints.ReservedBlockBehavior, shortestPath: Bool) throws -> [GraphPath] {
        var paths = [GraphPath]()
        
        guard let fromBlock = self.block(for: train.blockId) else {
            return []
        }

        guard let trainInstance = fromBlock.trainInstance else {
            throw LayoutError.trainNotFoundInBlock(blockId: fromBlock.id)
        }

        let fromDirections: [Direction]
        if train.canMoveBackwards {
            fromDirections = [.previous, .next]
        } else {
            fromDirections = [trainInstance.direction]
        }
        
        let toDirections: [Direction]
        if let toDirection = toDirection {
            toDirections = [toDirection]
        } else {
            toDirections = [.previous, .next]
        }
        
        for fromDirection in fromDirections {
            for toDirection in toDirections {
                if let path = try path(for: train, fromDirection: fromDirection, toBlock: toBlock, toDirection: toDirection, reservedBlockBehavior: reservedBlockBehavior, shortestPath: shortestPath) {
                    paths.append(path)
                }
            }
        }

        return paths
    }

    private func path(for train: Train, fromDirection: Direction, toBlock: Block?, toDirection: Direction, reservedBlockBehavior: PathFinder.Constraints.ReservedBlockBehavior, shortestPath: Bool) throws -> GraphPath? {
        let constraints = PathFinder.Constraints(layout: self,
                                                 train: train,
                                                 reservedBlockBehavior: reservedBlockBehavior,
                                                 stopAtFirstBlock: false,
                                                 relaxed: false)
        
        let settings = PathFinder.Settings(verbose: SettingsKeys.bool(forKey: SettingsKeys.logRoutingResolutionSteps),
                                           random: automaticRouteRandom,
                                           overflow: pathFinderOverflowLimit)
        let pf = PathFinder(constraints: constraints, settings: settings)
        
        guard let fromBlock = self.block(for: train.blockId) else {
            return nil
        }
        
        if let toBlock = toBlock {
            if shortestPath {
                return try self.shortestPath(for: train, from: (fromBlock, fromDirection), to: (toBlock, toDirection), pathFinder: pf)
            } else {
                return path(for: train, from: (fromBlock, fromDirection), to: (toBlock, toDirection), pathFinder: pf)
            }
        } else {
            return path(for: train, from: (fromBlock, fromDirection), to: nil, pathFinder: pf)
        }
    }
    
    private func path(for train: Train, from: (Block, Direction), to: (Block, Direction)?, pathFinder: PathFinder) -> GraphPath? {
        // Note: when direction is `next`, it means we are leaving the starting element from its `nextSocket`
        let fromElement = GraphPathElement.starting(from.0, from.1 == .next ? Block.nextSocket : Block.previousSocket)
        let toElement: GraphPathElement?
        if let to = to {
            // Note: when direction is `next`, it means we are entering the last block from its `previousSocket`
            toElement = .ending(to.0, to.1 == .next ? Block.previousSocket : Block.nextSocket)
        } else {
            toElement = nil
        }
        return pathFinder.path(graph: self, from: fromElement, to: toElement)
    }
 
    private func shortestPath(for train: Train, from: (Block, Direction), to: (Block, Direction), pathFinder: PathFinder) throws -> GraphPath? {
        let fromElement = from.1 == .next ? from.0.elementDirectionNext:from.0.elementDirectionPrevious
        let toElement = to.1 == .next ? to.0.elementDirectionNext:to.0.elementDirectionPrevious

        return try pathFinder.shortestPath(graph: self, from: fromElement, to: toElement)
    }
    
}