const questions = [
  {
    q: "what is daemonflow?",
    a: "A menu bar app for macOS that turns your voice into clean text. Hold Fn, speak, and let go: it transcribes what you said, removes filler words and false starts, fixes punctuation, and pastes the result into whatever app you're typing in.",
  },
  {
    q: "does anything leave my mac?",
    a: "No. Transcription, cleanup and screen awareness all run on your Mac. Audio is kept in memory and never written to disk. The only network access is downloading models from Hugging Face when you choose one.",
  },
  {
    q: "is it reading my screen all the time?",
    a: "No. It reads the text of the frontmost window only when you press Fn, keeps the unusual words as spelling hints for that one dictation, and skips password fields entirely. Turn it off under Vocabulary, Use text on screen.",
  },
  {
    q: "which apps does it work with?",
    a: "Anything you can paste into. DaemonFlow pastes with Cmd+V and puts your clipboard back the way it was afterwards.",
  },
  {
    q: "which languages does it understand?",
    a: "English for now. Transcription and cleanup are both tuned for it.",
  },
  {
    q: "what do i need?",
    a: "A Mac with Apple Silicon running macOS 27 or later, and room for the models you pick: from 75 MB for the smallest Whisper model to 4.5 GB for the largest cleanup model.",
  },
  {
    q: "why does it ask for permissions again after an update?",
    a: "DaemonFlow isn't signed with a developer certificate yet, so macOS treats each new version as a different app. Remove it from Accessibility and Input Monitoring in System Settings, then add it again.",
  },
  {
    q: "is it really free?",
    a: "Yes. No account, no subscription, no word limit. The source is on GitHub.",
  },
];

export function Faq() {
  return (
    <section className="faq" id="faq" aria-labelledby="faq-title">
      <h2 id="faq-title" className="faq-title">
        frequently asked questions
      </h2>
      <p className="faq-sub">what to know about daemonflow, privacy, and getting started.</p>
      <div className="faq-list">
        {questions.map((item, index) => (
          <details key={item.q} open={index === 0}>
            <summary>{item.q}</summary>
            <p>{item.a}</p>
          </details>
        ))}
      </div>
    </section>
  );
}
