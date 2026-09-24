import { Clock3, Layers3, Zap } from 'lucide-react';

const features = [
  { icon: Layers3, title: 'A little less clutter.', text: 'A clear place for the thoughts you want to keep.', graphic: 'clarity' },
  { icon: Clock3, title: 'Thoughts age', text: 'A gentle color cue brings older thoughts back into view.', graphic: 'aging' },
  { icon: Zap, title: 'Always within reach.', text: 'Capture a thought and get right back to your day.', graphic: 'reach' },
];

function FeatureGraphic({ type }: { type: string }) {
  if (type === 'clarity') {
    return (
      <svg className="feature-art feature-art--clarity" viewBox="0 0 96 46" fill="none" aria-hidden="true">
        <rect x="2" y="8" width="19" height="5" rx="2.5" fill="#b7bba9" />
        <rect x="2" y="20.5" width="28" height="5" rx="2.5" fill="#969f8f" />
        <rect x="2" y="33" width="37" height="5" rx="2.5" fill="#748574" />
      </svg>
    );
  }
  if (type === 'aging') {
    return (
      <svg className="feature-art feature-art--aging" viewBox="0 0 96 46" fill="none" aria-hidden="true">
        <rect x="2" y="20" width="11" height="6" rx="3" fill="#b8b69f" />
        <rect x="18" y="20" width="18" height="6" rx="3" fill="#d5a568" />
        <rect x="41" y="20" width="27" height="6" rx="3" fill="#c77d62" />
      </svg>
    );
  }
  return (
    <svg className="feature-art feature-art--reach" viewBox="0 0 96 46" fill="none" aria-hidden="true">
      <path d="M3 23h34" stroke="#d8c7a9" strokeWidth="2" strokeLinecap="round" strokeDasharray="2 5" />
      <circle cx="7" cy="23" r="4" fill="#c77d62" />
      <circle cx="22" cy="23" r="3" fill="#d5a568" />
      <circle cx="38" cy="23" r="5" fill="#aab19f" />
      <path d="M49 16h37M49 23h28M49 30h33" stroke="#8c9689" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

export default function LandingPage() {
  return (
    <main className="page-shell">
      <header className="site-header">
        <a className="brand" href="#top" aria-label="bands home">
          <img className="brand-icon" src="/images/app-icon.png" alt="" />
          <span>bands</span>
        </a>
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <h1>Calm the<br/><span>chaotic mind</span></h1>
          <p className="hero-description">A mac toolbar app for organizing a multi-taking chaotic work session</p>
          <a className="download-button" href="https://github.com/ankushChatterjee/bands/releases/latest">
            <span className="apple-mark" aria-hidden="true"></span>
            <span>Download</span>
          </a>
        </div>

        <div className="product-shot">
          <img src="/images/bands_screenshot.png" alt="bands app, a quiet space for organizing thoughts" />
          <div className="slot-card" aria-label="Slot thoughts with Jev">
            <span className="slot-card__label">Slot thoughts with <strong>Jev</strong></span>
          </div>
        </div>
      </section>

      <section className="feature-list" aria-label="What bands does">
        {features.map(({ icon: Icon, title, text, graphic }) => (
          <article className="feature-tile" key={title}>
            <div className="tile-visual">
              <FeatureGraphic type={graphic} />
              <div className="tile-top"><Icon size={21} strokeWidth={1.7}/></div>
            </div>
            <h2>{title}</h2>
            <p>{text}</p>
          </article>
        ))}
      </section>

    </main>
  );
}
