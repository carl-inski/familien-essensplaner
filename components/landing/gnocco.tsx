// Gnocco, das Maskottchen – dieselbe Figur wie in der iPhone-App
// (ios/Gnocchi/Design/Gnocco.swift). Reine Dekoration, daher aria-hidden.

type Mood = "happy" | "cheering" | "curious";

export function Gnocco({ mood = "happy", size = 96, className = "" }: { mood?: Mood; size?: number; className?: string }) {
  const shift = mood === "curious" ? 5 : 0;
  return (
    <svg
      viewBox="0 0 100 86"
      width={size}
      height={size * 0.86}
      className={`gnocco ${mood === "cheering" ? "gnocco-hop" : ""} ${className}`}
      aria-hidden
      focusable="false"
    >
      <defs>
        <linearGradient id="gnocco-dough" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="var(--g-dough)" />
          <stop offset="1" stopColor="var(--g-dough-shade)" />
        </linearGradient>
      </defs>
      <ellipse cx="50" cy="83" rx="34" ry="3.2" fill="rgba(0,0,0,0.1)" />
      {mood === "cheering" && (
        <g fill="var(--g-dough-shade)">
          <rect x="6" y="18" width="8" height="22" rx="4" transform="rotate(-38 10 29)" />
          <rect x="86" y="18" width="8" height="22" rx="4" transform="rotate(38 90 29)" />
        </g>
      )}
      <g className="gnocco-body">
        <path
          d="M50 4 C81 4 96 24 96 46 C96 69 78 80 50 80 C22 80 4 69 4 46 C4 24 19 4 50 4 Z"
          fill="url(#gnocco-dough)"
          stroke="var(--g-dough-shade)"
          strokeWidth="1.2"
        />
        <g fill="none" stroke="var(--g-dough-shade)" strokeWidth="2.2" strokeLinecap="round">
          <path d="M32 14 Q29 20 32 27" />
          <path d="M50 9 Q50 18 50 27" />
          <path d="M68 14 Q71 20 68 27" />
        </g>
        <g transform={`translate(${shift} 0)`}>
          {mood === "cheering" ? (
            <g fill="none" stroke="#1a1714" strokeWidth="3" strokeLinecap="round">
              <path d="M33 45 Q38 38 43 45" />
              <path d="M57 45 Q62 38 67 45" />
            </g>
          ) : (
            <g className="gnocco-eyes" fill="#1a1714">
              <ellipse cx="38" cy="43" rx="3.8" ry="5" />
              <ellipse cx="62" cy="43" rx="3.8" ry="5" />
              <circle cx="39.6" cy="40.8" r="1.2" fill="#fff" />
              <circle cx="63.6" cy="40.8" r="1.2" fill="#fff" />
            </g>
          )}
          {mood === "cheering" ? (
            <ellipse cx="50" cy="57" rx="6.5" ry="5" fill="#7a2413" />
          ) : mood === "curious" ? (
            <circle cx="50" cy="57" r="2.6" fill="#1a1714" />
          ) : (
            <path d="M43.5 55 Q50 62 56.5 55" fill="none" stroke="#1a1714" strokeWidth="2.8" strokeLinecap="round" />
          )}
        </g>
        <circle cx="29" cy="54" r="5.5" fill="var(--g-tomato-bright)" opacity="0.28" />
        <circle cx="71" cy="54" r="5.5" fill="var(--g-tomato-bright)" opacity="0.28" />
      </g>
    </svg>
  );
}
