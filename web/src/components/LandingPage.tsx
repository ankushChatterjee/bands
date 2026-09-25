import { AlertTriangle } from 'lucide-react';

const features = [
  { title: 'A little sanity', text: 'Slot in your thoughts for a clearer mind', graphic: 'clarity' },
  { title: 'Thoughts age', text: 'A gentle color cue brings older thoughts back into view.', graphic: 'aging' },
  { title: 'Always within reach.', text: 'Lives within your toolbar', graphic: 'reach' },
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
      <rect x="49" y="9" width="39" height="28" rx="8" fill="#efeee7" stroke="#d8d6cc" />
      <path d="M57 18h23M57 25h16" stroke="#8c9689" strokeWidth="2.5" strokeLinecap="round" />
      <path d="M13 8v21l6-6 4.5 9 3.5-1.8-4.5-9H31L13 8Z" fill="#c77d62" stroke="#fffaf0" strokeWidth="1.3" strokeLinejoin="round" />
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
          <p className="hero-description">A mac toolbar app for slotting in your thoughts and tasks into clear bands for a multi-tasking chaotic work session</p>
          <a className="download-button" href="https://pub-690e2dfca33444bcb4b2e04193dc76fc.r2.dev/pre-alpha.1.5.0/bands-pre-alpha.1.5.0.dmg">
            <span className="apple-mark" aria-hidden="true"></span>
            <span>Download</span>
            <span className="download-badge"><AlertTriangle size={11} strokeWidth={2} aria-hidden="true" />pre-alpha</span>
          </a>
        </div>

        <div className="product-shot">
          <img src="/images/bands_screenshot.png" alt="bands app, a quiet space for organizing thoughts" />
          <div className="slot-card" aria-label="Slot thoughts with Jev">
            <span className="slot-card__label">Slot thoughts with <strong>Jev</strong></span>
          </div>
          <div className="slot-card slot-card--mcp" aria-label="Connect your AI using MCP">
            <span className="slot-card__label">Connect your AI using <strong>MCP</strong></span>
          </div>
        </div>
      </section>

      <section className="feature-list" aria-label="What bands does">
        {features.map(({ title, text, graphic }) => (
          <article className="feature-tile" key={title}>
            <div className="tile-visual">
              <FeatureGraphic type={graphic} />
            </div>
            <h2>{title}</h2>
            <p>{text}</p>
          </article>
        ))}
      </section>

    </main>
  );
}
