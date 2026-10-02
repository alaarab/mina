#!/usr/bin/env python3
"""Run Foundation-only age policy tests on macOS, without an iOS SDK or simulator.

The real Guidance, Predictor and Goals sources compile unchanged. Extract the
Foundation value dependencies from their app files; isolate preferences from the
App Group so this harness cannot change a family's settings.
"""
import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='mina-age-core-') as directory:
    root = Path(directory)
    source = root / 'Sources/MinaAgeCore'
    tests = root / 'Tests/MinaAgeCoreTests'
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    (root / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MinaAgeCore", products: [], targets: [
    .target(name: "MinaAgeCore"),
    .testTarget(name: "MinaAgeCoreTests", dependencies: ["MinaAgeCore"], swiftSettings: [.define("MINA_AGE_CORE")])
])
''')
    for path in ['Mina/Guide/Guidance.swift', 'Mina/Data/Prediction.swift', 'Mina/Data/Goals.swift']:
        (source / Path(path).name).write_text((repo / path).read_text())
    preferences = (repo / 'Mina/App/Preferences.swift').read_text()
    volume = preferences[preferences.index('enum VolumeUnit:'):preferences.index('// MARK: Stored settings')]
    summary = (repo / 'Mina/Data/Summary.swift').read_text()
    values = summary[summary.index('struct DaySummary {'):summary.index('    init(entries:')] + '}\n'
    formatting = summary[summary.index('enum Format {'):]
    (source / 'Dependencies.swift').write_text('import Foundation\n' + volume + values + formatting + '''
enum Prefs {
    static let defaults = UserDefaults(suiteName: "mina-age-core.''' + root.name + '''")!
    static var unit: VolumeUnit { .ounces }
}
''')
    (tests / 'AgeCoreTests.swift').write_text((repo / 'MinaTests/AgeCoreTests.swift').read_text())
    env = {**os.environ, 'CLANG_MODULE_CACHE_PATH': str(root / 'module-cache')}
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(root), '--jobs', '1', '--disable-sandbox', '--cache-path', str(root / 'cache'), '--config-path', str(root / 'config'), '--security-path', str(root / 'security'), '--manifest-cache', 'local'], env=env).returncode)
