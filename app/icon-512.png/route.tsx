import { ImageResponse } from "next/og";
import { AppIcon } from "@/lib/brand/app-icon";

export function GET() {
  return new ImageResponse(<AppIcon size={512} />, { width: 512, height: 512 });
}
