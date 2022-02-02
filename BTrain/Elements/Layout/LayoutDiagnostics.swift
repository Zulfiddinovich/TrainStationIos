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

enum DiagnosticError: Error, Equatable {
    case feedbackIdAlreadyExists(feedback: Feedback)
    case feedbackNameAlreadyExists(feedback: Feedback)
    case feedbackDuplicateAddress(feedback: Feedback)

    case turnoutIdAlreadyExists(turnout: Turnout)
    case turnoutNameAlreadyExists(turnout: Turnout)
    case turnoutMissingTransition(turnout: Turnout, socket: String)
    case turnoutDuplicateAddress(turnout: Turnout)
    
    case blockIdAlreadyExists(block: Block)
    case blockNameAlreadyExists(block: Block)
    case blockDuplicateFeedback(block: Block, feedback: Feedback)
    
    case blockMissingTransition(block: Block, socket: String)
    case invalidTransition(transitionId: Identifier<Transition>, socket: Socket)
    
    case blockMissingLength(block: Block)
    case turnoutMissingLength(turnout: Turnout)
    case trainMissingLength(train: Train)
    case trainMissingMagnetDistance(train: Train)
    case blockFeedbackMissingDistance(block: Block, feedbackId: Identifier<Feedback>)
}

extension DiagnosticError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .feedbackIdAlreadyExists(feedback: let feedback):
            return "Feedback ID \(feedback.id) (named \(feedback.name)) is used by more than one feedback"
        case .feedbackNameAlreadyExists(feedback: let feedback):
            return "Feedback name \(feedback.name) is used by more than one feedback"
        case .feedbackDuplicateAddress(feedback: let feedback):
            return "The address {deviceID=\(feedback.deviceID), contactID=\(feedback.contactID)} of feedback \(feedback.name) is already used by another feedback"
            
        case .blockIdAlreadyExists(block: let block):
            return "Block ID \(block.id) (named \(block.name)) is used by more than one block"
        case .blockNameAlreadyExists(block: let block):
            return "Block name \(block.name) is used by more than one block"
        case .blockDuplicateFeedback(block: let block, feedback: let feedback):
            return "Block \(block.name) uses feedback \(feedback.name) which is already used by another block"
            
        case .turnoutIdAlreadyExists(turnout: let turnout):
            return "Turnout ID \(turnout.id) (named \(turnout.name)) is used by more than one turnout"
        case .turnoutNameAlreadyExists(turnout: let turnout):
            return "Turnout name \(turnout.name) is used by more than one turnout"
        case .turnoutMissingTransition(turnout: let turnout, socket: let socket):
            return "Turnout \(turnout.name) is missing a transition from socket \(socket)"
        case .turnoutDuplicateAddress(turnout: let turnout):
            if turnout.doubleAddress {
                return "The address of turnout \(turnout.name) (\(turnout.address):\(turnout.address2)) is already used by another turnout"
            } else {
                return "The address of turnout \(turnout.name) (\(turnout.addressValue)) is already used by another turnout"
            }
        case .blockMissingTransition(block: let block, socket: let socket):
            return "Block \(block.name) is missing a transition from socket \(socket)"
        case .invalidTransition(transitionId: let transitionId, socket: let socket):
            return "Transition \(transitionId) is not connected via its socket \(socket)"
            
        case .blockMissingLength(block: let block):
            return "Block \(block.name) does not have a length defined"
        case .turnoutMissingLength(turnout: let turnout):
            return "Turnout \(turnout.name) does not have a length defined"
        case .blockFeedbackMissingDistance(block: let block, feedbackId: let feedbackId):
            return "Block \(block.name) does not have a distance defined for feedback \(feedbackId)"
            
        case .trainMissingLength(train: let train):
            return "Train \(train.name) does not have a length defined"
        case .trainMissingMagnetDistance(train: let train):
            return "Train \(train.name) does not have a distance defined for the magnet"
        }
    }
}

final class LayoutDiagnostic: ObservableObject {

    struct Options: OptionSet {
        let rawValue: Int

        static let lengths   = Options(rawValue: 1 << 0)
        static let duplicate = Options(rawValue: 1 << 1)
        static let orphaned  = Options(rawValue: 1 << 2)

        static let skipLengths: Options = [.duplicate, .orphaned]
        static let all: Options = [.lengths, .duplicate, .orphaned]
    }


    let layout: Layout
    let observer: LayoutObserver
        
    @Published var hasErrors = false
    
    init(layout: Layout) {
        self.layout = layout
        self.observer = LayoutObserver(layout: layout)
        self.automaticCheck()
        
        observer.registerForAnyChange() {
            DispatchQueue.main.async {
                self.automaticCheck()
            }
        }
    }

    func automaticCheck() {
        do {
            hasErrors = try check().count > 0
        } catch {
            BTLogger.error("Error checking the layout: \(error)")
            hasErrors = true
        }
    }
    
    func check(_ options: Options = Options.all) throws -> [DiagnosticError] {
        var errors = [DiagnosticError]()
                
        if options.contains(.duplicate) {
            checkForDuplicateFeedbacks(&errors)
            checkForDuplicateTurnouts(&errors)
            try checkForDuplicateBlocks(&errors)
        }
        
        if options.contains(.orphaned) {
            try checkForOrphanedElements(&errors)
        }
        
        if options.contains(.lengths) {
            checkForLengthAndDistance(&errors)
        }
        
        return errors
    }
    
