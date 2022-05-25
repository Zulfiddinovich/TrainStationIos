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

/// These are the commands specific to the Marklin CS2/3
enum MarklinCommand {
    /// This command is received from the CS3 when requesting configuration data, like the list of locomotives.
    case configDataStream(length: UInt32?, data: [UInt8], descriptor: CommandDescriptor? = nil)
    
    /// Acknowledgement of the query direction command. This response contains the direction of the train, which makes
    /// it special because it is not a simple acknowledgement of the query direction as it contains the direction.
    case queryDirectionResponse(address: UInt32, decoderType: DecoderType?, direction: Command.Direction, descriptor: CommandDescriptor? = nil)
}
