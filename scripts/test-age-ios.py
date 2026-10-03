#!/usr/bin/env python3
"""One bounded Mini run, manually cleared by the conductor after CI is quiet."""
import contextlib
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import shutil
import stat
import time
import uuid

repo = Path(__file__).resolve().parent.parent

def preflight():
    if sys.platform != 'darwin':
        raise RuntimeError('iOS SDK tests require the shared Mac lane.')
    free = shutil.disk_usage(repo).free / 1024 ** 3
    print(f'Mini capacity: {free:.2f} GiB free; load {os.getloadavg()}; {os.cpu_count()} CPUs.', flush=True)
    if free < 20:
        raise RuntimeError(f'Mini has {free:.2f} GiB free; at least 20 GiB is required. No Xcode started.')
    processes = subprocess.run(['pgrep', '-fl', '[x]codebuild'], capture_output=True, text=True)
    if processes.returncode != 1:
        raise RuntimeError('Xcode lane is occupied or the process check failed: ' + (processes.stdout + processes.stderr).strip())

@contextlib.contextmanager
def nonwaiting_gate(root):
    # Same guard and ownership convention as mini-sim-slot.py, with NO waiting.
    fd = os.open(root / 'phren-ios-slots.guard', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if info.st_uid != os.getuid() or not stat.S_ISREG(info.st_mode):
            raise RuntimeError('Shared slot guard must be a regular file owned by this user.')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Shared slot guard is busy. No Mina waiter was queued.')
        yield
    finally:
        os.close(fd)


@contextlib.contextmanager
def exclusive_mini_slot():
    # Load the shared configuration/identity routine, never its blocking acquire.
    helper = Path.home() / '.phren/global/skills/test-machines/scripts/mini-sim-slot.py'
    spec = importlib.util.spec_from_file_location('mina_shared_slot_configuration', helper)
    if spec is None or spec.loader is None:
        raise RuntimeError('Shared Mini slot configuration is unavailable.')
    shared = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(shared)
    root = shared.ROOT
    slots = shared.SLOTS
    if root.resolve() != Path('/tmp').resolve() or len(slots) != 2:
        raise RuntimeError('Shared Mini slot configuration changed; review it before starting.')
    if {name for name, _ in slots} != {'phren-ios-build.lock', 'phren-ios-build-2.lock'}:
        raise RuntimeError('Shared Mini slot names changed; review before starting.')
    pid = os.getpid()
    start = shared.process_start(pid)
    if start is None:
        raise RuntimeError('Cannot verify the Mina slot holder identity.')
    token = uuid.uuid4().hex
    created = []
    with nonwaiting_gate(root):
        if any(os.path.lexists(root / name) for name, _ in slots):
            raise RuntimeError('Shared Mini lane is occupied. No queue or stale-slot reclamation.')
        # Claim BOTH entries atomically under the shared guard: one simulator run,
        # no second Xcode may acquire the remaining slot while this run is active.
        try:
            for name, device in slots:
                lock = root / name
                lock.mkdir(mode=0o700)
                created.append(lock)
                (lock / 'holder.json').write_text(json.dumps({
                    'pid': pid, 'processStart': start, 'acquiredAt': time.time(),
                    'device': device, 'minaToken': token,
                }) + '\n')
        except BaseException:
            for lock in reversed(created):
                (lock / 'holder.json').unlink(missing_ok=True)
                lock.rmdir()  # No recursive cleanup, ever.
            raise
    try:
        yield slots[0][1]
    finally:
        # Release only our exact records. A busy guard or changed record leaves
        # the directories for inspection; it never queues or deletes other work.
        with nonwaiting_gate(root):
            for lock in created:
                info = lock.lstat()
                if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
                    raise RuntimeError('Owned slot changed; preserve it for inspection.')
                record = json.loads((lock / 'holder.json').read_text())
                if (record.get('pid'), record.get('processStart'), record.get('minaToken')) != (pid, start, token):
                    raise RuntimeError('Slot holder changed; do not remove its reservation.')
            for lock in reversed(created):
                (lock / 'holder.json').unlink()
                lock.rmdir()


def focused_run(device):
    common = subprocess.check_output(['git', 'rev-parse', '--git-common-dir'], cwd=repo, text=True).strip()
    common = (repo / common).resolve()
    evidence = common.parent / '.dd-age-support-20261002'
    if evidence.exists():
        raise RuntimeError(f'Preserve existing evidence at {evidence}; choose a fresh run directory before retrying.')
    evidence.mkdir()
    command = ['xcodebuild', 'test', '-jobs', '2', '-project', 'Mina.xcodeproj', '-scheme', 'AgeSupport',
               '-destination', f'platform=iOS Simulator,id={device}',
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
    return result


def main():
    if sys.argv[1:] != ['--coordinated']:
        raise RuntimeError('Mina native work is on hold. Only after conductor coordination and quiet CI, invoke with --coordinated. Capacity alone is not a lane grant.')
    preflight()
    def stop(_signal, _frame):
        raise KeyboardInterrupt
    old = {sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
    try:
        with exclusive_mini_slot() as device:
            preflight()  # Fresh disk/load/no-Xcode check after the atomic claim.
            return focused_run(device)
    finally:
        for sig, handler in old.items():
            signal.signal(sig, handler)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        sys.exit(130)
