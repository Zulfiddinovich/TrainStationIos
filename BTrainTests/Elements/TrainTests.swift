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

import XCTest

@testable import BTrain

class TrainTests: XCTestCase {
    
    let mi = MarklinInterface()

    func testCodable() throws {
        let t1 = Train(uuid: "1")
        t1.name = "Rail 2000"
        t1.address = 0x4001
        t1.speed.kph = 100
        t1.routeStepIndex = 1
        t1.position = 7
        t1.blockId = Identifier<Block>(uuid: "111")
        t1.routeId = Identifier<Route>(uuid: "1212")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(t1)

        let decoder = JSONDecoder()
        let t2 = try decoder.decode(Train.self, from: data)
        
        XCTAssertEqual(t1.id, t2.id)
        XCTAssertEqual(t1.name, t2.name)
        XCTAssertEqual(t1.address, t2.address)
        XCTAssertEqual(t1.speed.decoderType, t2.speed.decoderType)
        XCTAssertEqual(t1.speed.kph, 100)
        XCTAssertEqual(t2.speed.kph, 0) // When decoding a speed, it always is initialized back to 0 for security reason
        XCTAssertEqual(t1.routeStepIndex, t2.routeStepIndex)
        XCTAssertEqual(t1.position, t2.position)
        XCTAssertEqual(t1.blockId, t2.blockId)
        XCTAssertEqual(t1.routeId, t2.routeId)
    }
    
    func testSpeedInitialization() {
        let s1 = TrainSpeed(kph: 100, decoderType: .MFX)
        assertSpeed(s1, mi, kph: 100, steps: 63, value: 500)
        
        let s2 = TrainSpeed(steps: SpeedStep(value: 63), decoderType: .MFX)
        assertSpeed(s2, mi, kph: 100, steps: 63, value: 500)
    }
    
    func testSpeedSteps() {
        let t1 = Train(uuid: "1")
        t1.address = 0x4001
        
        XCTAssertEqual(t1.speed.speedTable.count, Int(DecoderType.MFX.steps) + 1)
        
        t1.speed.kph = 0
        assertSpeed(t1.speed, mi, kph: 0, steps: 0, value: 0)
        
        t1.speed.kph = 100
        assertSpeed(t1.speed, mi, kph: 100, steps: 63, value: 500)

        t1.speed.kph = 200
        assertSpeed(t1.speed, mi, kph: 200, steps: 126, value: 1000)

        t1.speed.kph = 300
        assertSpeed(t1.speed, mi, kph: 200, steps: 126, value: 1000)

        t1.speed.steps = SpeedStep.zero
        assertSpeed(t1.speed, mi, kph: 0, steps: 0, value: 0)
        
        t1.speed.steps = SpeedStep(value: 63)
        assertSpeed(t1.speed, mi, kph: 100, steps: 63, value: 500)

        t1.speed.steps = SpeedStep(value: 126)
        assertSpeed(t1.speed, mi, kph: 200, steps: 126, value: 1000)

        t1.speed.steps = SpeedStep(value: 200)
        assertSpeed(t1.speed, mi, kph: 200, steps: 126, value: 1000)

        t1.decoder = .MM
        XCTAssertEqual(t1.speed.speedTable.count, Int(DecoderType.MM.steps) + 1)
        
        t1.speed.kph = 0
        XCTAssertEqual(t1.speed.steps.value, 0)
        
        t1.speed.kph = 100
        XCTAssertEqual(t1.speed.steps.value, 7)

        t1.speed.kph = 200
        XCTAssertEqual(t1.speed.steps.value, 14)
    }
    
    func testSpeedTableWithUndefinedValue() {
        let t1 = Train(uuid: "1")
        t1.address = 0x4001
        
        XCTAssertEqual(t1.speed.speedTable.count, Int(DecoderType.MFX.steps) + 1)

        let fixedSpeedStep = SpeedStep(value: 10)
        
        t1.speed.steps = fixedSpeedStep
        
        XCTAssertEqual(t1.speed.steps.value, 10)
        XCTAssertEqual(t1.speed.kph, 15)
        
        t1.speed.speedTable[10] = .init(steps: fixedSpeedStep, speed: nil)

        t1.speed.steps = fixedSpeedStep

        XCTAssertEqual(t1.speed.steps.value, 9) // 9 because of the interpolation
        XCTAssertEqual(t1.speed.kph, 15)
        
        // Put back the speed value
        t1.speed.speedTable[10] = .init(steps: fixedSpeedStep, speed: 15)

        t1.speed.steps = fixedSpeedStep

        XCTAssertEqual(t1.speed.steps.value, 10)
        XCTAssertEqual(t1.speed.kph, 15)
    }
    
    private func assertSpeed(_ speed: TrainSpeed, _ interface: CommandInterface, kph: TrainSpeed.UnitKph, steps: UInt16, value: UInt16) {
        XCTAssertEqual(speed.kph, kph)
        XCTAssertEqual(speed.steps.value, steps)
        
        let actualValue = interface.speedValue(for: speed.steps, decoder: speed.decoderType)
        XCTAssertEqual(actualValue.value, value)
        XCTAssertEqual(interface.speedSteps(for: actualValue, decoder: speed.decoderType).value, steps)
    }
    
}
