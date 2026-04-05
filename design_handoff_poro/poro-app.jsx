/* global React, ReactDOM */

// ─────────────────────────────────────────────────────────────
// Poro — Floating AI Assistant (hi-fi)
// ─────────────────────────────────────────────────────────────

const TWEAKS_DEFAULTS = /*EDITMODE-BEGIN*/{
  "inputStyle": "flat",
  "accent": "beige",
  "initialState": "collapsed"
}/*EDITMODE-END*/;

const ACCENTS = {
  beige:   '#E8D4A8',
  cream:   '#F2E3C0',
  caramel: '#C9A876',
};

const SAMPLE_RESPONSE =
`Start from the platform's own primitives — system fonts, vibrancy, native hit targets. Then earn every pixel of deviation.

A few things that help:

• Use \`backdrop-filter\` aggressively. Nothing reads "native" faster than content bleeding through your chrome.
• Match the OS's motion curves. macOS favors a gentle overshoot around 280ms — not the flat ease-out the web defaults to.
• Keep chrome quiet. If the user can see the border, you've drawn it too hard.`;

// ─── Icons (inline SVG, Lucide-style) ────────────────────────
const Ico = {
  // Poro: small round furball with horns, beady eyes, pink tongue.
  poro: ({ size = 22, className, style } = {}) => (
    <img
      src="assets/poro.png"
      width={size}
      height={size}
      className={className}
      style={{ objectFit: 'contain', display: 'block', ...style }}
      alt="Poro"
    />
  ),
  sparkle: (p) => (
    <svg {...p} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M8 2 L9.2 6.1 L13.3 7.3 L9.2 8.5 L8 12.6 L6.8 8.5 L2.7 7.3 L6.8 6.1 Z"/>
      <path d="M13 2 L13.5 3.5 L15 4 L13.5 4.5 L13 6 L12.5 4.5 L11 4 L12.5 3.5 Z"/>
    </svg>
  ),
  pencilSquare: (p) => (
    <svg {...p} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M8.5 2.5 H3 a1 1 0 0 0 -1 1 v9 a1 1 0 0 0 1 1 h9 a1 1 0 0 0 1 -1 V7.5"/>
      <path d="M12 2 l2 2 l-6 6 H6 v-2 Z"/>
    </svg>
  ),
  clock: (p) => (
    <svg {...p} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="8" cy="8" r="6"/>
      <path d="M8 4.5 V 8 L 10.3 9.3"/>
    </svg>
  ),
  gear: (p) => (
    <svg {...p} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="8" cy="8" r="2"/>
      <path d="M8 1.5 v1.5 M8 13 v1.5 M14.5 8 h-1.5 M3 8 H1.5 M12.6 3.4 l-1 1 M4.4 11.6 l-1 1 M12.6 12.6 l-1 -1 M4.4 4.4 l-1 -1"/>
    </svg>
  ),
  returnArrow: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M11 3 V 6.5 a1.5 1.5 0 0 1 -1.5 1.5 H 3"/>
      <path d="M5.5 5.5 L 3 8 L 5.5 10.5"/>
    </svg>
  ),
};

