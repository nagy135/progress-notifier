import contextlib
import importlib.machinery
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch
import urllib.error

CLIENT = Path(__file__).resolve().parents[2] / "skills/progress-notifier/scripts/progress-notify"
loader = importlib.machinery.SourceFileLoader("progress_client", str(CLIENT))
spec = importlib.util.spec_from_loader(loader.name, loader)
client = importlib.util.module_from_spec(spec)
loader.exec_module(client)


class ClientTests(unittest.TestCase):
    def invoke(self, args, result=None, error=None):
        output, errors = io.StringIO(), io.StringIO()
        with patch("sys.argv", [str(CLIENT), *args]), patch.object(client, "request", return_value=result, side_effect=error) as request:
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                code = client.main()
        return code, output.getvalue(), errors.getvalue(), request

    def testStoppedAppIsSilentAndDoesNotRetry(self):
        code, out, err, request = self.invoke(["Build", "40", "90"], error=urllib.error.URLError(ConnectionRefusedError()))
        self.assertEqual((code, out, err), (0, "", ""))
        self.assertEqual(request.call_count, 1)

    def testTimeoutAlsoSkipsWithoutBlockingTheTask(self):
        code, out, err, _ = self.invoke(["Build", "40", "90"], error=TimeoutError())
        self.assertEqual((code, out, err), (0, "", ""))

    def testExplicitHealthDiagnosticReportsStoppedApp(self):
        code, out, err, _ = self.invoke(["--health", "--require-running"], error=urllib.error.URLError(ConnectionRefusedError()))
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("not listening", err)

    def testRunningAppReceivesUpdate(self):
        code, out, err, request = self.invoke(["Build", "40", "90"], result={"ok": True})
        self.assertEqual(code, 0)
        self.assertIn('"ok": true', out)
        self.assertEqual(err, "")
        request.assert_called_once_with("/items", "POST", {"name": "Build", "progress": 40, "etaSeconds": 90})

    def testProjectAndT3IconArePassedThrough(self):
        code, _, err, request = self.invoke(["Build", "40", "90", "--project", "nix-darwin",
                                            "--project-icon", '{"kind":"lucide","name":"snowflake","color":"blue"}'],
                                           result={"ok": True})
        self.assertEqual((code, err), (0, ""))
        request.assert_called_once_with("/items", "POST", {"name": "Build", "progress": 40, "etaSeconds": 90,
                                                          "project": "nix-darwin", "projectIcon": {
                                                              "kind": "lucide", "name": "snowflake", "color": "blue"}})

    def testT3DestinationIsPassedAsOneReference(self):
        code, _, err, request = self.invoke(["Build", "40", "90", "--t3-environment-id", "mac-123",
                                            "--t3-thread-id", "mcp:thread_456"], result={"ok": True})
        self.assertEqual((code, err), (0, ""))
        request.assert_called_once_with("/items", "POST", {"name": "Build", "progress": 40, "etaSeconds": 90,
                                                          "t3Thread": {"environmentId": "mac-123", "threadId": "mcp:thread_456"}})

    def testIncompleteInvalidAndCommandModeT3DestinationsAreRejected(self):
        for args in [["Build", "40", "90", "--t3-thread-id", "thread"],
                     ["Build", "40", "90", "--t3-environment-id", "mac"],
                     ["--list", "--t3-environment-id", "mac", "--t3-thread-id", "thread"]]:
            with self.assertRaises(SystemExit) as error:
                self.invoke(args)
            self.assertEqual(error.exception.code, 2)
        for invalid in ["", "../other", "id?prompt=bad", "bad\n", "é", "a" * 513]:
            for environment, thread in [(invalid, "thread"), ("mac", invalid)]:
                with self.assertRaises(SystemExit) as error:
                    self.invoke(["Build", "40", "90", "--t3-environment-id", environment, "--t3-thread-id", thread])
                self.assertEqual(error.exception.code, 2)

    def testInvalidIconJSONIsRejectedBeforeSending(self):
        for icon in ["not json", "[]", '"🎹"', '{"kind":"unknown"}']:
            with self.assertRaises(SystemExit) as error:
                self.invoke(["Build", "40", "90", "--project-icon", icon])
            self.assertEqual(error.exception.code, 2)

    def testDescriptionIsNormalizedAndSentWithItsPercentage(self):
        code, _, err, request = self.invoke(["Build", "40", "90", "--description", "  Compiled\r\nTests next  "], result={"ok": True})
        self.assertEqual((code, err), (0, ""))
        request.assert_called_once_with("/items", "POST", {"name": "Build", "progress": 40, "etaSeconds": 90,
                                                         "description": "Compiled\nTests next"})

    def testInvalidDescriptionsAndCommandCombinationsAreRejected(self):
        for args in [["Build", "40", "90", "--description", "x" * 2001],
                     ["Build", "40", "90", "--description", "Bad\x00text"],
                     ["--list", "--description", "Note"]]:
            with self.assertRaises(SystemExit) as error:
                self.invoke(args)
            self.assertEqual(error.exception.code, 2)
