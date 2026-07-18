import tempfile
import unittest
from pathlib import Path

from voice_management import delete_voice_file, normalize_voice_id


class VoiceManagementTest(unittest.TestCase):
    def test_deletes_uploaded_voice(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            voice = Path(temp_dir) / "sample.wav"
            voice.write_bytes(b"wav")

            removed = delete_voice_file(temp_dir, "sample.wav")

            self.assertEqual(removed, voice)
            self.assertFalse(voice.exists())

    def test_rejects_path_traversal(self):
        with self.assertRaises(ValueError):
            normalize_voice_id("../sample")


if __name__ == "__main__":
    unittest.main()
