import unittest

from notchy_dictation.postprocess import format_transcript


class FormatTranscriptTests(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(format_transcript(""), "")
        self.assertEqual(format_transcript(None), "")
        self.assertEqual(format_transcript("   \n "), "")

    def test_collapses_whitespace(self):
        self.assertEqual(format_transcript("  olá   mundo \n tudo  bem "), "Olá mundo tudo bem")

    def test_no_space_before_punctuation(self):
        self.assertEqual(format_transcript("olá , tudo bem ? sim ."), "Olá, tudo bem? Sim.")
        self.assertEqual(format_transcript("subiu 50 % ( muito )"), "Subiu 50% (muito)")

    def test_capitalizes_sentences_including_accents(self):
        self.assertEqual(format_transcript("ótimo. é isso! às vezes? sim"), "Ótimo. É isso! Às vezes? Sim")

    def test_keeps_numbers(self):
        self.assertEqual(format_transcript("custa 3,5 reais e pesa 1.200 kg"), "Custa 3,5 reais e pesa 1.200 kg")

    def test_never_changes_words(self):
        said = "Amanhã às nove horas vamos revisar o relatório com a equipe. Depois, eu envio um resumo por e-mail para todos."
        self.assertEqual(format_transcript(said), said)

    def test_starting_with_a_number(self):
        self.assertEqual(format_transcript("3 maçãs"), "3 maçãs")

    def test_quote_after_sentence(self):
        self.assertEqual(format_transcript('ele disse. "vamos"'), 'Ele disse. "Vamos"')


if __name__ == "__main__":
    unittest.main()
