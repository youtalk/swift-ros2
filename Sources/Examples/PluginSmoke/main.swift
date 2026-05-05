// Phase-7 smoke target: depends on SwiftROS2GenPlugin to generate a
// Swift wrapper for the local msg/Bool.msg at build time, then prints
// the resulting type's `typeInfo.typeName`. A non-empty stdout proves
// the plugin invoked the CLI and the build dependency on the generated
// source resolved correctly.
//
// Note: the package name passed to the plugin is the *target* name
// (`PluginSmoke`), which the plugin pascal-cases to `Pluginsmoke`. The
// generated struct is therefore `BoolMsg` namespaced under that
// per-target Pluginsmoke/ directory rather than under StdMsgs/. That is
// fine for a smoke check — the smoke target is not consumed by any
// other target and is excluded from any release product.

import Foundation
import SwiftROS2CDR
import SwiftROS2Messages

print("PluginSmoke: BoolMsg.typeInfo.typeName = \(BoolMsg.typeInfo.typeName)")
