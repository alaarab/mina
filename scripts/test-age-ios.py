#!/usr/bin/env python3
"""One bounded Mini run. Coordinate the shared lane with the integrator first."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import shutil

repo = Path(__file__).resolve().parent.parent

def preflight():
    if sys.platform != 'darwin':
        raise RuntimeError('iOS SDK tests require the shared Mac lane.')
    free = shutil.disk_usage(repo).free / 1024 ** 3
    if free < 20:
        raise RuntimeError(f'Mini has {free:.2f} GiB free; at least 20 GiB is required. No Xcode started.')
    processes = subprocess.run(['pgrep', '-fl', '[x]codebuild.*(test|build|archive)'], capture_output=True, text=True)
    if processes.returncode != 1:
        raise RuntimeError('Xcode lane is occupied or the process check failed: ' + (processes.stdout + processes.stderr).strip())

try:
    preflight()
    if len(sys.argv) == 1:
        slot = Path.home() / '.phren/global/skills/test-machines/scripts/mini-sim-slot.sh'
        if not slot.is_file():
            raise RuntimeError('Shared Mini slot script is unavailable.')
        raise SystemExit(subprocess.run([str(slot), 'run', sys.executable, str(Path(__file__).resolve()), '--locked', '{udid}'], cwd=repo).returncode)
    if len(sys.argv) != 3 or sys.argv[1] != '--locked':
        raise RuntimeError('Run without arguments through the shared Mini lane.')
    holder = Path('/tmp/phren-ios-build.lock/holder.json')
    other = Path('/tmp/phren-ios-build-2.lock/holder.json')
    owned = False
    for path in [holder, other]:
        if path.is_file():
            record = json.loads(path.read_text())
            owned = owned or (record.get('pid') == os.getppid() and record.get('device') == sys.argv[2])
    if not owned:
        raise RuntimeError('A live shared Mini slot holder is required; run without --locked.')
    common = subprocess.check_output(['git', 'rev-parse', '--git-common-dir'], cwd=repo, text=True).strip()
    common = (repo / common).resolve()
    evidence = common.parent / '.dd-age-support-20261002'
    if evidence.exists():
        raise RuntimeError(f'Preserve existing evidence at {evidence}; choose a fresh run directory before retrying.')
    evidence.mkdir()
    command = ['xcodebuild', 'test', '-project', 'Mina.xcodeproj', '-scheme', 'AgeSupport',
               '-destination', f'platform=iOS Simulator,id={sys.argv[2]}',
               '-derivedDataPath', str(evidence / 'DerivedData'), '-resultBundlePath', str(evidence / 'AgeSupport.xcresult'),
               '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
               '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '120',
               '-maximum-test-execution-time-allowance', '180',
               '-only-testing:MinaTests/AgeCoreTests', '-only-testing:MinaTests/AgePersistenceTests',
               '-only-testing:MinaTests/GuidanceTests', '-only-testing:MinaTests/PredictorTests',
               '-only-testing:MinaTests/GoalsTests', '-only-testing:MinaTests/WeeklyDigestTests', '-only-testing:MinaTests/UnitTests/testCareScheduleUsesCalendarDates',
               '-only-testing:MinaTests/UnitTests/testWHOStandardsReturnThePublishedMedian',
               '-only-testing:MinaUITests/AgeSupportUITests']
    print(' '.join(command), flush=True)
    with (evidence / 'test.log').open('w') as output:
        child = subprocess.Popen(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            result = child.wait(timeout=900)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            raise RuntimeError(f'Bounded run stopped; preserve {evidence}.')
    print(f'Xcode exit {result}; evidence: {evidence}', flush=True)
    raise SystemExit(result)
except RuntimeError as error:
    print(str(error), file=sys.stderr)
    raise SystemExit(2)
