import io
import json
import unittest
from unittest.mock import patch

import release_notes as notes


class ReleaseNotesTest(unittest.TestCase):
    def test_previous_version(self):
        tags = ['v1.0.2', 'v1.0.3-rc.1', 'v1.0.3-rc.2', 'v1.0.3',
                'v1.0.4', 'windows-preview-123', 'v1.0.3-rc.01']
        self.assertEqual(notes.previous_tag('v1.0.3-rc.2', tags), 'v1.0.3-rc.1')
        self.assertEqual(notes.previous_tag('v1.0.3-rc.1', tags), 'v1.0.2')
        self.assertEqual(notes.previous_tag('v1.0.3', tags), 'v1.0.3-rc.2')
        self.assertIsNone(notes.previous_tag('v1.0.0', tags))
        self.assertEqual(notes.previous_tag('v1.0.5-rc.1', ['v1.0.3', 'v1.0.4-rc.9']), 'v1.0.4-rc.9')
        with self.assertRaises(ValueError):
            notes.previous_tag('invalid', tags)

    def test_history_includes_previous_rc_on_rewritten_branch(self):
        with patch.dict('os.environ', {'GITHUB_REF_NAME': 'v1.0.3-rc.2',
                                      'GITHUB_REPOSITORY': 'example/repo',
                                      'RELEASE_NOTES_API_KEY': ''}), \
                patch.object(notes, 'git', side_effect=['v1.0.2\nv1.0.3-rc.1\nv1.0.3-rc.2',
                                                        '- abc Fix login']) as git, \
                patch('sys.stdout', new_callable=io.StringIO) as output:
            notes.main()
        self.assertEqual(git.call_args_list[0].args, ('tag', '--list'))
        self.assertEqual(git.call_args_list[1].args, ('log', '--format=- %h %s', 'v1.0.3-rc.1..v1.0.3-rc.2'))
        self.assertIn('compare/v1.0.3-rc.1...v1.0.3-rc.2', output.getvalue())

    def test_no_key_and_api_failure_use_commit_list(self):
        with patch.object(notes, 'urlopen', side_effect=OSError('offline')) as call:
            self.assertEqual(notes.summarize('- abc Fix login', ''), '- abc Fix login')
            call.assert_not_called()
            self.assertEqual(notes.summarize('- abc Fix login', 'test-key'), '- abc Fix login')
            self.assertEqual(call.call_count, 1)

    def test_only_allowed_model_and_provider_fallback(self):
        response = io.BytesIO(json.dumps({
            'choices': [{'message': {'content': '### Fixed\n- Fixed login.'}}],
        }).encode())
        with patch.object(notes, 'urlopen', return_value=response) as call:
            commits = '- abc Fix login\n' * 2000
            result = notes.summarize(commits, 'test-key')
        self.assertIn('Fixed login', result)
        bodies = [json.loads(c.args[0].data) for c in call.call_args_list]
        self.assertEqual([b['model'] for b in bodies],
                         ['openai/gpt-oss-120b'])
        for body in bodies:
            self.assertEqual(body['messages'][1]['content'], commits)
            self.assertEqual(body['provider']['only'], ['groq', 'akashml/bf16'])
            self.assertEqual(body['provider']['order'], ['groq', 'akashml/bf16'])

    def test_empty_model_response_falls_back(self):
        def empty(*args, **kwargs):
            return io.BytesIO(b'{"choices":[{"message":{"content":""}}]}')
        with patch.object(notes, 'urlopen', side_effect=empty):
            self.assertEqual(notes.summarize('- abc Fix login', 'test-key'), '- abc Fix login')


if __name__ == '__main__':
    unittest.main()
