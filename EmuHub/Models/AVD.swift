//
//  AVD.swift
//  EmuHub
//
//  Created by Munyaradzi Chigangawa on 27/1/2026.
//

import Foundation

struct AVD: Identifiable, Hashable {
    /// Stable identity derived from the AVD name. Using a fresh UUID per instance
    /// would make every refresh look like an all-new list to SwiftUI, forcing a
    /// full teardown/rebuild of every card each poll. AVD names are unique on disk.
    var id: String { name }
    let name: String
}
