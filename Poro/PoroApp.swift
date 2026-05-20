//
//  PoroApp.swift
//  Poro
//
//  Created by Andrew Vong on 4/17/26.
//

import SwiftUI

@main
struct PoroApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}
