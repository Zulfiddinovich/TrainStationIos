//
//  LayoutTests.swift
//  BTrainTests
//
//  Created by Jean Bovet on 1/15/22.
//

import XCTest

@testable import BTrain

class LayoutTests: XCTestCase {

    func testValidation() throws {
        let layout = LayoutECreator().newLayout()
        let errors = try LayoutDiagnostic(layout: layout).check()
        XCTAssertEqual(errors.count, 0)
    }

    func testAddAndRemoveBlock() throws {
        let layout = Layout()
        
        let t1 = layout.newTrain("t1", name: "t1", address: 0, decoder: .MM)
        let b1 = layout.newBlock(name: "b1", type: .free)
        let b2 = layout.newBlock(name: "b2", type: .free)
        layout.link(from: b1.next, to: b2.previous)
        layout.link(from: b2.next, to: b1.previous)

        try layout.setTrain(t1.id, toBlock: b1.id, direction: .next)
        try layout.reserve(train: t1.id, fromBlock: b1.id, toBlock: b2.id, direction: .next)
        XCTAssertEqual(t1.blockId, b1.id)
        XCTAssertEqual(layout.transitions.count, 2)

        let b11 = layout.block(for: b1.id)
        XCTAssertTrue(b1 === b11)
        
        layout.remove(blockID: b1.id)
        XCTAssertNil(layout.block(for: b1.id))
        XCTAssertNil(t1.blockId)
        XCTAssertEqual(layout.transitions.count, 0)
    }

    func testAddAndRemoveFeedback() throws {
        let layout = Layout()
        let b1 = layout.newBlock(name: "b1", type: .free)

        let f1 = layout.newFeedback()
        layout.assign(b1, [f1])
        XCTAssertEqual(b1.feedbacks.count, 1)

        let f11 = layout.feedback(for: f1.id)
        XCTAssertEqual(f1, f11)
        
        layout.remove(feedbackID: f1.id)
        XCTAssertNil(layout.feedback(for: f1.id))
        XCTAssertEqual(b1.feedbacks.count, 0)
    }
    
    func testAddAndRemoveTurnout() throws {
        let layout = Layout()
        let b1 = layout.newBlock(name: "b1", type: .free)

        let t1 = layout.newTurnout(name: "t1", type: .doubleSlip)
        layout.link(from: b1.next, to: t1.socket0)
        layout.link(from: t1.socket1, to: b1.previous)
        XCTAssertEqual(layout.transitions.count, 2)

        let t11 = layout.turnout(for: t1.id)
        XCTAssertEqual(t1, t11)
        
        layout.remove(turnoutID: t1.id)
        XCTAssertNil(layout.turnout(for: t1.id))
        XCTAssertEqual(layout.transitions.count, 0)
    }
    
    func testTrainDirection() throws {
        let layout = LayoutBCreator().newLayout()
        let train1 = layout.trains[0]
        let block1 = layout.blocks[0]
        
        XCTAssertEqual(train1.directionForward, true)

        // Set the train direction
        try layout.setTrain(train1, direction: .previous)
        XCTAssertEqual(train1.directionForward, false)

        // Set the train inside a block with a specific direction which
        // is opposite of the train direction itself
        try layout.setTrain(train1.id, toBlock: block1.id, direction: .next)
        XCTAssertEqual(block1.train!.direction, .next)
        XCTAssertEqual(train1.directionForward, false)

        // Change the train direction - which should not affect the direction
        // of the train within the block (we need to explicitly call the toggle
        // method for this to happen!)
        try layout.setTrain(train1, direction: .next)
        XCTAssertEqual(train1.directionForward, true)
        XCTAssertEqual(block1.train!.direction, .next)
        
        // Now toggle the direction within the block itself
        try layout.toggleTrainDirectionInBlock(train1)
        XCTAssertEqual(train1.directionForward, true)
        XCTAssertEqual(block1.train!.direction, .previous)
    }
    
    func testTransitionsAndTurnoutsReservation() throws {
        let layout = LayoutBCreator().newLayout()
        let train1 = layout.trains[0]
        let train2 = layout.trains[1]
        
        let b1 = layout.block(at: 0)
        let b2 = layout.block(at: 1)
        let b3 = layout.block(at: 2)
        let b4 = layout.block(at: 3)
        
        try layout.setTrain(train1.id, toBlock: b1.id, direction: .next)
        try layout.setTrain(train2.id, toBlock: b3.id, direction: .next)
        
        XCTAssertNoThrow(try layout.reserve(train: train1.id, fromBlock: b1.id, toBlock: b2.id, direction: .next))
        
        // Ensure that train 2 cannot reserve its block because they are overlapping with
        // the turnout which itself is already reserved for train 1
        XCTAssertThrowsError(try layout.reserve(train: train2.id, fromBlock: b3.id, toBlock: b4.id, direction: .next))
        
        // Now let's free the blocks reserved by train 1 (but keep it in its block) and try again to reserve for train 2, it should work this time
        try layout.free(trainID: train1.id)
        XCTAssertNotNil(b1.reserved)
        XCTAssertNotNil(train1.blockId)

        XCTAssertNoThrow(try layout.reserve(train: train2.id, fromBlock: b3.id, toBlock: b4.id, direction: .next))
        
        // Now let's remove train 1 from the layout
        try layout.free(trainID: train1.id, removeFromLayout: true)
        XCTAssertNil(b1.reserved)
        XCTAssertNil(train1.blockId)
    }

}