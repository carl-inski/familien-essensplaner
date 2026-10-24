"use client";

// Haushalt & Konto oben rechts – wie das Konto-Symbol in iOS-Apps.

import Link from "next/link";
import { useApp } from "./app-data";
import { Avatar } from "./ui";

export function AccountButton() {
  const { me } = useApp();
  return (
    <Link href="/haushalt" aria-label="Haushalt und Konto" className="pressable ml-1 flex h-9 w-9 items-center justify-center rounded-full">
      <Avatar member={me} size={30} />
    </Link>
  );
}
