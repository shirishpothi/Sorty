"""Exercise guard behavior without compiling Sorty or touching its index."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'agent_run.py'


class AgentRunTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'user.name', 'Guard test')
        (self.root / '.gitignore').write_text('.agent-local/\n')
        (self.root / 'source').write_text('original')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, check=True, capture_output=True)

    def run_guard(self, code, check=True):
        return subprocess.run([sys.executable, str(SCRIPT), *(['--check'] if check else []),
                               '--', sys.executable, '-c', code], cwd=self.root, capture_output=True)

    def test_stable_and_child_failure(self):
        self.assertEqual(self.run_guard('pass').returncode, 0)
        self.assertEqual(self.run_guard('raise SystemExit(9)').returncode, 9)

    def test_changes_invalidate_evidence(self):
        result = self.run_guard("from pathlib import Path; Path('source').write_text('changed')")
        self.assertEqual(result.returncode, 76)
        self.assertEqual((self.root / 'source').read_text(), 'changed')

    def test_mutation_mode_allows_edits(self):
        self.assertEqual(self.run_guard("from pathlib import Path; Path('new').touch()", False).returncode, 0)

    def test_concurrent_command_is_refused_and_lock_releases(self):
        owner = subprocess.Popen([sys.executable, str(SCRIPT), '--', sys.executable, '-c',
                                  "from pathlib import Path; import time; Path('.agent-local/ready').touch(); time.sleep(30)"],
                                 cwd=self.root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while not (self.root / '.agent-local/ready').exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.root / '.agent-local/ready').exists())
            self.assertEqual(self.run_guard('pass').returncode, 75)
        finally:
            import signal
            os.killpg(owner.pid, signal.SIGTERM)
            owner.wait()
        self.assertEqual(self.run_guard('pass').returncode, 0)


if __name__ == '__main__':
    unittest.main()
