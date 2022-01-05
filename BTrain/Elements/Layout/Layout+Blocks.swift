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
import OrderedCollections

extension Layout {
    
    var blockIds: OrderedSet<Identifier<Block>> {
        return blockMap.keys
    }
    
    var blocks: [Block] {
        get {
            return blockMap.values.map { $0 }
        }
        set {
            blockMap.removeAll()
            newValue.forEach { blockMap[$0.id] = $0 }
        }
    }

    @discardableResult
    func newBlock(name: String, type: Block.Category) -> Block {
        let block = Block(id: Layout.newIdentity(blockMap), name: name, type: type, center: .init(x: 100, y: 100), rotationAngle: 0)
        blockMap[block.id] = block
        return block
    }
    
    func remove(blockID: Identifier<Block>) {
        blockMap.removeValue(forKey: blockID)

        mutableTrains.forEach { train in
            if train.blockId == blockID {
                train.blockId = nil
            }
        }
        
        transitions.removeAll { transition in
            return transition.a.block == blockID ||
            transition.b.block == blockID
        }
    }
    
    func mutableBlock(at index: Int) -> Block {
        return blockMap.values[index]
    }
    
    func mutableBlock(for blockId: Identifier<Block>) -> Block? {
        return blockMap[blockId]
    }
    
    func mutableBlock(for trainId: Identifier<Train>) -> Block? {
        return blockMap.first(where: { $0.value.train?.trainId == trainId })?.value
    }
    
    func sortBlocks() {
        blockMap.sort {
            $0.value.name < $1.value.name
        }
    }

    func block(at index: Int) -> Block {
        return blockMap.values[index]
    }
    
    func block(for blockId: Identifier<Block>?) -> Block? {
        return blocks.first(where: { $0.id == blockId })
    }

    func assign(_ block: Block, _ feedbacks: [Feedback]) {
        block.assign(feedbacks.map { $0.id })
        for feedback in feedbacks {
            if !self.feedbacks.contains(feedback) {
                self.feedbacks.append(feedback)
            }
        }
    }

    func add(_ blocks: [Block]) {
        for block in blocks {
            self.blockMap[block.id] = block
        }
    }
        
    func currentBlock(train: ITrain) -> Block? {
        if let blockId = train.blockId {
            return block(for: blockId)
        } else {
            return nil
        }
    }

    func nextBlock(train: ITrain) -> Block? {
        if let route = route(for: train.routeId, trainId: train.id) {
            if train.routeIndex + 1 < route.steps.count {
                let nextBlockId = route.steps[train.routeIndex+1].blockId
                return block(for: nextBlockId)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    func atEndOfBlock(train: ITrain) -> Bool {
        if let currentBlock = currentBlock(train: train) {
            if currentBlock.trainNaturalDirection {
                return train.position == currentBlock.feedbacks.count
            } else {
                return train.position == 0
            }
        } else {
            return false
        }
    }

}
