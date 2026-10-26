"use client";

import { useParams } from "next/navigation";
import { BookView } from "@/components/book-view";

export default function BookDetailPage() {
  const { id } = useParams<{ id: string }>();
  return <BookView id={id} />;
}