// ─── Wallpaper + underlay window (the thing Poro floats over) ───
function Desktop() {
  return (
    <>
      <div className="wallpaper" />
      <div className="menubar">
        <span className="apple">􀣺</span>
        <span className="app-name">Xcode</span>
        <span className="menu-item">File</span>
        <span className="menu-item">Edit</span>
        <span className="menu-item">View</span>
        <span className="menu-item">Find</span>
        <span className="menu-item">Navigate</span>
        <span className="menu-item">Editor</span>
        <span className="menu-item">Product</span>
        <span className="menu-item">Window</span>
        <span className="menu-item">Help</span>
        <span className="right">
          <span>􀐫</span>
          <span>􀊪</span>
          <span>􀛭</span>
          <span style={{fontVariantNumeric: 'tabular-nums'}}>Tue 9:41 AM</span>
        </span>
      </div>

      <div className="underlay-window">
        <div className="underlay-chrome">
          <span className="tl" style={{'--c': '#ff5f57'}}/>
          <span className="tl" style={{'--c': '#febc2e'}}/>
          <span className="tl" style={{'--c': '#28c840'}}/>
          <span className="underlay-title">ContentView.swift</span>
        </div>
        <div className="underlay-body">
          <div><span className="com">// Poro · a floating assistant</span></div>
          <div><span className="kw">import</span> SwiftUI</div>
          <div>&nbsp;</div>
          <div><span className="kw">struct</span> CommandBar: <span className="kw">View</span> {'{'}</div>
          <div>&nbsp;&nbsp;<span className="kw">@State</span> <span className="kw">private</span> <span className="kw">var</span> query: String = <span className="str">""</span></div>
          <div>&nbsp;&nbsp;<span className="kw">@FocusState</span> <span className="kw">private</span> <span className="kw">var</span> focused: Bool</div>
          <div>&nbsp;</div>
          <div>&nbsp;&nbsp;<span className="kw">var</span> body: <span className="kw">some</span> View {'{'}</div>
          <div>&nbsp;&nbsp;&nbsp;&nbsp;HStack(spacing: 12) {'{'}</div>
          <div>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Image(systemName: <span className="str">"sparkles"</span>)</div>
          <div>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;.foregroundStyle(.white.opacity(<span className="str">0.5</span>))</div>
          <div>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;TextField(<span className="str">"Ask anything…"</span>, text: $query)</div>
          <div>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;.textFieldStyle(.plain)</div>
          <div>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;.focused($focused)</div>
          <div>&nbsp;&nbsp;&nbsp;&nbsp;{'}'}</div>
          <div>&nbsp;&nbsp;&nbsp;&nbsp;.frame(width: <span className="str">560</span>, height: <span className="str">56</span>)</div>
          <div>&nbsp;&nbsp;&nbsp;&nbsp;.background(.ultraThinMaterial)</div>
          <div>&nbsp;&nbsp;&nbsp;&nbsp;.clipShape(RoundedRectangle(cornerRadius: <span className="str">14</span>))</div>
          <div>&nbsp;&nbsp;{'}'}</div>
          <div>{'}'}</div>
        </div>
      </div>
    </>
  );
}

// ─── Input bar ────────────────────────────────────────────────
function InputBar({ inputStyle, query, setQuery, onSubmit, streaming, onStop, inputRef }) {
  const hasText = query.length > 0;
  const handleKey = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (!streaming && hasText) onSubmit();
    }
  };

  const field = (
    <>
      <Ico.poro size={22} className="spark poro-ico" />
      <input
        ref={inputRef}
        className="field"
        placeholder="Ask anything…"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={handleKey}
        autoFocus
      />
      {streaming && (
        <button className="stop-btn" onClick={onStop} aria-label="Stop">
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
            <circle cx="10" cy="10" r="9" stroke="currentColor" strokeWidth="1.5"/>
            <rect x="6.5" y="6.5" width="7" height="7" rx="1.25" fill="currentColor"/>
          </svg>
        </button>
      )}
      {!streaming && hasText && (
        <span className="return-key" aria-hidden><Ico.returnArrow/></span>
      )}
    </>
  );

  return (
    <div className={`input-row ${inputStyle}`}>
      {inputStyle === 'flat' ? field : <div className="field-wrap">{field}</div>}
    </div>
  );
}

// ─── Messages list ────────────────────────────────────────────
function Messages({ messages, streamingText }) {
  const scrollRef = React.useRef(null);
  React.useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages, streamingText]);

  return (
    <div className="msgs" ref={scrollRef}>
      {messages.map((m, i) => {
        const isLast = i === messages.length - 1;
        const showStreamCursor = m.role === 'assistant' && isLast && streamingText !== null;
        return (
          <div className="msg-block" key={i}>
            <div className={`msg-label ${m.role === 'assistant' ? 'poro-label' : ''}`}>
              {m.role === 'assistant' ? 'PORO' : 'YOU'}
            </div>
            <div className={`msg-body ${m.role === 'assistant' ? 'assistant' : ''}`}>
              <FormattedText text={m.content}/>
              {showStreamCursor && <span className="stream-cursor"/>}
            </div>
          </div>
        );
      })}
    </div>
  );
}

