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
import SwiftUI
import UniformTypeIdentifiers

// This is the class defining the document for a single layout document.
// It is used across all the views of the application and contains
// the data model shared by these views.
//                                          ┌──────────────────┐
//          ┌────────────────────────────┬──│  LayoutDocument  │───┬────────────────────────────┐
//          │                            │  └──────────────────┘   │                            │
//          │                            │                         │                            │
//          ▼                            ▼                         ▼                            ▼
//┌──────────────────┐         ┌──────────────────┐           ┌─────────┐             ┌──────────────────┐
//│ CommandInterface │◀────────│LayoutCoordinator │──────────▶│ Layout  │◀────────────│   Switchboard    │
//└──────────────────┘         └──────────────────┘           └─────────┘             └──────────────────┘
//
final class LayoutDocument: ObservableObject {
    
    enum ViewType: String, Identifiable, CaseIterable {
        var id : String { rawValue }

        case switchboard = "Switchboard"
        case routes = "Routes"
        case locomotives = "Locomotives"
        case blocks = "Blocks"
        case turnouts = "Turnouts"
        case feedback = "Feedback"
        case feedbackMonitor = "Feedback Monitor"
    }
        
    // Interface used to communicate with the real layout
    @Published var interface: CommandInterface? {
        didSet {
            connected = interface != nil
            coordinator?.interface = interface
            layout.interface = interface
        }
    }
    
    // The layout model
    @Published private(set) var layout: Layout

    @Published var coordinator: LayoutCoordinator?

    @Published var switchboard: SwitchBoard?
    
    // Used to perform the menu command "Diagnostics"
    @Published var diagnostics = false

    @Published var repairLayoutTrigger = false

    @Published var discoverLocomotiveConfirmation = false
    
    @Published var importPredefinedLayout = false

    // Used to perform the menu command "Switch View"
    @AppStorage("selectedView") var selectedView: ViewType = .switchboard

    // Toggle to display debug-only controls
    @AppStorage("debugMode") var debugMode = false
        
    // Returns true if the application is connected
    @Published var connected = false

    // The simulator that can be used in place of a real central station
    var simulator: MarklinCommandSimulator
        
    init(layout: Layout) {
        self.layout = layout
        self.simulator = MarklinCommandSimulator(layout: layout)
        change(layout: layout)
    }
    
    func change(layout: Layout) {
        self.layout = layout
        coordinator = LayoutCoordinator(layout: layout, interface: nil)
        switchboard = SwitchBoardFactory.generateSwitchboard(layout: layout)
    }
}

// MARK: ReferenceFileDocument

extension LayoutDocument: ReferenceFileDocument {
    
    static var readableContentTypes: [UTType] { [.json] }
    
    convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let layout = try LayoutDocument.layout(contentType: configuration.contentType, data: data)
        self.init(layout: layout)
    }
    
    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        switch configuration.contentType {
        case .json:
            return .init(regularFileWithContents: snapshot)
        default:
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
    }

    static func layout(contentType: UTType, data: Data) throws -> Layout {
        guard contentType == .json else {
            throw CocoaError(.fileReadUnknown)
        }
        let decoder = JSONDecoder()
        let layout = try decoder.decode(Layout.self, from: data)
        return layout
    }
    
    func snapshot(contentType: UTType) throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(layout)
        return data
    }

}

// MARK: Commands

extension LayoutDocument {
    
    func enable() {
        interface?.execute(command: .go())
    }
    
    func disable() {
        interface?.execute(command: .stop())
    }
    
    func start(train: Identifier<Train>, withRoute route: Identifier<Route>, toBlockId: Identifier<Block>?) throws {
        // Note: the simulator holds a reference to the layout and will automatically simulate any
        // enabled route associated with a train.
        try coordinator?.start(routeID: route, trainID: train, toBlockId: toBlockId)
    }
    
    func stop(train: Train) throws {
        guard let route = train.routeId else {
            throw LayoutError.trainNotAssignedToARoute(train: train)
        }
                
        try coordinator?.stop(routeID: route, trainID: train.id)
    }
    
    func connectToSimulator(completed: ((Error?) -> Void)? = nil) {
        simulator.start()
        connect(address: "localhost", port: 15731, completed: completed)
    }
    
    func connect(address: String, port: UInt16, completed: ((Error?) -> Void)? = nil) {
        let mi = MarklinInterface(server: address, port: port)
        mi.connect {
            DispatchQueue.main.async {
                self.interface = mi
                self.registerForDirectionChange()
                completed?(nil)
            }
        } onError: { error in
            DispatchQueue.main.async {
                self.interface = nil
                completed?(error)
            }
        } onUpdate: {
            DispatchQueue.main.async {
                self.interfaceFeedbackChanged()
                self.interfaceSpeedChanged()
            }
        } onStop: {
            // No-op
        }
    }
    
    func disconnect() {
        simulator.stop()
        interface?.disconnect() { }
        interface = nil
    }
    
    func applyTurnoutStateToDigitalController() {
        for t in layout.turnouts {
            coordinator?.stateChanged(turnout: t)
        }
    }
    
    func registerForDirectionChange() {
        guard let interface = interface else {
            return
        }

        interface.register(forDirectionChange: { address, direction in
            DispatchQueue.main.async {
                if let train = self.coordinator?.layout.trains.find(address: address) {
                    switch(direction) {
                    case .forward:
                        if train.directionForward == false {
                            train.directionForward = true
                            try? self.layout.toggleTrainDirectionInBlock(train)
                        }
                    case .backward:
                        if train.directionForward {
                            train.directionForward = false
                            try? self.layout.toggleTrainDirectionInBlock(train)
                        }
                    case .unknown:
                        BTLogger.error("Unknown direction \(direction) for \(address.toHex())")
                    }
                } else {
                    BTLogger.error("Unknown address \(address.toHex()) for change in direction event")
                }
            }
        })
    }
    
    // A feedback change event has been received from the Digital Control System
    func interfaceFeedbackChanged() {
        guard let interface = interface else {
            return
        }
        for cmdFeedback in interface.feedbacks {
            if let feedback = coordinator?.layout.feedbacks.find(deviceID: cmdFeedback.deviceID, contactID: cmdFeedback.contactID) {
                feedback.detected = cmdFeedback.value == 1
            }
        }
    }
            
    // A speed change event has been received from the Digital Control System
    func interfaceSpeedChanged() {
        guard let interface = interface else {
            return
        }
        for cmdSpeed in interface.speedChanges {
            if let train = coordinator?.layout.trains.find(address: cmdSpeed.address.address) {
                train.speed = cmdSpeed.speed
            }
        }
    }

}
