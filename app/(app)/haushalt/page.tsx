"use client";

import { useApp } from "@/components/app-data";
import { HouseholdView } from "@/components/household-view";
import { PageHeader } from "@/components/nav";

export default function HouseholdPage() {
  const { household } = useApp();
  return (
    <>
      <PageHeader title="Haushalt" subtitle={household.name} width="medium" back={{ href: "/woche", label: "Woche" }} />
      <HouseholdView />
    </>
  );
}