// Render inline `code` as <code> without pulling in markdown
function FormattedText({ text }) {
  const parts = [];
  let rest = text;
  let i = 0;
  const re = /`([^`]+)`/g;
  let last = 0;
  let m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) parts.push(<React.Fragment key={i++}>{text.slice(last, m.index)}</React.Fragment>);
    parts.push(<code key={i++}>{m[1]}</code>);
    last = m.index + m[0].length;
  }
  if (last < text.length) parts.push(<React.Fragment key={i++}>{text.slice(last)}</React.Fragment>);
  return <>{parts}</>;
}

// ─── Top toolbar (expanded only) ──────────────────────────────
function TopRow({ onNew }) {
  return (
    <div className="top-row">
      <Ico.poro size={18} className="spark poro-ico" />
      <div className="icons">
        <button className="icon-btn" title="New conversation" onClick={onNew}><Ico.pencilSquare/></button>
        <button className="icon-btn" title="History"><Ico.clock/></button>
        <button className="icon-btn" title="Settings"><Ico.gear/></button>
      </div>
    </div>
  );
}

// ─── Tweaks panel ─────────────────────────────────────────────
function TweaksPanel({ tweaks, update, onReset, onSummon, dismissed }) {
  return (
    <div className="tweaks">
      <h3>Tweaks</h3>

      <div className="grp">
        <div className="grp-label">Input bar</div>
        <div className="seg">
          {['flat','pill','bordered'].map(s => (
            <button key={s}
              aria-pressed={tweaks.inputStyle === s}
              onClick={() => update({ inputStyle: s })}>
              {s}
            </button>
          ))}
        </div>
      </div>

      <div className="grp">
        <div className="grp-label">Accent</div>
        <div className="swatches">
          {Object.entries(ACCENTS).map(([k, v]) => (
            <button key={k}
              className="sw"
              style={{ background: v }}
              aria-pressed={tweaks.accent === k}
              aria-label={k}
              onClick={() => update({ accent: k })}/>
          ))}
        </div>
      </div>

      <div className="grp">
        <div className="grp-label">Actions</div>
        <div className="row">
          {dismissed
            ? <button className="action primary" onClick={onSummon}>Summon ⌘␣</button>
            : <button className="action" onClick={onReset}>New conversation</button>}
        </div>
      </div>
    </div>
  );
}

// ─── Streaming simulator ──────────────────────────────────────
function useStreaming() {
  const [streamingText, setStreamingText] = React.useState(null);
  const timerRef = React.useRef(null);
  const abortRef = React.useRef(false);

  const start = (full, onChunk, onDone) => {
    abortRef.current = false;
    let i = 0;
    setStreamingText('');
    const tick = () => {
      if (abortRef.current) { onDone(full.slice(0, i)); setStreamingText(null); return; }
      // advance 2-6 chars per tick for smooth cadence
      i = Math.min(full.length, i + 2 + Math.floor(Math.random() * 4));
      const partial = full.slice(0, i);
      setStreamingText(partial);
      onChunk(partial);
      if (i < full.length) {
        timerRef.current = setTimeout(tick, 16 + Math.random() * 18);
      } else {
        onDone(partial);
        setStreamingText(null);
      }
    };
    tick();
  };

  const stop = () => {
    abortRef.current = true;
    if (timerRef.current) clearTimeout(timerRef.current);
  };

  React.useEffect(() => () => {
    abortRef.current = true;
    if (timerRef.current) clearTimeout(timerRef.current);
  }, []);

  return { streamingText, start, stop };
}

// ─── Root app ─────────────────────────────────────────────────
function App() {
  const [tweaks, setTweaks] = React.useState(TWEAKS_DEFAULTS);
  const [editMode, setEditMode] = React.useState(false);
  const [query, setQuery] = React.useState('');
  const [messages, setMessages] = React.useState([]);
  const [dismissed, setDismissed] = React.useState(false);
  const inputRef = React.useRef(null);
  const { streamingText, start, stop } = useStreaming();

  // Accent binding
  React.useEffect(() => {
    document.documentElement.style.setProperty('--accent', ACCENTS[tweaks.accent] || ACCENTS.beige);
    const c = ACCENTS[tweaks.accent] || ACCENTS.beige;
    // recompute soft accent
    const soft = hexToRgba(c, 0.14);
    document.documentElement.style.setProperty('--accent-soft', soft);
  }, [tweaks.accent]);

  // Edit-mode bridge for host Tweaks toggle
  React.useEffect(() => {
    const onMsg = (e) => {
      const d = e.data || {};
      if (d.type === '__activate_edit_mode') setEditMode(true);
      if (d.type === '__deactivate_edit_mode') setEditMode(false);
    };
    window.addEventListener('message', onMsg);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', onMsg);
  }, []);

  // Hotkey handling
  React.useEffect(() => {
    const onKey = (e) => {
      // ⌘␣ or Ctrl+␣ to summon
      if ((e.metaKey || e.ctrlKey) && e.code === 'Space') {
        e.preventDefault();
        setDismissed(false);
        setTimeout(() => inputRef.current?.focus(), 10);
      }
      // Escape dismisses
      if (e.key === 'Escape' && !dismissed) {
        if (streamingText !== null) { stop(); return; }
        setDismissed(true);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [dismissed, streamingText]);

  const updateTweak = (patch) => {
    setTweaks((t) => {
      const next = { ...t, ...patch };
      window.parent.postMessage({ type: '__edit_mode_set_keys', edits: patch }, '*');
      return next;
    });
  };

  const handleSubmit = () => {
    const q = query.trim();
    if (!q || streamingText !== null) return;
    const userMsg = { role: 'user', content: q };
    const next = [...messages, userMsg, { role: 'assistant', content: '' }];
    setMessages(next);
    setQuery('');
    start(
      SAMPLE_RESPONSE,
      (partial) => {
        setMessages((prev) => {
          const copy = prev.slice();
          copy[copy.length - 1] = { role: 'assistant', content: partial };
          return copy;
        });
      },
      (final) => {
        setMessages((prev) => {
          const copy = prev.slice();
          copy[copy.length - 1] = { role: 'assistant', content: final };
          return copy;
        });
      }
    );
  };

  const handleNew = () => {
    stop();
    setMessages([]);
    setQuery('');
    setTimeout(() => inputRef.current?.focus(), 50);
  };

  const expanded = messages.length > 0;

  return (
    <div className={`stage ${dismissed ? 'dismissed' : ''}`}>
      <Desktop />

      <div className={`poro ${expanded ? 'expanded' : 'collapsed'}`} data-screen-label={expanded ? '02 Expanded' : '01 Summoned'}>
        {expanded && (
          <>
            <TopRow onNew={handleNew} />
            <div className="msgs-wrap">
              <Messages messages={messages} streamingText={streamingText}/>
            </div>
            <div className="divider"/>
          </>
        )}
        <InputBar
          inputStyle={tweaks.inputStyle}
          query={query}
          setQuery={setQuery}
          onSubmit={handleSubmit}
          streaming={streamingText !== null}
          onStop={stop}
          inputRef={inputRef}
        />
      </div>

      {!expanded && !dismissed && (
        <div className="hint">
          <span>Press</span>
          <kbd>Esc</kbd>
          <span>to dismiss,</span>
          <kbd>⌘</kbd><kbd>␣</kbd>
          <span>to summon</span>
        </div>
      )}

      <TweaksPanel
        tweaks={tweaks}
        update={updateTweak}
        onReset={handleNew}
        onSummon={() => { setDismissed(false); setTimeout(() => inputRef.current?.focus(), 50); }}
        dismissed={dismissed}
      />
    </div>
  );
}

function hexToRgba(hex, a) {
  const h = hex.replace('#','');
  const n = parseInt(h.length === 3 ? h.split('').map(c=>c+c).join('') : h, 16);
  const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  return `rgba(${r}, ${g}, ${b}, ${a})`;
}

const root = ReactDOM.createRoot(document.getElementById('app'));
root.render(<App />);