    func checkForDuplicateBlocks(_ errors: inout [DiagnosticError]) throws {
        var ids = Set<Identifier<Block>>()
        for block in layout.blocks {
            if ids.contains(block.id) {
                errors.append(DiagnosticError.blockIdAlreadyExists(block: block))
            } else {
                ids.insert(block.id)
            }
        }

        var names = Set<String>()
        for block in layout.blocks {
            if names.contains(block.name) {
                errors.append(DiagnosticError.blockNameAlreadyExists(block: block))
            } else {
                names.insert(block.name)
            }
        }

        var feedbacks = Set<Identifier<Feedback>>()
        for block in layout.blocks {
            for blockFeedback in block.feedbacks {
                if feedbacks.contains(blockFeedback.feedbackId) {
                    guard let feedback = layout.feedback(for: blockFeedback.feedbackId) else {
                        throw LayoutError.feedbackNotFound(feedbackId: blockFeedback.feedbackId)
                    }
                    errors.append(DiagnosticError.blockDuplicateFeedback(block: block, feedback: feedback))
                }
                feedbacks.insert(blockFeedback.feedbackId)
            }
        }
    }

    func checkForDuplicateFeedbacks(_ errors: inout [DiagnosticError]) {
        var ids = Set<Identifier<Feedback>>()
        for f in layout.feedbacks {
            if ids.contains(f.id) {
                errors.append(DiagnosticError.feedbackIdAlreadyExists(feedback: f))
            } else {
                ids.insert(f.id)
            }
        }

        var names = Set<String>()
        for f in layout.feedbacks {
            if names.contains(f.name) {
                errors.append(DiagnosticError.feedbackNameAlreadyExists(feedback: f))
            } else {
                names.insert(f.name)
            }
        }

        var addresses = Set<String>()
        for f in layout.feedbacks {
            let key = "\(f.deviceID)-\(f.contactID)"
            if addresses.contains(key) {
                errors.append(DiagnosticError.feedbackDuplicateAddress(feedback: f))
            } else {
                addresses.insert(key)
            }
        }
    }

    func checkForDuplicateTurnouts(_ errors: inout [DiagnosticError]) {
        var ids = Set<Identifier<Turnout>>()
        for turnout in layout.turnouts {
            if ids.contains(turnout.id) {
                errors.append(DiagnosticError.turnoutIdAlreadyExists(turnout: turnout))
            } else {
                ids.insert(turnout.id)
            }
        }
        
        var names = Set<String>()
        for turnout in layout.turnouts {
            if names.contains(turnout.name) {
                errors.append(DiagnosticError.turnoutNameAlreadyExists(turnout: turnout))
            } else {
                names.insert(turnout.name)
            }
        }

        var addresses = Set<CommandTurnoutAddress>()
        for turnout in layout.turnouts {
            if addresses.contains(turnout.address) {
                errors.append(DiagnosticError.turnoutDuplicateAddress(turnout: turnout))
                addresses.insert(turnout.address)
            }
            if turnout.doubleAddress {
                if addresses.contains(turnout.address2) {
                    errors.append(DiagnosticError.turnoutDuplicateAddress(turnout: turnout))
                }
                addresses.insert(turnout.address2)
            }
        }
    }

    func checkForOrphanedElements(_ errors: inout [DiagnosticError]) throws {
        // Check for elements that are not linked together (orphaned sockets)
        for turnout in layout.turnouts {
            for socket in turnout.allSockets {
                if try layout.transitions(from: socket).isEmpty {
                    let name: String
                    if let socketId = socket.socketId {
                        name = turnout.socketName(socketId)
                    } else {
                        name = "any"
                    }
                    errors.append(DiagnosticError.turnoutMissingTransition(turnout: turnout, socket: name))
                }
            }
        }
        
        for block in layout.blocks {
            for socket in block.allSockets {
                if try layout.transitions(from: socket).isEmpty {
                    let name: String
                    if let socketId = socket.socketId {
                        name = block.socketName(socketId)
                    } else {
                        name = "any"
                    }
                    errors.append(DiagnosticError.blockMissingTransition(block: block, socket: name))
                }
            }
        }
        
        for transition in layout.transitions {
            for socket in [transition.a, transition.b] {
                if try layout.transitions(from: socket).isEmpty {
                    errors.append(DiagnosticError.invalidTransition(transitionId: transition.id, socket: socket))
                }
            }
        }
    }
    
    func checkForLengthAndDistance(_ errors: inout [DiagnosticError]) {
        for block in layout.blocks {
            if block.length == nil {
                errors.append(DiagnosticError.blockMissingLength(block: block))
            }
            for bf in block.feedbacks {
                if bf.distance == nil {
                    errors.append(DiagnosticError.blockFeedbackMissingDistance(block: block, feedbackId: bf.feedbackId))
                }
            }
        }
        for turnout in layout.turnouts {
            if turnout.length == nil {
                errors.append(DiagnosticError.turnoutMissingLength(turnout: turnout))
            }
        }
        for train in layout.trains {
            if train.length == nil {
                errors.append(DiagnosticError.trainMissingLength(train: train))
            }
            if train.magnetDistance == nil {
                errors.append(DiagnosticError.trainMissingMagnetDistance(train: train))
            }
        }
    }
    
    func repair() {
        // Remove any transitions that are looping back to the same socket
        layout.transitions.removeAll { transition in
            return transition.a == transition.b
        }
        
        // Remove any train that do not exist anymore
        for block in layout.blocks {
            if let trainId = block.train?.trainId {
                if layout.train(for: trainId) == nil {
                    block.train = nil
                }
            }
            if let trainId = block.reserved?.trainId {
                if layout.train(for: trainId) == nil {
                    block.reserved = nil
                }
            }
        }
    }
}
