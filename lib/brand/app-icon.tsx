// PNG-App-Icon für PWA und iOS-Homescreen (gerendert über next/og)

export function AppIcon({ size }: { size: number }) {
  return (
    <div style={{ width: size, height: size, display: "flex", background: "#e8590c", alignItems: "center", justifyContent: "center" }}>
      <svg width={size} height={size} viewBox="0 0 64 64">
        <circle cx="32" cy="33" r="14" fill="none" stroke="#fff" strokeWidth="3.5" />
        <circle cx="32" cy="33" r="7.5" fill="#fff" fillOpacity=".85" />
        <path d="M10.5 14v9.5a3 3 0 0 0 6 0V14M13.5 14v38" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" />
        <path d="M52 52V14c-3.2 1.6-4.6 6-4.6 11.5V33H52" fill="#fff" stroke="#fff" strokeWidth="2.4" strokeLinejoin="round" strokeLinecap="round" />
      </svg>
    </div>
  );
}
