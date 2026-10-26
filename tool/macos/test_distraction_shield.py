#!/usr/bin/env python3
"""Compile the production shield class and check its offscreen AppKit contract.

Run on macOS: python3 tool/macos/test_distraction_shield.py
Requires Xcode command-line tools and a desktop login session; never orders a
window onscreen or activates an application. Live keyboard delivery, Spaces,
full-screen transitions and signed sandbox distribution need separate checks.
"""

from pathlib import Path
import re
import subprocess
import tempfile


project = Path(__file__).resolve().parents[2]
source = project / "apps/flutter/macos/Runner/DistractionProtectionController.swift"
# Compile the actual top-level class verbatim, excluding the Flutter controller.
# A missing/renamed class or changed top-level layout fails explicitly.
match = re.search(
    r"^final class DistractionShieldPanel: NSPanel \{\n.*?^\}",
    source.read_text(), re.M | re.S,
)
if match is None:
    raise SystemExit(f"Cannot extract DistractionShieldPanel from {source}")

checks = r'''
import AppKit

@main
struct DistractionShieldChecks {
  static func main() {
    _ = NSApplication.shared
    let panel = DistractionShieldPanel(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    defer { panel.close() }
    precondition(panel.canBecomeKey, "Shield must be eligible for keyboard focus")
    precondition(!panel.canBecomeMain, "Shield must not replace the main task window")
    precondition(!panel.styleMask.contains(.nonactivatingPanel), "Shield must activate")
    precondition(!panel.becomesKeyOnlyIfNeeded, "Shield must always accept key focus")
    precondition(panel.hidesOnDeactivate, "Never cover another application's keyboard focus")

    func key(_ text: String, _ code: UInt16,
             _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
      NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: 0, windowNumber: panel.windowNumber, context: nil,
        characters: text, charactersIgnoringModifiers: text,
        isARepeat: false, keyCode: code)!
    }
    precondition(panel.performKeyEquivalent(with: key("w", 13, [.command])))
    precondition(panel.performKeyEquivalent(with: key("w", 13, [.command, .option])))
    precondition(panel.performKeyEquivalent(with: key("\u{1b}", 53)))
    // The shortcut filter must leave navigation/return and guarded app quit to
    // normal AppKit handling. These checks do not simulate live key delivery.
    for event in [key("\t", 48), key("\t", 48, [.shift]), key("\r", 36),
                  key("q", 12, [.command])] {
      precondition(!panel.performKeyEquivalent(with: event),
        "Shield shortcut filter swallowed an unrelated key equivalent")
    }
    precondition(!panel.isVisible, "Check must stay offscreen")
    print("Distraction shield: key eligibility, activation, deactivation safety, Cmd-W/Escape and unrelated key equivalents passed")
  }
}
'''

with tempfile.TemporaryDirectory(prefix="pomodoist-shield-check-") as temporary:
    directory = Path(temporary)
    panel = directory / "DistractionShieldPanel.swift"
    harness = directory / "DistractionShieldChecks.swift"
    binary = directory / "distraction-shield-check"
    panel.write_text("import AppKit\n" + match.group(0) + "\n")
    harness.write_text(checks)
    sdk = subprocess.check_output(
        ["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True,
    ).strip()
    subprocess.run(
        ["xcrun", "swiftc", "-sdk", sdk, "-framework", "AppKit",
         str(panel), str(harness), "-o", str(binary)], check=True,
    )
    subprocess.run([str(binary)], check=True)
