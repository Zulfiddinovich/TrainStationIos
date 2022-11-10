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

// TODO: move this into its own class
extension LayoutDocument {
        
    func discoverLocomotives(merge: Bool, completion: CompletionBlock? = nil) {
        // TODO: unregister at the end of the discovery
        interface.callbacks.register(forLocomotivesQuery: { [weak self] locomotives in
            DispatchQueue.main.async {
                self?.process(locomotives: locomotives, merge: merge)
                completion?()
            }
        })

        interface.execute(command: .locomotives(), completion: nil)
    }
        
    private func process(locomotives: [CommandLocomotive], merge: Bool) {
        var newLocs = [Locomotive]()
        for cmdLoc in locomotives {
            if let locUID = cmdLoc.uid, let loc = layout.locomotives.first(where: { $0.id.uuid == String(locUID) }), merge {
                mergeLocomotive(cmdLoc, with: loc)
            } else if let locAddress = cmdLoc.address, let loc = layout.locomotives.find(address: locAddress, decoder: cmdLoc.decoderType), merge {
                mergeLocomotive(cmdLoc, with: loc)
            } else {
                let loc: Locomotive
                if let locUID = cmdLoc.uid {
                    loc = Locomotive(uuid: String(locUID))
                } else {
                    loc = Locomotive()
                }
                mergeLocomotive(cmdLoc, with: loc)
                newLocs.append(loc)
            }
        }
        
        if merge {
            layout.locomotives.append(contentsOf: newLocs)
        } else {
            layout.removeAllLocomotives()
            layout.locomotives = newLocs
        }
    }
    
    private func mergeLocomotive(_ locomotive: CommandLocomotive, with loc: Locomotive) {
        if let name = locomotive.name {
            loc.name = name
        }
        if let address = locomotive.address {
            loc.address = address
        }
        if let maxSpeed = locomotive.maxSpeed {
            loc.speed.maxSpeed = LocomotiveSpeed.UnitKph(maxSpeed)
        }
        loc.decoder = locomotive.decoderType ?? .MFX
        if let icon = locomotive.icon {
            try! locomotiveIconManager.setIcon(icon, locId: loc.id)
        }
    }

}
