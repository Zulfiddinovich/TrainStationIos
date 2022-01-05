//
//  SimulatorTrainControlView.swift
//  BTrain
//
//  Created by Jean Bovet on 1/3/22.
//

import SwiftUI

struct SimulatorTrainControlView: View {
    
    let simulator: MarklinCommandSimulator
    @ObservedObject var train: SimulatorTrain
    
    var body: some View {
        HStack {
            Button {
                simulator.setTrainDirection(train: train, directionForward: !train.directionForward)
            } label: {
                if train.directionForward {
                    Image(systemName: "arrowtriangle.right.fill")
                } else {
                    Image(systemName: "arrowtriangle.left.fill")
                }
            }.buttonStyle(.borderless)
            
            Slider(
                value: $train.speedAsDouble,
                in: 0...100
            ) {
            } onEditingChanged: { editing in
                simulator.setTrainSpeed(train: train, value: train.speed)
            }
            
            Text("\(Int(train.speed)) km/h")
        }
    }
}

extension SimulatorTrain {
    
    // Necessary because SwiftUI Slider requires a Double
    // while speed is UInt16.
    var speedAsDouble: Double {
        get {
            return Double(self.speed)
        }
        set {
            self.speed = UInt16(newValue)
        }
    }
    
}

struct SimulatorTrainControlView_Previews: PreviewProvider {

    static let layout = LayoutACreator().newLayout()
    
    static var previews: some View {
        SimulatorTrainControlView(simulator: MarklinCommandSimulator(layout: layout),
                                  train: .init(train: layout.trains[0]))
    }
}