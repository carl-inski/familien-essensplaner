import { ImageResponse } from "next/og";
import { AppIcon } from "@/lib/brand/app-icon";

export function GET() {
  return new ImageResponse(<AppIcon size={192} />, { width: 192, height: 192 });
}
