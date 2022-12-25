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

final class LayoutASCIIProducer {
    let layout: Layout

    init(layout: Layout) {
        self.layout = layout
    }

    func stringFrom(route: Route, trainId: Identifier<Train>, useBlockName: Bool = false, useTurnoutName: Bool = false) throws -> String {
        var text = ""

        guard let train = layout.trains[trainId] else {
            throw LayoutError.trainNotFound(trainId: trainId)
        }

        let resolver = RouteResolver(layout: layout, train: train)
        let result = try resolver.resolve(unresolvedPath: route.steps, verbose: false)
        switch result {
        case let .success(resolvedPaths):
            if let resolvedPath = resolvedPaths.randomElement() {
                for step in resolvedPath {
                    switch step {
                    case let .block(stepBlock):
                        addSpace(&text)
                        try generateBlock(step: stepBlock, useBlockName: useBlockName, text: &text)
                    case let .turnout(stepTurnout):
                        addSpace(&text)
                        generateTurnout(step: stepTurnout, useTurnoutName: useTurnoutName, text: &text)
                    }
                }
            }
            return text

        case .failure:
            return text
        }
    }

    private func generateBlock(step: ResolvedRouteItemBlock, useBlockName: Bool, text: inout String) throws {
        let block = step.block

        let reverse = step.direction == .previous
        if reverse {
            text += "!"
        }
        switch block.category {
        case .station:
            text += "{"
            if let reserved = block.reservation {
                text += "r\(reserved.trainId)"
                text += "{"
            }
            if useBlockName {
                text += "\(block.name)"
            } else {
                text += "\(block.id)"
            }
        case .free, .sidingNext, .sidingPrevious:
            if block.category == .sidingPrevious {
                text += "|"
            }
            text += "["
            if let reserved = block.reservation {
                text += "r\(reserved.trainId)"
                text += "["
            }
            if useBlockName {
                text += "\(block.name)"
            } else {
                text += "\(block.id)"
            }
        }

        // 0 | 1 | 2
        // [ A ≏ B ≏ C ]
        // 2 | 1 | 0
        // [ C ≏ B ≏ A ]
        if !reverse {
            if let part = train(block, 0) {
                text += " " + part
            }
        }

        let feedbacks = reverse ? block.feedbacks.reversed() : block.feedbacks
        for index in feedbacks.indices {
            let partIndex = reverse ? feedbacks.count - index - 1 : index

            let feedback = feedbacks[index]
            guard let f = layout.feedbacks[feedback.feedbackId] else {
                throw LayoutError.feedbackNotFound(feedbackId: feedback.feedbackId)
            }

            if reverse {
                if let part = train(block, partIndex + 1) {
                    text += " " + part
                }
            }

            if f.detected {
                text += " ≡"
            } else {
                text += " ≏"
            }

            if !reverse {
                if let part = train(block, partIndex + 1) {
                    text += " " + part
                }
            }
        }

        if reverse {
            if let part = train(block, 0) {
                text += " " + part
            }
        }
        switch block.category {
        case .station:
            if block.reservation != nil {
                text += " }}"
            } else {
                text += " }"
            }
        case .free, .sidingNext, .sidingPrevious:
            if block.reservation != nil {
                text += " ]]"
            } else {
                text += " ]"
            }
            if block.category == .sidingNext {
                text += "|"
            }
        }
    }

    func generateTurnout(step: ResolvedRouteItemTurnout, useTurnoutName: Bool, text: inout String) {
        let turnout = step.turnout

        text += "<"
        if let reserved = turnout.reserved?.train {
            text += "r\(reserved)"
            text += "<"
        }

        // <t0{sl}(0,1),s>
        if useTurnoutName {
            text += "\(turnout.name)"
        } else {
            text += "\(turnout.id)"
        }
        text += "{\(turnoutType(turnout))}"

        let entrySocket = step.entrySocketId
        let exitSocket = step.exitSocketId
        text += "(\(entrySocket),\(exitSocket))"

        if let state = turnoutState(turnout.state(fromSocket: entrySocket, toSocket: exitSocket)) {
            text += ",\(state)"
        }
        if turnout.reserved != nil {
            text += ">"
        }
        text += ">"
    }

    func turnoutState(_ state: Turnout.State) -> String? {
        switch state {
        case .straight:
            return "s"
        case .branch:
            return "b"
        case .branchLeft:
            return "l"
        case .branchRight:
            return "r"
        case .straight01:
            return "s01"
        case .straight23:
            return "s23"
        case .branch03:
            return "b03"
        case .branch21:
            return "b21"
        case .invalid:
            return nil
        }
    }

    func turnoutType(_ turnout: Turnout) -> String {
        switch turnout.category {
        case .singleLeft:
            return "sl"
        case .singleRight:
            return "sr"
        case .threeWay:
            return "tw"
        case .doubleSlip:
            return "ds"
        case .doubleSlip2:
            return "ds2"
        }
    }

    func train(_ block: Block, _ position: Int) -> String? {
        guard let trainInstance = block.trainInstance else {
            return nil
        }

        guard let train = layout.trains[trainInstance.trainId] else {
            return nil
        }

        if trainInstance.parts.isEmpty, train.positions.head?.index == position {
            return stringFrom(train)
        } else if let part = trainInstance.parts[position] {
            switch part {
            case .locomotive:
                return stringFrom(train)
            case .wagon:
                if let tail = train.positions.tail, tail.index == position && tail.blockId == block.id {
                    return "􀼰\(train.id)"
                } else {
                    return "􀼯\(train.id)"
                }
            }
        } else {
            return nil
        }
    }

    func stringFrom(_ train: Train) -> String {
        var text: String
        switch train.state {
        case .running:
            if train.speed?.requestedKph == LayoutFactory.DefaultLimitedSpeed {
                text = "🔵"
            } else {
                text = "🟢"
            }
        case .braking:
            text = "🟡"
        case .stopping:
            text = "🟠"
        case .stopped:
            text = "🔴"
        }
        if !train.directionForward {
            text += "!"
        }
        text += "􀼮\(train.id)"
        return text
    }

    private func addSpace(_ text: inout String) {
        if text.isEmpty {
            return
        }
        if text.last == " " {
            return
        }
        text += " "
    }
}
