// Linien-Icons im Stil von SF Symbols (1.8px Strich, runde Enden)

import type { SVGProps } from "react";

type P = SVGProps<SVGSVGElement> & { size?: number };

function Svg({ size = 22, children, ...rest }: P & { children: React.ReactNode }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...rest}>
      {children}
    </svg>
  );
}

export const IconCalendar = (p: P) => (
  <Svg {...p}><rect x="3.5" y="5" width="17" height="15" rx="3" /><path d="M3.5 10h17M8 3v4M16 3v4" /></Svg>
);
export const IconBook = (p: P) => (
  <Svg {...p}><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5v-15Z" /><path d="M4 20.5A2.5 2.5 0 0 0 6.5 23H20v-5" /></Svg>
);
export const IconShelf = (p: P) => (
  <Svg {...p}><path d="M4 4v16M8.5 4v16M13 6l3.5 14M3 20h18" /></Svg>
);
export const IconCart = (p: P) => (
  <Svg {...p}><path d="M3 4h2.2l2.3 11.2a1.5 1.5 0 0 0 1.5 1.2h8.6a1.5 1.5 0 0 0 1.5-1.1L21 8H6.2" /><circle cx="9.5" cy="20" r="1.3" /><circle cx="17" cy="20" r="1.3" /></Svg>
);
export const IconPeople = (p: P) => (
  <Svg {...p}><circle cx="9" cy="8" r="3.2" /><path d="M3 19.5c.6-3.3 3-5 6-5s5.4 1.7 6 5" /><circle cx="17" cy="9" r="2.6" /><path d="M16.5 14.6c2.4.2 4 1.7 4.5 4.4" /></Svg>
);
export const IconChevronLeft = (p: P) => <Svg {...p}><path d="m15 5-7 7 7 7" /></Svg>;
export const IconChevronRight = (p: P) => <Svg {...p}><path d="m9 5 7 7-7 7" /></Svg>;
export const IconChevronDown = (p: P) => <Svg {...p}><path d="m5 9 7 7 7-7" /></Svg>;
export const IconPlus = (p: P) => <Svg {...p}><path d="M12 5v14M5 12h14" /></Svg>;
export const IconMinus = (p: P) => <Svg {...p}><path d="M5 12h14" /></Svg>;
export const IconClose = (p: P) => <Svg {...p}><path d="M6 6l12 12M18 6 6 18" /></Svg>;
export const IconCheck = (p: P) => <Svg {...p}><path d="m5 12.5 4.5 4.5L19 7.5" /></Svg>;
export const IconSearch = (p: P) => <Svg {...p}><circle cx="11" cy="11" r="6.5" /><path d="m16 16 4.5 4.5" /></Svg>;
export const IconSparkles = (p: P) => (
  <Svg {...p}><path d="M10 3.5 11.6 8a2 2 0 0 0 1.3 1.3L17.5 11l-4.6 1.6a2 2 0 0 0-1.3 1.3L10 18.5l-1.6-4.6a2 2 0 0 0-1.3-1.3L2.5 11l4.6-1.6A2 2 0 0 0 8.4 8L10 3.5Z" /><path d="M18 3v4M16 5h4M19 16v3M17.5 17.5h3" /></Svg>
);
export const IconClock = (p: P) => <Svg {...p}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></Svg>;
export const IconFork = (p: P) => (
  <Svg {...p}><path d="M7 3v7a2 2 0 0 0 2 2v9M11 3v7a2 2 0 0 1-2 2M9 3v5M17 21V3c-2 1-3 4-3 7v4h3" /></Svg>
);
export const IconLeaf = (p: P) => (
  <Svg {...p}><path d="M5 19c0-8 5-13 15-14-1 10-6 15-14 15" /><path d="M5 19 13 11" /></Svg>
);
export const IconFish = (p: P) => (
  <Svg {...p}><path d="M3 12c3-4.5 7-6 10.5-6 3 0 5.5 2.5 7.5 6-2 3.5-4.5 6-7.5 6C10 18 6 16.5 3 12Z" /><path d="M3 12 1 9M3 12l-2 3" /><circle cx="15.5" cy="10.5" r=".8" fill="currentColor" /></Svg>
);
export const IconMeat = (p: P) => (
  <Svg {...p}><path d="M14.5 3.5c3.5 0 6 2.5 6 6 0 5-5.5 9-10 9-1.2 0-2-.3-2.6-.8l-3.4 3.4a1.4 1.4 0 0 1-2-2l3.4-3.4C5.3 14.6 5 13.8 5 12.6c0-4.5 4-9.1 9.5-9.1Z" fill="currentColor" fillOpacity={0.28} /></Svg>
);
export const IconShare = (p: P) => (
  <Svg {...p}><path d="M12 15V3.5M8 7.5l4-4 4 4" /><path d="M7 11H6a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2h-1" /></Svg>
);
export const IconCopy = (p: P) => (
  <Svg {...p}><rect x="8.5" y="8.5" width="11.5" height="11.5" rx="2.5" /><path d="M15.5 8.5V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7.5a2 2 0 0 0 2 2h2.5" /></Svg>
);
export const IconEdit = (p: P) => (
  <Svg {...p}><path d="M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16v4Z" /><path d="m13.5 6.5 4 4" /></Svg>
);
export const IconTrash = (p: P) => (
  <Svg {...p}><path d="M4 7h16M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13M10 11v5.5M14 11v5.5" /></Svg>
);
export const IconMore = (p: P) => (
  <Svg {...p}><circle cx="5.5" cy="12" r="1.2" fill="currentColor" /><circle cx="12" cy="12" r="1.2" fill="currentColor" /><circle cx="18.5" cy="12" r="1.2" fill="currentColor" /></Svg>
);
export const IconArrowUp = (p: P) => <Svg {...p}><path d="M12 19V5M6 11l6-6 6 6" /></Svg>;
export const IconArrowDown = (p: P) => <Svg {...p}><path d="M12 5v14M6 13l6 6 6-6" /></Svg>;
export const IconHistory = (p: P) => (
  <Svg {...p}><path d="M3.5 12a8.5 8.5 0 1 0 2.5-6L3.5 8.5" /><path d="M3.5 4v4.5H8M12 7.5V12l3 2" /></Svg>
);
export const IconDownload = (p: P) => (
  <Svg {...p}><path d="M12 4v11M7.5 10.5 12 15l4.5-4.5M4 19.5h16" /></Svg>
);
export const IconUpload = (p: P) => (
  <Svg {...p}><path d="M12 15V4M7.5 8.5 12 4l4.5 4.5M4 19.5h16" /></Svg>
);
export const IconWarning = (p: P) => (
  <Svg {...p}><path d="M12 4 2.8 19.5h18.4L12 4Z" /><path d="M12 10v4.5M12 17.2v.3" /></Svg>
);
export const IconChef = (p: P) => (
  <Svg {...p}><path d="M7 14.5V20h10v-5.5" /><path d="M7 14.5a4 4 0 0 1-1-7.8A4.5 4.5 0 0 1 12 4a4.5 4.5 0 0 1 6 2.7 4 4 0 0 1-1 7.8H7Z" /><path d="M7 17h10" /></Svg>
);
export const IconLogout = (p: P) => (
  <Svg {...p}><path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4M10 16l-4-4 4-4M6 12h10" /></Svg>
);
export const IconCamera = (p: P) => (
  <Svg {...p}><path d="M4 8a2 2 0 0 1 2-2h2l1.5-2h5L16 6h2a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8Z" /><circle cx="12" cy="13" r="3.5" /></Svg>
);
export const IconLeftovers = (p: P) => (
  <Svg {...p}><path d="M4 11h16v2a7 7 0 0 1-7 7h-2a7 7 0 0 1-7-7v-2Z" /><path d="M9 7c0-1.5 1-2 1-3.5M13 7c0-1.5 1-2 1-3.5" /></Svg>
);
export const IconNote = (p: P) => (
  <Svg {...p}><path d="M5 4.5h14v10L14 19.5H5v-15Z" /><path d="M14 19.5v-5h5M8.5 9h7M8.5 12.5h4" /></Svg>
);
export const IconLink = (p: P) => (
  <Svg {...p}><path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1" /><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1" /></Svg>
);
export const IconHome = (p: P) => (
  <Svg {...p}><path d="M4 10.5 12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-5.5h-5V20H5a1 1 0 0 1-1-1v-8.5Z" /></Svg>
);
